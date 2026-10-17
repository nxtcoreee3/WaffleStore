// Protocol, retry and redirect behavior adapted from majd/ipatool (MIT),
// pkg/appstore/appstore_login.go at 3411d57. No CLI or password persistence.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AuthenticationError: Error, LocalizedError, Equatable {
    case invalidCode, invalidCredentials, twoFactorRequired, verificationRejected, accountDisabled
    case apple(failure: String, message: String)
    case invalidResponse(Int), http(Int), rateLimited, retryLater, network(Int)
    case invalidRedirect, tooManyRedirects, invalidSession

    public var errorDescription: String? {
        switch self {
        case .invalidCode: return "The verification code must contain exactly six digits."
        case .invalidCredentials: return "Apple rejected the Apple ID or password."
        case .twoFactorRequired: return "Apple requires a verification code from your trusted device."
        case .verificationRejected: return "Apple did not complete verification. Enter a fresh 2FA code."
        case .accountDisabled: return "Apple reports that this account is disabled or locked."
        case .apple(let failure, let message): return message.isEmpty ? "Apple rejected sign-in (code \(failure))." : message
        case .invalidResponse(let status): return "Apple returned no usable login response (HTTP \(status)). Try again later or from another network."
        case .http(let status): return "Apple authentication failed after bounded retries (HTTP \(status))."
        case .rateLimited: return "Apple rate limited sign-in. Wait before trying again."
        case .retryLater: return "Apple requested a wait longer than 30 seconds. Try again later."
        case .network(let code): return "Authentication network request failed (code \(code)). Check your connection."
        case .invalidRedirect: return "Apple authentication endpoint or redirect was rejected. No credentials were forwarded."
        case .tooManyRedirects: return "Apple returned too many authentication redirects."
        case .invalidSession: return "The saved Store session is invalid. Sign in again."
        }
    }
}

public enum AuthenticationOutcome { case authenticated(StoreAccount), twoFactorRequired([StoreCookie]) }
public enum AuthenticationStage: String, Sendable {
    case bag = "Resolving Store Bag", sap = "Initializing SAP", signing = "Signing authentication request"
    case authenticating = "Contacting Apple", redirect = "Following Store pod", retrying = "Waiting to retry"
    case prepared = "Using prepared SAP session"
    case twoFactor = "Enter the code from your trusted device", saving = "Saving session in Keychain"
}

public protocol ActionSigning {
    func actionSignature(body: Data) async throws -> String
}
extension SAPSession: ActionSigning {}

public struct TwoFactorAuthentication {
    public static func normalize(_ input: String) throws -> String {
        if input.isEmpty { return "" }
        let code = input.filter { !$0.isWhitespace }
        guard code.utf8.count == 6, code.allSatisfy({ $0.isASCII && $0 >= "0" && $0 <= "9" }) else {
            throw AuthenticationError.invalidCode
        }
        return code
    }
}

public struct AppleAuthentication {
    private let transport: AuthenticationTransport
    private let signer: ActionSigning
    private let persistence: StoreAccountPersistence
    private let sleep: (TimeInterval) async throws -> Void
    private let diagnostic: (String) async -> Void
    private let recoveryAttempts: Int
    private let recoveryWindow: TimeInterval?
    private let now: () -> Date
    public init(transport: AuthenticationTransport, signer: ActionSigning,
                persistence: StoreAccountPersistence,
                diagnostic: @escaping (String) async -> Void = { _ in },
                automaticRecovery: Bool = false,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping (TimeInterval) async throws -> Void = {
                    try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
                }) {
        self.transport = transport; self.signer = signer; self.persistence = persistence; self.sleep = sleep; self.diagnostic = diagnostic; self.now = now
        recoveryAttempts = automaticRecovery ? 12 : 3
        recoveryWindow = automaticRecovery ? 120 : nil
    }

    public func login(email: String, password: String, code: String = "", identity: MachineIdentity,
                      endpoint: URL, resolvedEndpoint: (URL) async -> Void = { _ in }, progress: (AuthenticationStage) async -> Void = { _ in }) async throws -> AuthenticationOutcome {
        let code = try TwoFactorAuthentication.normalize(code)
        var endpoint = try AuthenticationEndpoint.validate(endpoint)
        let deadline = recoveryWindow.map { now().addingTimeInterval($0) }
        var logicalAttempt = 1
        var redirects = 0
        var body = try payload(email: email, password: password, code: code, guid: identity.guid, attempt: logicalAttempt)
        while true {
            try Task.checkCancellation()
            // Only publish endpoints after the same strict validation used for
            // credential replay. A warm 2FA/retry can skip an already resolved pod.
            await resolvedEndpoint(endpoint)
            let (data, response) = try await send(body: body, endpoint: endpoint, progress: progress, secrets: [password, code, email], deadline: deadline)
            if (300..<400).contains(response.statusCode) {
                await diagnostic("authentication-redirect=received; HTTP=\(response.statusCode); location-present=\(response.value(forHTTPHeaderField: "Location") != nil)")
                guard [301, 302, 307, 308].contains(response.statusCode),
                      let location = response.value(forHTTPHeaderField: "Location") else {
                    throw AuthenticationError.invalidRedirect
                }
                guard redirects < 4 else { throw AuthenticationError.tooManyRedirects }
                endpoint = try AuthenticationEndpoint.redirect(from: endpoint, location: location)
                redirects += 1
                await progress(.redirect)
                // Same attempt and exact signed payload; never convert to GET.
                continue
            }
            guard let result = try? ApplePlist.dictionary(data) else { throw AuthenticationError.invalidResponse(response.statusCode) }
            let failure = string(result["failureType"])
            let message = string(result["customerMessage"])
            if failure == "-5000", logicalAttempt == 1 {
                logicalAttempt = 2
                body = try payload(email: email, password: password, code: code, guid: identity.guid, attempt: logicalAttempt)
                continue
            }
            if failure.isEmpty, message == "MZFinance.BadLogin.Configurator_message" {
                if code.isEmpty { await progress(.twoFactor); return .twoFactorRequired(await transport.cookies()) }
                throw AuthenticationError.verificationRejected
            }
            if message == "Your account is disabled." { throw AuthenticationError.accountDisabled }
            if !failure.isEmpty {
                if failure == "-5000", message.isEmpty { throw AuthenticationError.invalidCredentials }
                throw AuthenticationError.apple(failure: safe(failure, secrets: [password, code, email]),
                    message: safe(message, secrets: [password, code, email, string(result["passwordToken"])]))
            }
            let dsid = string(result["dsPersonId"])
            let token = string(result["passwordToken"])
            let storefront = response.value(forHTTPHeaderField: "X-Set-Apple-Store-Front") ?? ""
            if !message.isEmpty, token.isEmpty || dsid.isEmpty {
                throw AuthenticationError.apple(failure: "", message: safe(message, secrets: [password, code, email]))
            }
            guard response.statusCode == 200, !dsid.isEmpty, !token.isEmpty, !storefront.isEmpty else {
                throw AuthenticationError.invalidResponse(response.statusCode)
            }
            let info = result["accountInfo"] as? [String: Any] ?? [:]
            let address = info["address"] as? [String: Any] ?? [:]
            let name = [string(address["firstName"]), string(address["lastName"])].filter { !$0.isEmpty }.joined(separator: " ")
            let account = StoreAccount(email: string(info["appleId"]).isEmpty ? email : string(info["appleId"]),
                name: name, dsid: dsid, passwordToken: token, storefront: storefront,
                pod: response.value(forHTTPHeaderField: "pod"), guid: identity.guid,
                authenticationURL: endpoint, cookies: await transport.cookies())
            try account.validate(identity: identity)
            try Task.checkCancellation()
            await progress(.saving)
            try Task.checkCancellation()
            try persistence.save(account)
            return .authenticated(account)
        }
    }

    private func payload(email: String, password: String, code: String, guid: String, attempt: Int) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["appleId": email, "attempt": String(attempt),
            "guid": guid, "password": password + code, "rmp": "0", "why": "signIn"], format: .xml, options: 0)
    }

    private func send(body: Data, endpoint: URL, progress: (AuthenticationStage) async -> Void, secrets: [String], deadline: Date?) async throws -> (Data, HTTPURLResponse) {
        for attempt in 1...recoveryAttempts {
            try Task.checkCancellation()
            if let deadline, now() >= deadline { throw AuthenticationError.retryLater }
            await diagnostic("authentication-recovery-attempt=\(attempt)/\(recoveryAttempts)")
            await progress(.signing)
            var request = URLRequest(url: endpoint)
            if let deadline { request.timeoutInterval = max(1, min(30, deadline.timeIntervalSince(now()))) }
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(SAPProtocol.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("close", forHTTPHeaderField: "Connection")
            let signature = try await signer.actionSignature(body: body)
            guard !signature.isEmpty else { throw SAPError.emptySignature }
            request.setValue(signature, forHTTPHeaderField: "X-Apple-ActionSignature")
            try Task.checkCancellation()
            // Native signing can be slow: recompute the remaining network
            // timeout afterwards, not before the blocking interpreter call.
            if let deadline {
                guard deadline > now() else { throw AuthenticationError.retryLater }
                request.timeoutInterval = max(1, min(30, deadline.timeIntervalSince(now())))
            }
            await progress(.authenticating)
            do {
                await diagnostic(await transport.cookieDiagnostic(for: endpoint))
                let (data, response) = try await transport.send(request)
                await diagnostic(ResponseDiagnostic.response(data, status: response.statusCode, scope: "authentication", attempt: attempt, secrets: secrets))
                guard data.count <= SAPProtocol.maximumBodySize else { throw SAPError.oversizedResponse }
                let result = try? ApplePlist.dictionary(data)
                let populated = result.map { !string($0["failureType"]).isEmpty || !string($0["customerMessage"]).isEmpty || !string($0["passwordToken"]).isEmpty } ?? false
                let status = response.statusCode
                if populated || (300..<400).contains(status) || status == 200 { return (data, response) }
                guard [204, 403, 404, 429].contains(status) || status / 100 == 5 else { throw AuthenticationError.invalidResponse(status) }
                guard attempt < recoveryAttempts else { throw status == 429 ? AuthenticationError.rateLimited : AuthenticationError.http(status) }
                let delay = try retryDelay(response.value(forHTTPHeaderField: "Retry-After"), attempt: attempt)
                if let deadline, now().addingTimeInterval(delay) >= deadline { throw status == 429 ? AuthenticationError.rateLimited : AuthenticationError.http(status) }
                await progress(.retrying)
                try await sleep(delay)
            } catch let error as URLError {
                if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
                guard [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code), attempt < recoveryAttempts else {
                    throw AuthenticationError.network(error.code.rawValue)
                }
                await progress(.retrying)
                let delay = recoveryWindow == nil ? Double(10 << (attempt - 1)) : min(15, Double(2 << min(attempt - 1, 3)))
                if let deadline, now().addingTimeInterval(delay) >= deadline { throw AuthenticationError.network(error.code.rawValue) }
                try await sleep(delay)
            }
        }
        throw AuthenticationError.invalidResponse(0)
    }

    private func retryDelay(_ header: String?, attempt: Int) throws -> TimeInterval {
        guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return recoveryWindow == nil ? Double(10 << (attempt - 1)) : min(15, Double(2 << min(attempt - 1, 3)))
        }
        if !header.isEmpty, header.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let seconds = UInt64(header), seconds <= 30 else { throw AuthenticationError.retryLater }
            return max(1, Double(seconds))
        }
        for format in ["EEE, dd MMM yyyy HH:mm:ss z", "EEEE, dd-MMM-yy HH:mm:ss z", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            if let date = formatter.date(from: header) {
                let value = max(0, date.timeIntervalSince(now()))
                guard value <= 30 else { throw AuthenticationError.retryLater }
                return max(1, value)
            }
        }
        return recoveryWindow == nil ? Double(10 << (attempt - 1)) : min(15, Double(2 << min(attempt - 1, 3)))
    }
    private func string(_ value: Any?) -> String { (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
    private func safe(_ text: String, secrets: [String]) -> String {
        var text = text
        for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: secret, with: "[redacted]")
        }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }.prefix(500)))
    }
}

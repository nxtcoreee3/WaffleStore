import Foundation
import Security
import SwiftUI
import PartyUI
import MapleSAP

// MainActor owns UI state; SAPSession runs the blocking native guest away from it.
extension AppData {
    func startAppleLogin() {
        guard !isAuthenticating, !appleId.isEmpty, !password.isEmpty else { return }
        let email = appleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        let verification = hasSent2FACode ? code : ""
        let challengeCookies = hasSent2FACode ? pendingAuthenticationCookies : []
        isAuthenticating = true
        authenticationError = ""
        authenticationRecovery = ""
        authenticationTask = Task {
            defer { isAuthenticating = false; authenticationTask = nil }
            var preparation: PreparedAppleLogin?
            var keepPrepared = false
            do {
                try Task.checkCancellation()
                // Reject invalid codes before creating a guest or contacting Apple.
                _ = try TwoFactorAuthentication.normalize(verification)
                let prepared: PreparedAppleLogin
                if let existing = preparedAppleLogin, existing.canReuse(for: email) {
                    prepared = existing
                } else {
                    if let existing = preparedAppleLogin { await existing.close() }
                    preparedAppleLogin = nil
                    prepared = try PreparedAppleLogin(email: email, cookies: challengeCookies)
                    preparedAppleLogin = prepared
                }
                preparation = prepared
                let signer = try await prepared.prepare { self.setAuthenticationStage($0) }
                try Task.checkCancellation()
                let authentication = AppleAuthentication(transport: prepared.loginTransport, signer: signer,
                    persistence: KeychainStoreAccount(), diagnostic: { event in
                        await MainActor.run {
                            if event.hasPrefix("authentication-recovery-attempt=") {
                                self.authenticationRecovery = "Automatic attempt " + event.replacingOccurrences(of: "authentication-recovery-attempt=", with: "")
                            }
                        }
                    }, automaticRecovery: true)
                guard let endpoint = prepared.endpoint else { throw CancellationError() }
                let outcome = try await authentication.login(email: email, password: secret, code: verification,
                    identity: prepared.identity, endpoint: endpoint, resolvedEndpoint: { endpoint in
                        await MainActor.run { prepared.endpoint = endpoint }
                    }) { stage in
                        await MainActor.run { self.setAuthenticationStage(stage) }
                    }
                try Task.checkCancellation()
                switch outcome {
                case .twoFactorRequired(let cookies):
                    pendingAuthenticationCookies = cookies
                    keepPrepared = true
                    hasSent2FACode = true
                    code = ""
                    applicationStatus = AuthenticationStage.twoFactor.rawValue
                case .authenticated(let account):
                    applyStoreAccount(account, restored: false)
                }
            } catch let error where error is CancellationError || Task.isCancelled {
                applicationStatus = "Sign-in cancelled."
            } catch {
                if let preparation {
                    if hasSent2FACode { pendingAuthenticationCookies = await preparation.loginTransport.cookies() }
                    if let error = error as? AuthenticationError {
                        switch error {
                        case .http, .network, .rateLimited, .retryLater, .invalidResponse, .verificationRejected, .invalidCode:
                            keepPrepared = true
                        default: break
                        }
                    }
                }
                // Apple/SAP errors have sanitized, bounded descriptions. Arbitrary
                // URL errors can include routing secrets: expose only numeric codes.
                if let error = error as? AuthenticationError { authenticationError = error.localizedDescription }
                else if let error = error as? SAPError { authenticationError = error.localizedDescription }
                else { authenticationError = "Sign-in failed (code \((error as NSError).code))." }
                code = ""
                applicationStatus = "Sign-in failed."
                print("Apple sign-in failed (code \((error as NSError).code)).")
            }
            if let preparation {
                if keepPrepared, !Task.isCancelled, preparation.canReuse(for: email), preparedAppleLogin === preparation {
                    expireLoginPreparation(preparation)
                } else {
                    if preparedAppleLogin === preparation { preparedAppleLogin = nil }
                    await preparation.close()
                }
            }
        }
    }

    func cancelAppleLogin() {
        authenticationTask?.cancel()
        clearLoginPreparation()
        hasSent2FACode = false
        code = ""
        password = ""
        pendingAuthenticationCookies = []
        authenticationError = ""
        applicationStatus = "Not logged in!".localized
    }

    func restoreStoreAccount() {
        guard !didRestoreStoreAccount else { return }
        didRestoreStoreAccount = true
        do {
            // Legacy sessions include a password and may use a key file. Discard
            // them without decrypting/importing and require one fresh SAP login.
            try LegacyCredentials.remove()
            guard let account = try KeychainStoreAccount().load() else { return }
            try account.validate(identity: KeychainMachineIdentity.loadOrCreate())
            applyStoreAccount(account, restored: true)
        } catch {
            authenticationError = "Saved session could not be restored (code \((error as NSError).code)). Sign in again."
            // Do not overwrite or delete an inaccessible Keychain item during device lock.
        }
    }

    func logoutStoreAccount() {
        guard !isAuthenticating, storeTask == nil, !showStoreVersions else { return }
        do {
            clearLoginPreparation()
            try KeychainKBSync().clear()
            try KeychainStoreAccount().clear()
            try LegacyCredentials.remove()
            ipaTool?.close()
            ipaTool = nil
            isAuthenticated = false
            hasSent2FACode = false
            appleId = ""; password = ""; code = ""
            pendingAuthenticationCookies = []
            authenticationError = ""
            hasAppBeenServed = false
            applicationStatus = "Not logged in!".localized
            applicationIcon = "xmark.circle.fill"
            // The machine-identity Keychain item deliberately survives logout.
        } catch {
            authenticationError = "Could not remove the saved session (code \((error as NSError).code))."
            Alertinator.shared.alert(title: "Log Out".localized, body: authenticationError)
        }
    }

    private func expireLoginPreparation(_ prepared: PreparedAppleLogin) {
        loginPreparationExpiry?.cancel()
        loginPreparationExpiry = Task {
            let remaining = max(0, prepared.expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, preparedAppleLogin === prepared, !isAuthenticating else { return }
            preparedAppleLogin = nil
            await prepared.close()
        }
    }
    private func clearLoginPreparation() {
        loginPreparationExpiry?.cancel(); loginPreparationExpiry = nil
        let prepared = preparedAppleLogin
        preparedAppleLogin = nil
        Task { await prepared?.close() }
    }

    private func setAuthenticationStage(_ stage: AuthenticationStage) {
        switch stage {
        case .bag, .sap, .signing, .prepared: applicationStatus = "Preparing sign-in…"
        case .authenticating, .redirect: applicationStatus = "Connecting to Apple…"
        case .retrying: applicationStatus = "Apple is taking longer. Retrying…"
        case .saving: applicationStatus = "Completing sign-in…"
        case .twoFactor: applicationStatus = "Enter your verification code."
        }
        print("Apple authentication stage: \(stage.rawValue)")
    }
    private func applyStoreAccount(_ account: StoreAccount, restored: Bool) {
        appleId = account.email
        password = ""; code = ""; hasSent2FACode = false
        pendingAuthenticationCookies = []
        ipaTool = IPATool(account: account)
        isAuthenticated = true
        applicationStatus = "Signed in. Choose an app to get started."
        applicationIcon = "checkmark.circle.fill"
        applicationIconColor = .primary
        print("Apple authentication: \(restored ? "saved session loaded" : "DSID/token/storefront received and saved in Keychain") [values withheld]")
    }

}

// A short-lived, same-account preparation avoids repeating the Bag/certificate/
// SAP handshake for a manual retry or 2FA. It holds no password/code, writes
// nothing to disk, signs every request freshly and expires after five minutes.
@MainActor
final class PreparedAppleLogin {
    let email: String
    let identity: MachineIdentity
    let loginTransport: AppleAuthenticationTransport
    private let sapTransport = AppleSAPTransport()
    private var signer: SAPSession?
    private var closed = false
    var endpoint: URL?
    private(set) var expiresAt = Date.distantPast
    init(email: String, cookies: [StoreCookie]) throws {
        self.email = email
        identity = try KeychainMachineIdentity.loadOrCreate()
        loginTransport = AppleAuthenticationTransport(cookies: cookies, isolatedConnections: true)
    }
    func canReuse(for email: String) -> Bool {
        !closed && self.email == email && signer != nil && expiresAt > Date()
    }
    func prepare(progress: (AuthenticationStage) -> Void) async throws -> SAPSession {
        guard !closed else { throw CancellationError() }
        if let signer { progress(.prepared); return signer }
        progress(.bag)
        let configuration = try await SAPProtocol(transport: sapTransport).bag(identity: identity)
        endpoint = try AuthenticationEndpoint.validate(configuration.authenticationURL)
        progress(.sap)
        let created = try SAPSession(guest: NativeSAPGuest(), transport: sapTransport)
        // Own the guest immediately, including cancellation during initialization.
        signer = created
        try await created.initialize(configuration: configuration, identity: identity)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        expiresAt = Date().addingTimeInterval(300)
        return created
    }
    func close() async {
        guard !closed else { return }
        closed = true
        sapTransport.close(); loginTransport.close()
        if let signer { await signer.close() }
        signer = nil; endpoint = nil
    }
}

private enum LegacyCredentials {
    static func remove() throws {
        let fm = FileManager.default
        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let library = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        for file in [documents.appendingPathComponent("authinfo"), library.appendingPathComponent(".authkey")] {
            if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        }
        let status = SecItemDelete([kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.nxtcoreee3.WaffleStore.key"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SAPError.keychain(status) }
    }
}

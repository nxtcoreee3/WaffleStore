import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Intentionally excludes the password, 2FA code and SAP setup buffers.
public struct StoreAccount: Codable, Equatable {
    public let email: String
    public let name: String
    public let dsid: String
    public let passwordToken: String
    public let storefront: String
    public let pod: String?
    public let guid: String
    public let authenticationURL: URL
    public let cookies: [StoreCookie]

    public init(email: String, name: String, dsid: String, passwordToken: String,
                storefront: String, pod: String?, guid: String, authenticationURL: URL,
                cookies: [StoreCookie] = []) {
        self.email = email; self.name = name; self.dsid = dsid
        self.passwordToken = passwordToken; self.storefront = storefront
        self.pod = pod; self.guid = guid; self.authenticationURL = authenticationURL
        self.cookies = cookies
    }

    public func validate(identity: MachineIdentity) throws {
        guard guid == identity.guid, !dsid.isEmpty, dsid.allSatisfy({ $0.isASCII && $0.isNumber }),
              !passwordToken.isEmpty, !storefront.isEmpty else { throw AuthenticationError.invalidSession }
        _ = try AuthenticationEndpoint.validate(authenticationURL)
        if let pod = pod, !pod.isEmpty, !pod.allSatisfy({ $0.isASCII && $0.isNumber }) {
            throw AuthenticationError.invalidSession
        }
    }
}

public struct StoreCookie: Codable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expires: Date?
    public let secure: Bool
    public let httpOnly: Bool

    public init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        expires = cookie.expiresDate; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
    }

    public func cookie(now: Date = Date()) -> HTTPCookie? {
        let host = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard (host == "apple.com" || host == "itunes.apple.com" || host.hasSuffix(".itunes.apple.com")),
              expires == nil || expires! > now else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires = expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}

public protocol StoreAccountPersistence {
    func load() throws -> StoreAccount?
    func save(_ account: StoreAccount) throws
    func clear() throws
}

public enum AuthenticationEndpoint {
    // Same authentication host/path policy as ipatool 3411d57. Bag-only SAP
    // probes may discover other endpoints; credentials never use a fallback.
    public static func validate(_ url: URL) throws -> URL {
        do { _ = try SAPConfiguration.trustedAppleURL(url.absoluteString) }
        catch { throw AuthenticationError.invalidRedirect }
        let host = url.host?.lowercased() ?? ""
        let path = "/WebObjects/MZFinance.woa/wa/authenticate"
        guard (host == "buy.itunes.apple.com" || host.hasSuffix("-buy.itunes.apple.com")),
              [path, path + "/"].contains(url.path),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == url.path
        else { throw AuthenticationError.invalidRedirect }
        return url
    }

    public static func redirect(from base: URL, location: String) throws -> URL {
        let text = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text, relativeTo: base)?.absoluteURL else {
            throw AuthenticationError.invalidRedirect
        }
        return try validate(url)
    }
}

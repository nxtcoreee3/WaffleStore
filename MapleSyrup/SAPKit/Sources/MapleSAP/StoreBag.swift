import Foundation

public enum SAPError: Error, LocalizedError, Equatable {
    case invalidBag, unsupportedVersion, invalidEndpoint, invalidIdentity
    case http(Int), oversizedResponse, invalidCertificate, invalidExchange
    case runtimeUnavailable, executableRuntimeRejected, invalidState, emptySignature
    case keychain(Int32)
    case nativeRuntime(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidBag: return "Store Bag does not contain a valid SAP configuration."
        case .unsupportedVersion: return "Store Bag requires an unsupported SAP version."
        case .invalidEndpoint: return "Apple endpoint rejected: HTTPS and a trusted Apple host are required."
        case .invalidIdentity: return "Machine identity is invalid."
        case .http(let status): return "Apple returned HTTP \(status)."
        case .oversizedResponse: return "Apple SAP response exceeds the 1 MiB limit."
        case .invalidCertificate: return "Apple returned no SAP certificate."
        case .invalidExchange: return "Apple returned an invalid SAP setup exchange."
        case .runtimeUnavailable: return "SAP guest interpreter is not implemented. No ActionSignature was generated. See IMPLEMENTATION.md."
        case .executableRuntimeRejected: return "A runtime that generates executable memory is incompatible with this jailed SAP module."
        case .invalidState: return "SAP operation called in an invalid session state."
        case .emptySignature: return "SAP runtime returned an empty signature."
        case .keychain(let status): return "Keychain operation failed (OSStatus \(status))."
        case .nativeRuntime(let stage): return "SAP native runtime failed at stage \(stage) (1 arguments; 2 assets; 3 emulator; 4 initialization; 5 exchange; 6 signing; 7 handle)."
        }
    }
}

public struct MachineIdentity: Equatable {
    public let hardwareID: Data
    public var guid: String { hardwareID.map { String(format: "%02X", $0) }.joined() }
    public init(hardwareID: Data) throws {
        guard hardwareID.count == 6 else { throw SAPError.invalidIdentity }
        self.hardwareID = hardwareID
    }
}

public struct SAPConfiguration: Equatable {
    public let authenticationURL: URL
    public let setupURL: URL
    public let certificateURL: URL
    public let version: UInt32

    public static func parse(bag data: Data) throws -> SAPConfiguration {
        guard let root = try ApplePlist.dictionary(data),
              let bag = root["urlBag"] as? [String: Any],
              let authentication = bag["authenticateAccount"] as? String,
              let setup = bag["sign-sap-setup"] as? String,
              let certificate = bag["sign-sap-setup-cert"] as? String,
              let rawVersion = bag["sign-sap-version"] else { throw SAPError.invalidBag }
        let versionString = (rawVersion as? String) ?? (rawVersion as? NSNumber)?.stringValue
        guard let string = versionString, let version = UInt32(string) else { throw SAPError.invalidBag }
        guard version == 200 else { throw SAPError.unsupportedVersion }
        let authURL = try trustedAppleURL(authentication)
        let host = authURL.host!.lowercased()
        let modern = (host == "auth.itunes.apple.com" || host.hasSuffix("-buy.itunes.apple.com")) &&
            ["/auth/v1/native", "/auth/v1/native/"].contains(authURL.path)
        // Some live Bags still advertise the legacy endpoint. Permit discovery
        // for SAP-only diagnostics; no credentials are sent by this module.
        let legacy = host == "buy.itunes.apple.com" && authURL.path == "/WebObjects/MZFinance.woa/wa/authenticate"
        guard modern || legacy else { throw SAPError.invalidEndpoint }
        return SAPConfiguration(authenticationURL: authURL, setupURL: try trustedAppleURL(setup),
                                certificateURL: try trustedAppleURL(certificate), version: version)
    }

    public static func trustedAppleURL(_ string: String) throws -> URL {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased(),
              (host == "apple.com" || host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com")),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { throw SAPError.invalidEndpoint }
        return url
    }
}

enum ApplePlist {
    static func dictionary(_ data: Data) throws -> [String: Any]? {
        if let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return parsed
        }
        // Apple's Document/Protocol envelope can contain a nested plist.
        // Equivalent to ipatool HTTP normalization; no regex/body logging.
        guard let text = String(data: data, encoding: .utf8) else { throw SAPError.invalidBag }
        if let start = text.range(of: "<plist"), let end = text.range(of: "</plist>", options: .backwards),
           start.lowerBound < end.upperBound {
            let plist = Data(text[start.lowerBound..<end.upperBound].utf8)
            return try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        }
        if let start = text.range(of: "<dict>"), let end = text.range(of: "</dict>", options: .backwards),
           start.lowerBound < end.upperBound {
            let plist = Data(("<plist version=\"1.0\">" + text[start.lowerBound..<end.upperBound] + "</plist>").utf8)
            return try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        }
        // Some native replies contain bare key/value pairs in Document/Protocol.
        // Normalize only these envelopes (or bare pairs), never arbitrary HTML.
        var inner = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for tag in ["Document", "Protocol"] {
            if let start = inner.range(of: "<" + tag + ">"),
               let end = inner.range(of: "</" + tag + ">", options: .backwards),
               start.upperBound < end.lowerBound {
                inner = String(inner[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if inner.hasPrefix("<key>") {
            let plist = Data(("<plist version=\"1.0\"><dict>" + inner + "</dict></plist>").utf8)
            return try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        }
        throw SAPError.invalidBag
    }
}

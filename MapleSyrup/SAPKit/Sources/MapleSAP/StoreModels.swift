import Foundation
import CoreFoundation

public enum StoreError: Error, LocalizedError, Equatable {
    case unsupportedStorefront, invalidApp, unavailable, invalidResponse, versionMismatch
    case retryLater
    case emptyRedownload
    case sessionExpired, licenseRequired, paidPurchase, http(Int), native(Int32), packageInvalid
    case apple(String, String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedStorefront: return "This account's storefront is not recognized."
        case .invalidApp: return "Enter an App Store link, numeric App Store ID or bundle ID."
        case .retryLater: return "Apple requested a longer retry delay. Wait and try again later."
        case .emptyRedownload: return "Apple redownload endpoint returned an empty HTTP 500."
        case .unavailable: return "Apple could not find or serve this app/version in the selected catalog or for this account."
        case .invalidResponse: return "Apple returned an incomplete Store response."
        case .versionMismatch: return "Apple returned a different app or externalVersionId. Download refused."
        case .sessionExpired: return "Apple Store requires sign-in for this request. The saved account was retained. Please try again later if a fresh login gives the same error."
        case .licenseRequired: return "This account needs a license. Acquire the app in the App Store, then retry."
        case .paidPurchase: return "Only verified free apps can be acquired automatically. Use the App Store for paid apps or subscriptions."
        case .http(let code): return "Store request failed (HTTP \(code))."
        case .native(let stage):
            let reason: [Int32: String] = [2: "Apple asset loading", 8: "interpreted StoreAgent kbsync", 20: "package parameters", 21: "ZIP preparation", 22: "CDN range inspection", 31: "invalid ZIP or size/path limit", 32: "MD5 mismatch", 33: "IPA bundle/platform mismatch", 34: "metadata app/version mismatch", 35: "SINF data/path mismatch", 36: "ZIP checksum failure", 37: "sandbox storage access or space"]
            return "Native Store operation failed (stage \(stage): \(reason[stage] ?? "unknown"))."
        case .packageInvalid: return "IPA validation failed. No completed IPA was saved."
        case .apple(let code, let message): return "Apple Store \(code): \(message)"
        }
    }
}
public struct StoreApp: Sendable, Equatable {
    public let id: String
    public let bundleID: String
    public let name: String
    public let price: Double?
    public let catalogCountry: String?
    public init(id: String, bundleID: String, name: String, price: Double?, catalogCountry: String? = nil) {
        self.id = id; self.bundleID = bundleID; self.name = name; self.price = price; self.catalogCountry = catalogCountry
    }
}
public struct StoreDownload: Sendable {
    public let url: URL
    public let externalVersionID: String
    public let availableVersionIDs: [String]
    public let metadata: Data
    public let sinfs: [Data]
    public let md5: String
}
public protocol KBSyncGenerator {
    func generate(identity: MachineIdentity, dsid: UInt64) throws -> Data
}
public protocol KBSyncPersistence {
    func load(dsid: String, guid: String) throws -> Data?
    func save(_ data: Data, dsid: String, guid: String) throws
    func clear() throws
}
public struct NoKBSyncPersistence: KBSyncPersistence {
    public init() {}
    public func load(dsid: String, guid: String) throws -> Data? { nil }
    public func save(_ data: Data, dsid: String, guid: String) throws {}
    public func clear() throws {}
}
public enum StoreParsing {
    public static func identifier(_ value: Any?) -> String? {
        let text: String?
        if let value = value as? String { text = value }
        else if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            text = value.stringValue
        } else { text = nil }
        guard let text = text, !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), UInt64(text) != nil else { return nil }
        return text
    }
    public static func download(_ root: [String: Any], app: StoreApp, version: String, email: String) throws -> StoreDownload {
        try failure(root)
        guard let items = root["songList"] as? [[String: Any]], items.count == 1,
              let item = items.first, var metadata = item["metadata"] as? [String: Any] else { throw StoreError.unavailable }
        guard identifier(metadata["itemId"]) == app.id,
              identifier(metadata["softwareVersionExternalIdentifier"]) == version,
              metadata["softwareVersionBundleId"] as? String == app.bundleID else { throw StoreError.versionMismatch }
        guard let text = item["URL"] as? String else { throw StoreError.invalidResponse }
        let url = try CDNPolicy.validate(text)
        let versions = (metadata["softwareVersionExternalIdentifiers"] as? [Any] ?? []).compactMap(identifier)
        metadata["apple-id"] = email; metadata["userName"] = email
        let sinfItems = item["sinfs"] as? [[String: Any]] ?? []
        var sinfs: [Data] = []
        for entry in sinfItems {
            guard let data = entry["sinf"] as? Data, !data.isEmpty, data.count <= 1 << 20 else { throw StoreError.invalidResponse }
            sinfs.append(data)
        }
        return StoreDownload(url: url, externalVersionID: version,
            availableVersionIDs: Array(Set(versions + [version])).sorted { (UInt64($0) ?? 0) > (UInt64($1) ?? 0) },
            metadata: try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0),
            sinfs: sinfs, md5: item["md5"] as? String ?? "")
    }
    static func failure(_ root: [String: Any]) throws {
        let code = (root["failureType"] as? String) ?? (root["failureType"] as? NSNumber)?.stringValue ?? ""
        let message = root["customerMessage"] as? String ?? ""
        if ["2034", "2042", "1008"].contains(code) || message.lowercased().contains("password has changed") { throw StoreError.sessionExpired }
        if code == "9610" { throw StoreError.licenseRequired }
        if code == "5002" { return } // already owned; purchase handles separately
        if !code.isEmpty || !message.isEmpty {
            if message.lowercased().hasSuffix("no longer available") { throw StoreError.unavailable }
            throw StoreError.apple(String(code.prefix(32)), String(message.filter { !$0.isNewline }.prefix(400)))
        }
    }
}
public enum CDNPolicy {
    public static func validate(_ text: String) throws -> URL {
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com") || host.hasSuffix(".cdn-apple.com")
        else { throw SAPError.invalidEndpoint }
        return url
    }
}

public enum StoreStage: String, Sendable {
    case bag = "Resolving Store Bag"
    case latest = "Resolving latest iOS externalVersionId"
    case kbsync = "Generating account-bound kbsync"
    case ent = "Requesting ent/download"
    case legacy = "Trying Store pod fallback"
    case redownload = "Trying Bag redownload"
    case update = "Trying pinned Bag update"
    case purchase = "Acquiring free app license"
    case validated = "Store app and externalVersionId validated"
}

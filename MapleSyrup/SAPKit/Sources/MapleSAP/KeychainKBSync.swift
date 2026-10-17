#if canImport(Security)
import Foundation
import Security

// Separate from the session: only server-accepted blobs are persisted.
public final class KeychainKBSync: KBSyncPersistence {
    private let service: String
    public init(service: String = "com.nxtcoreee3.WaffleStore.sap") { self.service = service }
    private struct Entry: Codable { let dsid: String; let guid: String; let blob: Data }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "kbsync-v1"]
    }
    public func load(dsid: String, guid: String) throws -> Data? {
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SAPError.keychain(status) }
        guard let data = result as? Data, let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.dsid == dsid, entry.guid == guid, !entry.blob.isEmpty else { return nil }
        return entry.blob
    }
    public func save(_ data: Data, dsid: String, guid: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(Entry(dsid: dsid, guid: guid, blob: data)),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SAPError.keychain(updated) }
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else { throw SAPError.keychain(status) }
    }
    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SAPError.keychain(status) }
    }
}
#endif

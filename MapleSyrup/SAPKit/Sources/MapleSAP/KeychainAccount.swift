#if canImport(Security)
import Foundation
import Security

public final class KeychainStoreAccount: StoreAccountPersistence {
    private let service: String
    private let account = "store-account-v2"
    public init(service: String = "com.nxtcoreee3.WaffleStore.sap") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func load() throws -> StoreAccount? {
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SAPError.keychain(status) }
        guard let data = result as? Data, let decoded = try? JSONDecoder().decode(StoreAccount.self, from: data)
        else { throw AuthenticationError.invalidSession }
        return decoded
    }
    public func save(_ account: StoreAccount) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(account),
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

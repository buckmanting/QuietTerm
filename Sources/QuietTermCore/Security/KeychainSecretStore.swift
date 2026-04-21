import Foundation

#if canImport(Security)
import Security

public final class KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "app.quietterm.secrets") {
        self.service = service
    }

    public func save(_ data: Data, id: String) throws {
        let query = baseQuery(id: id)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.storageFailed("Keychain save failed with status \(status).")
        }
    }

    public func read(id: String) throws -> Data {
        var query = baseQuery(id: id)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw SecretStoreError.notFound
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretStoreError.storageFailed("Keychain read failed with status \(status).")
        }

        return data
    }

    public func delete(id: String) throws {
        let status = SecItemDelete(baseQuery(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.storageFailed("Keychain delete failed with status \(status).")
        }
    }

    private func baseQuery(id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
#endif

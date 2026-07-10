import Foundation
import Security

/// Thin, synchronous Keychain wrapper for storing short string values (tokens, IDs).
/// All items are stored under a shared service identifier and are accessible after the
/// first device unlock — appropriate for tokens used during background refresh.
enum KeychainStore {

    private static let service = "com.melakunet.snapshop.auth"

    // MARK: — Public API

    /// Persists `value` under `key`, replacing any existing entry.
    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Delete first so SecItemAdd always starts clean.
        delete(key: key)
        let attributes: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            // Accessible after first unlock; not synced to other devices via iCloud Keychain.
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Returns the stored string for `key`, or nil if not found or unreadable.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Removes the item stored under `key`. No-op if not found.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

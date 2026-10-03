import Foundation
import Security

/// API keys live only in the Keychain, one generic-password item per provider.
nonisolated enum KeychainStore {
    struct Failure: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            switch status {
            case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
                // Ad-hoc signed builds are a "new app" to the Keychain after every update.
                String(localized: "macOS didn’t allow calto to read the key. After an update macOS asks once: try again and choose “Always Allow”.")
            default:
                (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
            }
        }
    }

    private static let service = Bundle.main.bundleIdentifier ?? "io.github.nickcool0.calto"

    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    /// Checks for an item without decrypting it, so it never triggers a Keychain password prompt.
    static func contains(account: String) -> Bool {
        var lookup = query(account)
        lookup[kSecReturnAttributes] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        return SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) throws -> String? {
        var lookup = query(account)
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Failure(status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData] = data
            item[kSecAttrLabel] = "calto: \(account) API key"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    // MARK: All keys in one item

    /// Every provider's key lives in this one item, so macOS asks for the Keychain password at most once
    /// (each item has its own access list, and an ad-hoc signed update is a new app to all of them).
    static let allKeysAccount = "api-keys"

    /// Reads all keys. Keys from calto 0.6 and earlier (one item per provider) are moved into the shared
    /// item on first use; macOS may ask once for each of those old items.
    static func loadAllKeys(legacyAccounts: [String]) throws -> [String: String] {
        if let json = try read(account: allKeysAccount) {
            return (try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))) ?? [:]
        }
        var keys: [String: String] = [:]
        for account in legacyAccounts {
            if let key = try read(account: account), !key.isEmpty {
                keys[account] = key
            }
        }
        if !keys.isEmpty {
            try saveAllKeys(keys)
            for account in keys.keys {
                try? delete(account: account)
            }
        }
        return keys
    }

    static func saveAllKeys(_ keys: [String: String]) throws {
        if keys.isEmpty {
            try delete(account: allKeysAccount)
            return
        }
        let data = try JSONEncoder().encode(keys)
        try save(String(decoding: data, as: UTF8.self), account: allKeysAccount)
    }
}

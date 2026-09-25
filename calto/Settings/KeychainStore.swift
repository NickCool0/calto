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
}

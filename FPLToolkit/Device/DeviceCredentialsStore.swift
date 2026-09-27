import Foundation
import Security

/// The server-issued device ID and secret. The secret is the only proof this install owns its
/// watch list, so it lives in the Keychain (this device only, readable after first unlock).
struct DeviceCredentials: Codable, Sendable, Equatable {
    let deviceId: String
    let secret: String

    var authorizationHeader: String { "Device \(deviceId).\(secret)" }
}

struct DeviceCredentialsStore: Sendable {
    var service = "uk.co.fpltoolkit.device"
    var account = "credentials"

    func load() -> DeviceCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(DeviceCredentials.self, from: data)
    }

    @discardableResult
    func save(_ credentials: DeviceCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

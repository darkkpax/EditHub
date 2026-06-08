import Foundation
import Security

enum KeychainCredentialStoreError: LocalizedError {
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            return "KEYCHAIN OPERATION FAILED (\(status))."
        }
    }
}

enum KeychainCredentialStore {
    private static let service = "GoogleDropboxDownloader.credentials.v1"

    static func readData(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainCredentialStoreError.operationFailed(status)
        }
    }

    static func writeData(_ data: Data, account: String) throws {
        try delete(account: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.operationFailed(status)
        }
    }

    static func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.operationFailed(status)
        }
    }

    static func readString(account: String) throws -> String? {
        guard let data = try readData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeString(_ value: String, account: String) throws {
        try writeData(Data(value.utf8), account: account)
    }
}

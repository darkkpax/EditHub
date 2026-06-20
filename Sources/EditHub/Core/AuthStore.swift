import Foundation

/// Хранит JWT-токен в keychain и держит состояние аутентификации.
/// Единый источник истины — `AuthStore.shared`.
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    private(set) var token: String?
    private(set) var userId: String?
    private(set) var workspaceId: String?
    private(set) var userEmail: String?

    var isLoggedIn: Bool { token != nil }

    private static let keychainAccount = "edithub.jwt"

    private init() {
        // Восстанавливаем токен из keychain при старте.
        if let saved = try? KeychainCredentialStore.readString(account: Self.keychainAccount),
           let payload = jwtPayload(saved) {
            // Проверяем срок — exp в Unix-секундах.
            if let exp = payload["exp"] as? TimeInterval, Date().timeIntervalSince1970 < exp {
                token       = saved
                userId      = payload["userId"] as? String
                workspaceId = payload["workspaceId"] as? String
            } else {
                // Токен протух — удаляем.
                try? KeychainCredentialStore.delete(account: Self.keychainAccount)
            }
        }
    }

    func apply(response: AuthResponse) {
        token       = response.token
        userId      = response.userId
        workspaceId = response.workspaceId
        try? KeychainCredentialStore.writeString(response.token, account: Self.keychainAccount)
    }

    func logout() {
        token       = nil
        userId      = nil
        workspaceId = nil
        userEmail   = nil
        try? KeychainCredentialStore.delete(account: Self.keychainAccount)
    }

    // MARK: - JWT payload decode (без проверки подписи — доверяем серверу)

    private func jwtPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = base64.count % 4
        if rem > 0 { base64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// AuthResponse lives in Sources/EditHub/Models/ServerModels.swift

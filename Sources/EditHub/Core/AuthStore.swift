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

    /// Called after the user grants sandbox access to their iCloud Drive folder.
    func importSharedSession(from selectedICloudURL: URL) {
        guard token == nil else { return }
        let selectedName = selectedICloudURL.lastPathComponent.lowercased()
        let candidates: [URL]
        if selectedName == "edithub" || selectedName == "edit hub" {
            candidates = [selectedICloudURL.appendingPathComponent("auth.json")]
        } else {
            candidates = [
                selectedICloudURL.appendingPathComponent("EditHub/auth.json"),
                selectedICloudURL.appendingPathComponent("edithub/auth.json"),
                selectedICloudURL.appendingPathComponent("Edit Hub/auth.json")
            ]
        }
        guard let shared = Self.loadSharedSession(from: candidates),
              let payload = jwtPayload(shared.token),
              let exp = payload["exp"] as? TimeInterval,
              Date().timeIntervalSince1970 < exp else { return }
        token = shared.token
        userId = shared.userId ?? payload["userId"] as? String
        workspaceId = shared.workspaceId ?? payload["workspaceId"] as? String
        userEmail = shared.email
        try? KeychainCredentialStore.writeString(shared.token, account: Self.keychainAccount)
        if let serverURL = shared.serverURL, !serverURL.isEmpty {
            UserDefaults.standard.set(serverURL, forKey: "edithub.serverURL")
        }
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

    private static func loadSharedSession(from candidates: [URL]) -> SharedAuthSession? {
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(SharedAuthSession.self, from: data),
                  !session.token.isEmpty else { continue }
            return session
        }
        return nil
    }
}

private struct SharedAuthSession: Decodable {
    let token: String
    let userId: String?
    let workspaceId: String?
    let email: String?
    let serverURL: String?

    private enum CodingKeys: String, CodingKey {
        case token, userId, workspaceId, email, userEmail, serverURL, serverUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        email = try container.decodeIfPresent(String.self, forKey: .userEmail)
            ?? container.decodeIfPresent(String.self, forKey: .email)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL)
            ?? container.decodeIfPresent(String.self, forKey: .serverUrl)
    }
}

// AuthResponse lives in Sources/EditHub/Models/ServerModels.swift

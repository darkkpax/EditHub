import AppKit
import CryptoKit
import Foundation
import Network

enum GoogleDriveOAuthConfiguration {
    static let clientID = "875188896849-71kig4s8vrn00c3aivj9hum9h1at8n0q.apps.googleusercontent.com"
    static let scope = "https://www.googleapis.com/auth/drive.readonly"
    static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
}

@MainActor
final class GoogleDriveAuthController: NSObject, ObservableObject {
    static let shared = GoogleDriveAuthController()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var accountHint = "GOOGLE DRIVE: NOT SIGNED IN"

    private let sessionStore = GoogleDriveOAuthSessionStore()
    private let diagnostics = DownloadDiagnosticsStore()

    override init() {
        super.init()
        Task { @MainActor in
            await refreshPublishedState()
        }
    }

    func signIn() {
        Task { @MainActor in
            do {
                let clientSecret = GoogleDriveOAuthClientSecretStorage.current()
                guard !clientSecret.isEmpty else {
                    throw DownloaderError.processFailed("SET GOOGLE OAUTH CLIENT SECRET FROM TOP MENU: GOOGLE DRIVE -> SET CLIENT SECRET...")
                }
                let verifier = Self.makeCodeVerifier()
                let challenge = Self.makeCodeChallenge(from: verifier)
                let state = UUID().uuidString
                let callback = try await GoogleOAuthLoopbackServer.start()
                let redirectURI = "http://127.0.0.1:\(callback.port)/oauth2callback"

                var components = URLComponents(url: GoogleDriveOAuthConfiguration.authURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: GoogleDriveOAuthConfiguration.clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: GoogleDriveOAuthConfiguration.scope),
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "state", value: state)
                ]

                guard let authURL = components.url else {
                    throw DownloaderError.processFailed("FAILED TO BUILD GOOGLE AUTHORIZATION URL.")
                }
                guard NSWorkspace.shared.open(authURL) else {
                    throw DownloaderError.processFailed("FAILED TO OPEN GOOGLE SIGN-IN PAGE.")
                }

                let callbackURL = try await callback.waitForRedirect(timeout: 180)
                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

                if let returnedState = items.first(where: { $0.name == "state" })?.value, returnedState != state {
                    throw DownloaderError.processFailed("GOOGLE SIGN-IN STATE MISMATCH.")
                }

                if let error = items.first(where: { $0.name == "error" })?.value {
                    throw DownloaderError.processFailed("GOOGLE SIGN-IN FAILED: \(error.uppercased())")
                }

                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    throw DownloaderError.processFailed("GOOGLE SIGN-IN DID NOT RETURN AN AUTHORIZATION CODE.")
                }

                let token = try await exchangeCodeForToken(
                    code: code,
                    codeVerifier: verifier,
                    redirectURI: redirectURI,
                    clientSecret: clientSecret
                )
                try sessionStore.save(token)
                diagnostics.log("GOOGLE OAUTH SIGN-IN SUCCEEDED")
                await refreshPublishedState()
            } catch {
                diagnostics.log("GOOGLE OAUTH SIGN-IN FAILED: \(error.localizedDescription)")
                DownloadErrorPresenter.present(error: error)
            }
        }
    }

    func signOut() {
        try? sessionStore.clear()
        diagnostics.log("GOOGLE OAUTH SIGN-OUT")
        Task { @MainActor in
            await refreshPublishedState()
        }
    }

    func currentAccessToken() async throws -> String? {
        guard var token = try sessionStore.load() else { return nil }
        if token.isUsable {
            return token.accessToken
        }
        guard let storedRefreshToken = token.refreshToken, !storedRefreshToken.isEmpty else {
            try sessionStore.clear()
            await refreshPublishedState()
            return nil
        }

        let clientSecret = GoogleDriveOAuthClientSecretStorage.current()
        guard !clientSecret.isEmpty else {
            try sessionStore.clear()
            await refreshPublishedState()
            throw DownloaderError.processFailed("SET GOOGLE OAUTH CLIENT SECRET FROM TOP MENU: GOOGLE DRIVE -> SET CLIENT SECRET...")
        }

        do {
            token = try await refreshAccessToken(using: storedRefreshToken, clientSecret: clientSecret)
        } catch {
            if Self.isRevokedOrExpiredGrant(error) {
                try? sessionStore.clear()
                await refreshPublishedState()
                throw DownloaderError.processFailed("GOOGLE SESSION EXPIRED OR REVOKED. SIGN IN AGAIN FROM MENU: GOOGLE DRIVE -> SIGN IN.")
            }
            throw error
        }
        try sessionStore.save(token)
        await refreshPublishedState()
        return token.accessToken
    }

    private static func isRevokedOrExpiredGrant(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("invalid_grant")
            || text.contains("expired or revoked")
            || text.contains("token has been expired")
            || text.contains("token has been revoked")
    }

    private func refreshPublishedState() async {
        let token = try? sessionStore.load()
        isAuthenticated = token != nil
        accountHint = token == nil ? "GOOGLE DRIVE: NOT SIGNED IN" : "GOOGLE DRIVE: SIGNED IN"
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String, redirectURI: String, clientSecret: String) async throws -> GoogleDriveOAuthToken {
        var request = URLRequest(url: GoogleDriveOAuthConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedData([
            "client_id": GoogleDriveOAuthConfiguration.clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        return try decodeTokenResponse(data: data, response: response)
    }

    private func refreshAccessToken(using refreshToken: String, clientSecret: String) async throws -> GoogleDriveOAuthToken {
        var request = URLRequest(url: GoogleDriveOAuthConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedData([
            "client_id": GoogleDriveOAuthConfiguration.clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        var token = try decodeTokenResponse(data: data, response: response)
        token.refreshToken = token.refreshToken ?? refreshToken
        return token
    }

    private func decodeTokenResponse(data: Data, response: URLResponse) throws -> GoogleDriveOAuthToken {
        guard let http = response as? HTTPURLResponse else {
            throw DownloaderError.badServerResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(GoogleOAuthErrorPayload.self, from: data) {
                throw DownloaderError.processFailed("GOOGLE TOKEN ERROR \(http.statusCode): \(payload.errorDescription.uppercased())")
            }
            throw DownloaderError.processFailed("GOOGLE TOKEN ERROR \(http.statusCode).")
        }

        let payload = try JSONDecoder().decode(GoogleOAuthTokenPayload.self, from: data)
        return GoogleDriveOAuthToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private func formEncodedData(_ parameters: [String: String]) -> Data? {
        let body = parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func makeCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private struct GoogleOAuthTokenPayload: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct GoogleOAuthErrorPayload: Decodable {
    let error: String
    let errorDescription: String

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct GoogleDriveOAuthToken: Codable {
    let accessToken: String
    var refreshToken: String?
    let expirationDate: Date

    var isUsable: Bool {
        expirationDate.timeIntervalSinceNow > 60
    }
}

final class GoogleDriveOAuthSessionStore {
    private let defaultsKey = "google_drive_oauth_token"
    private let keychainAccount = "google_drive_oauth_token"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> GoogleDriveOAuthToken? {
        if let keychainData = try KeychainCredentialStore.readData(account: keychainAccount) {
            return try decoder.decode(GoogleDriveOAuthToken.self, from: keychainData)
        }

        guard let defaultsData = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        let token = try decoder.decode(GoogleDriveOAuthToken.self, from: defaultsData)
        try? KeychainCredentialStore.writeData(defaultsData, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return token
    }

    func save(_ token: GoogleDriveOAuthToken) throws {
        let data = try encoder.encode(token)
        try KeychainCredentialStore.writeData(data, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func clear() throws {
        try KeychainCredentialStore.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

enum GoogleDriveOAuthClientSecretStorage {
    static let storageKey = "google_drive_oauth_client_secret"
    static let keychainAccount = "google_drive_oauth_client_secret"

    /// Baked-in default so the app works on a fresh machine without manual setup.
    /// A user-entered value (Keychain/UserDefaults) always takes precedence.
    static let bundledDefault = "***REMOVED***"

    static func current() -> String {
        if let keychainValue = (try? KeychainCredentialStore.readString(account: keychainAccount))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainValue.isEmpty {
            return keychainValue
        }

        let defaultsValue = UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !defaultsValue.isEmpty {
            try? KeychainCredentialStore.writeString(defaultsValue, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: storageKey)
            return defaultsValue
        }
        return bundledDefault
    }

    static func clear() {
        try? KeychainCredentialStore.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    @MainActor
    static func promptForClientSecret() {
        let alert = NSAlert()
        alert.messageText = "Google OAuth Client Secret"
        alert.informativeText = "Insert the client secret for your Google Desktop OAuth app."
        alert.alertStyle = .informational

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "GOCSPX-..."
        field.stringValue = current()
        alert.accessoryView = field

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                clear()
            } else {
                try? KeychainCredentialStore.writeString(value, account: keychainAccount)
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
    }

    static func currentMaskedValue() -> String {
        let value = current()
        guard !value.isEmpty else { return "CLIENT SECRET: NOT SET" }
        if value.count <= 8 {
            return "CLIENT SECRET: \(value)"
        }
        return "CLIENT SECRET: \(value.prefix(4))...\(value.suffix(4))"
    }
}

private enum DownloadErrorPresenter {
    @MainActor
    static func present(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Google Drive Sign-In"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class GoogleOAuthLoopbackServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0

    private let listener: NWListener
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var continuation: CheckedContinuation<URL, Error>?
    private let queue = DispatchQueue(label: "GoogleOAuthLoopbackServer")

    private init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
    }

    static func start() async throws -> GoogleOAuthLoopbackServer {
        let server = try GoogleOAuthLoopbackServer()
        server.port = try await server.startListener()
        return server
    }

    deinit {
        listener.cancel()
    }

    func waitForRedirect(timeout: TimeInterval) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw DownloaderError.processFailed("GOOGLE SIGN-IN CALLBACK SERVER WAS RELEASED.")
                }
                return try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw DownloaderError.processFailed("GOOGLE SIGN-IN TIMED OUT. PLEASE TRY AGAIN.")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func startListener() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let boundPort = self.listener.port?.rawValue else {
                        self.readyContinuation?.resume(throwing: DownloaderError.processFailed("FAILED TO ALLOCATE LOCAL PORT FOR GOOGLE SIGN-IN."))
                        self.readyContinuation = nil
                        return
                    }
                    self.readyContinuation?.resume(returning: boundPort)
                    self.readyContinuation = nil
                case .failed(let error):
                    self.readyContinuation?.resume(throwing: error)
                    self.readyContinuation = nil
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.finish(with: error)
                connection.cancel()
                return
            }

            guard let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first else {
                self.finish(with: DownloaderError.processFailed("GOOGLE SIGN-IN CALLBACK WAS EMPTY."))
                connection.cancel()
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.finish(with: DownloaderError.processFailed("GOOGLE SIGN-IN CALLBACK WAS MALFORMED."))
                connection.cancel()
                return
            }

            let path = String(parts[1])
            let callbackURL = URL(string: "http://127.0.0.1:\(self.port)\(path)")
            let responseHTML = """
            <html><body style="font-family: -apple-system; padding: 24px;">Google sign-in completed. You can close this window.</body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(responseHTML.utf8.count)\r
            Connection: close\r
            \r
            \(responseHTML)
            """

            guard let callbackURL else {
                self.send(response, over: connection) {
                    self.finish(with: DownloaderError.processFailed("FAILED TO PARSE GOOGLE SIGN-IN CALLBACK URL."))
                }
                return
            }

            self.send(response, over: connection) {
                self.finish(with: callbackURL)
            }
        }
    }

    private func send(_ response: String, over connection: NWConnection, completion: @escaping @Sendable () -> Void) {
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            completion()
        })
    }

    private func finish(with url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
        listener.cancel()
    }

    private func finish(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        listener.cancel()
    }
}

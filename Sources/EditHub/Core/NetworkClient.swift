import Foundation

/// Типизированный HTTP-клиент для EditHub API.
/// Берёт базовый URL из UserDefaults (импортируется из iCloud auth.json) и JWT из AuthStore.
@MainActor
@Observable
final class NetworkClient {
    static let shared = NetworkClient()

    static let serverURLKey = "edithub.serverURL"
    static let defaultURL   = "http://127.0.0.1:3000"

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: Self.serverURLKey) }
    }

    private var baseURL: URL {
        URL(string: serverURL.trimmingCharacters(in: .init(charactersIn: "/"))) ?? URL(string: Self.defaultURL)!
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: - Auth

    func login(email: String, password: String) async throws -> AuthResponse {
        try await post("/auth/login", body: ["email": email, "password": password], auth: false)
    }

    func register(email: String, password: String, workspaceName: String) async throws -> AuthResponse {
        try await post("/auth/register",
            body: ["email": email, "password": password, "workspaceName": workspaceName],
            auth: false)
    }

    func logout() async throws {
        let _: EmptyResponse = try await post("/auth/logout", body: Empty(), auth: true)
    }

    func me() async throws -> MeResponse {
        try await get("/me")
    }

    // MARK: - Projects

    func getProjects() async throws -> [ServerProject] {
        try await get("/projects")
    }

    func createProject(_ p: ProjectPayload) async throws -> ServerProject {
        try await post("/projects", body: p, auth: true)
    }

    func updateProject(id: String, patch: ProjectPatch) async throws -> ServerProject {
        try await httpPatch("/projects/\(id)", body: patch)
    }

    func deleteProject(id: String) async throws {
        try await delete("/projects/\(id)")
    }

    // MARK: - Sync

    func localScan(projects: [LocalScanProject]) async throws -> LocalScanResponse {
        try await post("/sync/local-scan", body: ["projects": projects], auth: true)
    }

    func importICloudArchives(archives: [ArchivePayload]) async throws -> SyncResult {
        let r: ImportResponse = try await post("/sync/import-icloud-archives",
            body: ["archives": archives], auth: true)
        return r.sync
    }

    // MARK: - HTTP primitives

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        addAuth(&req)
        return try await perform(req)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, auth: Bool = true) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.iso.encode(body)
        if auth { addAuth(&req) }
        return try await perform(req)
    }

    private func httpPatch<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.iso.encode(body)
        addAuth(&req)
        return try await perform(req)
    }

    private func delete(_ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        addAuth(&req)
        let (_, resp) = try await session.data(for: req)
        try checkStatus(resp, data: Data())
    }

    private func addAuth(_ req: inout URLRequest) {
        if let token = AuthStore.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        try checkStatus(resp, data: data)
        return try JSONDecoder.iso.decode(T.self, from: data)
    }

    private func checkStatus(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error
                ?? "HTTP \(http.statusCode)"
            throw NetworkError.apiError(msg)
        }
    }
}

// MARK: - Errors

enum NetworkError: LocalizedError {
    case apiError(String)
    var errorDescription: String? {
        switch self { case .apiError(let m): return m }
    }
}

private struct APIError: Decodable { let error: String }
private struct Empty: Encodable {}
private struct EmptyResponse: Decodable {}

// Models live in Sources/EditHub/Models/ServerModels.swift

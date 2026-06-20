import Foundation

/// Проект как он приходит с сервера.
struct ServerProject: Decodable {
    let id: String
    let workspaceId: String
    let name: String
    let year: String
    let month: String
    let monthNumber: Int
    let template: String?
    let footageLinks: [String]
    let archiveRelativePath: String?
    let archiveByteCount: Int?
    let archiveChecksum: String?
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String
}

struct ProjectPayload: Encodable {
    let id: String
    let name: String
    let year: String
    let month: String
    let template: String?
    let footageLinks: [String]
    let archiveRelativePath: String?
    let archiveByteCount: Int?
    let archiveChecksum: String?
    let archivedAt: String?
}

struct ProjectPatch: Encodable {
    var name: String?
    var footageLinks: [String]?
    var archiveRelativePath: String?
    var archiveByteCount: Int?
    var archiveChecksum: String?
    var archivedAt: String?
}

struct LocalScanProject: Encodable {
    let id: String
    let name: String
    let year: String
    let month: String
    let template: String?
    let footageLinks: [String]
    let archiveRelativePath: String?
    let archiveByteCount: Int?
    let archivedAt: String?
    let updatedAt: String
}

struct LocalScanResponse: Decodable {
    let sync: SyncResult
    let projects: [ServerProject]
}

struct SyncResult: Decodable {
    let created: Int
    let updated: Int
    let skipped: Int
    let failed: [FailedItem]

    struct FailedItem: Decodable { let name: String; let reason: String }
}

struct ArchivePayload: Encodable {
    let id: String?
    let name: String
    let year: String
    let month: String
    let archiveRelativePath: String
    let archiveByteCount: Int?
    let archivedAt: String?
}

struct ImportResponse: Decodable {
    let sync: SyncResult
}

struct MeResponse: Decodable {
    struct User: Decodable { let id: String; let email: String }
    struct Workspace: Decodable { let id: String; let name: String }
    let user: User
    let workspace: Workspace
}

struct AuthResponse: Decodable {
    let token: String
    let userId: String
    let workspaceId: String
}

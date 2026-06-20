import Foundation

/// Lightweight local metadata that should survive across archive/restore cycles.
///
/// It is intentionally separate from `<project>.edithub`: that file marks an
/// archived project, while this hidden sidecar can exist for active projects too.
struct ProjectMetadata: Codable, Equatable {
    var version: Int = 2
    /// Стабильная идентичность проекта, не зависящая от пути на диске.
    /// Переживает переименование, перемещение и восстановление на другой машине.
    var projectId: UUID = UUID()
    var footageLinks: [String] = []
    var updatedAt: Date = Date()

    var primaryFootageLink: String? {
        footageLinks.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func load(from url: URL) throws -> ProjectMetadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso.decode(ProjectMetadata.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case version, projectId, footageLinks, updatedAt
    }

    /// Был ли `projectId` записан в файле. Если декодировали version-1 файл без
    /// id, дефолт `UUID()` даёт каждый раз новый id — это надо поймать и
    /// мигрировать (см. `ProjectMetadataStore.load`).
    var hasPersistedProjectId: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        footageLinks = try c.decodeIfPresent([String].self, forKey: .footageLinks) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        if let id = try c.decodeIfPresent(UUID.self, forKey: .projectId) {
            projectId = id
            hasPersistedProjectId = true
        } else {
            projectId = UUID()
            hasPersistedProjectId = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(projectId, forKey: .projectId)
        try c.encode(footageLinks, forKey: .footageLinks)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder.iso.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

enum ProjectMetadataStore {
    static let fileName = ".edithub-metadata.json"

    static func url(for projectURL: URL) -> URL {
        projectURL.appendingPathComponent(fileName)
    }

    /// Загрузить метаданные проекта. Если файл отсутствует — вернуть пустые с
    /// новым `projectId`. Если файл старого формата (без `projectId`) — выдать
    /// ему стабильный id и сразу записать обратно, иначе id «плавал» бы при
    /// каждом запуске.
    static func load(projectURL: URL) -> ProjectMetadata {
        guard var metadata = try? ProjectMetadata.load(from: url(for: projectURL)) else {
            return ProjectMetadata()
        }
        if !metadata.hasPersistedProjectId || metadata.version < 2 {
            metadata.version = 2
            metadata.hasPersistedProjectId = true
            // Закрепляем сгенерированный id на диске. Тихо игнорируем ошибку
            // записи (например, read-only volume) — id всё равно валиден в памяти.
            try? metadata.write(to: url(for: projectURL))
        }
        return metadata
    }

    static func save(_ metadata: ProjectMetadata, projectURL: URL) throws {
        var metadata = metadata
        metadata.version = 2
        metadata.updatedAt = Date()
        try metadata.write(to: url(for: projectURL))
    }

    static func setFootageLink(_ link: String, projectURL: URL) throws {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var metadata = load(projectURL: projectURL)
        metadata.footageLinks.removeAll { $0 == trimmed }
        metadata.footageLinks.insert(trimmed, at: 0)
        try save(metadata, projectURL: projectURL)
    }
}

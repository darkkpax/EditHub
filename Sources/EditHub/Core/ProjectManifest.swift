import Foundation
import CryptoKit

/// Файл-манифест `<ИМЯ>.edithub`, который остаётся в корне законсервированного
/// проекта. По нему [[ProjectArchiver]] восстанавливает проект из iCloud.
struct ProjectManifest: Codable {
    /// Версия формата — на будущее.
    var version: Int = 2
    /// Стабильная идентичность проекта (см. [[ProjectMetadata]]). Позволяет
    /// законсервированному проекту переподключиться к серверной записи.
    /// Опционально для совместимости со старыми манифестами без id.
    var projectId: String?
    var projectName: String
    var year: String
    var month: String
    var archivedAt: Date
    /// Относительный путь архива в iCloud (`Archive/2026/JUNE/NAME.zip`).
    var archiveRelativePath: String
    /// Какие тяжёлые папки были удалены при консервации.
    var removedHeavyFolders: [String]
    /// Размер архива в байтах (для UI).
    var archiveByteCount: Int64?
    /// SHA-256 hex архивного zip (для проверки целостности при восстановлении).
    var archiveChecksum: String?
    /// Links that can rebuild heavy folders after the light iCloud archive is restored.
    var footageLinks: [String]?

    var primaryFootageLink: String? {
        (footageLinks ?? []).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func load(from url: URL) throws -> ProjectManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso.decode(ProjectManifest.self, from: data)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder.iso.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - SHA-256 helper

enum FileChecksum {
    /// Считает SHA-256 файла потоково (не грузит весь файл в память).
    static func sha256(of url: URL) throws -> String {
        let bufferSize = 1 << 20  // 1 MB
        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            hasher.update(data: Data(bytes: buffer, count: read))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verify(url: URL, expected: String) throws {
        let actual = try sha256(of: url)
        guard actual == expected else {
            throw NSError(
                domain: "EditHub.Checksum",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Archive checksum mismatch — file may be corrupted."]
            )
        }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

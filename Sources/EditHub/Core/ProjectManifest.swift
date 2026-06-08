import Foundation

/// Файл-манифест `<ИМЯ>.edithub`, который остаётся в корне законсервированного
/// проекта. По нему [[ProjectArchiver]] восстанавливает проект из iCloud.
struct ProjectManifest: Codable {
    /// Версия формата — на будущее.
    var version: Int = 1
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

    static func load(from url: URL) throws -> ProjectManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso.decode(ProjectManifest.self, from: data)
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder.iso.encode(self)
        try data.write(to: url, options: .atomic)
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

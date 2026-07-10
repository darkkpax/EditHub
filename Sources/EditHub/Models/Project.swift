import Foundation

/// Один проект монтажа на диске: `<КОРЕНЬ>/<ГОД>/<МЕСЯЦ>/<ИМЯ>/`.
///
/// Сканируется с диска через [[ProjectStore]]. Признак консервации
/// определяется наличием файла-манифеста `<ИМЯ>.edithub` (см. [[ProjectArchiver]]).
struct Project: Identifiable, Hashable {
    /// Стабильная идентичность из метаданных, не зависит от пути на диске.
    let id: String
    let name: String
    /// Локальный путь на диске. `nil` для `remoteOnly` проектов.
    let url: URL?
    let year: String
    /// Месяц как он записан на диске (для отображения): `OCTOBER`, `October`…
    let month: String
    let createdAt: Date
    /// Проект законсервирован — тяжёлые папки удалены, ценное в архиве iCloud.
    let isArchived: Bool
    /// Относительный путь архива из серверной записи (для remoteOnly restore).
    let serverArchiveRelativePath: String?

    /// Проект есть только на сервере — локальной папки нет.
    var isRemoteOnly: Bool { url == nil }

    /// URL локальной папки. Вызывать только для локальных проектов — программная ошибка для remoteOnly.
    var localURL: URL { url! }

    // Локальный проект (с диска).
    init(id: String, url: URL, year: String, month: String, createdAt: Date, isArchived: Bool) {
        self.id = id
        self.name = url.lastPathComponent
        self.url = url
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.serverArchiveRelativePath = nil
    }

    // Удалённый проект (только сервер, нет на диске).
    init(serverProject s: ServerProject) {
        self.id   = s.id
        self.name = s.name
        self.url  = nil
        self.year = s.year
        self.month = s.month
        self.createdAt = ISO8601DateFormatter().date(from: s.createdAt) ?? .distantPast
        self.isArchived = s.archivedAt != nil
        self.serverArchiveRelativePath = s.archiveRelativePath
    }

    /// Канонический ключ месяца (`"01"..."12"`) для группировки и дедупликации —
    /// не зависит от регистра/языка записи на диске. См. [[MonthKey]].
    var monthKey: String { MonthKey.canonical(month) }

    /// URL подпапки проекта (например FOOTAGE). Nil для remoteOnly.
    func folderURL(_ folder: ProjectFolder) -> URL? {
        url?.appendingPathComponent(folder.folderName, isDirectory: true)
    }

    /// Путь к файлу-манифесту консервации. Nil для remoteOnly.
    var manifestURL: URL? {
        url?.appendingPathComponent("\(name).edithub")
    }

    var metadataURL: URL? {
        url.map { ProjectMetadataStore.url(for: $0) }
    }

    var metadata: ProjectMetadata {
        url.map { ProjectMetadataStore.load(projectURL: $0) } ?? ProjectMetadata()
    }
}

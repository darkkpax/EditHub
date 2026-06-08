import Foundation

/// Доступ к папке приложения в iCloud Drive для хранения архивов
/// законсервированных проектов. Используется [[ProjectArchiver]].
///
/// Архивы лежат по пути `<iCloud>/Documents/Archive/<ГОД>/<МЕСЯЦ>/<ИМЯ>.zip`.
enum iCloudStore {
    enum iCloudError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "ICLOUD DRIVE IS NOT AVAILABLE. SIGN IN TO ICLOUD AND ENABLE ICLOUD DRIVE."
            }
        }
    }

    /// Корень iCloud-контейнера приложения (`.../Documents`). Может быть nil,
    /// если пользователь не залогинен в iCloud.
    static var documentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    static var isAvailable: Bool { documentsURL != nil }

    /// Папка архива (создаётся при необходимости).
    static func archiveDirectory() throws -> URL {
        guard let docs = documentsURL else { throw iCloudError.unavailable }
        let dir = docs.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// URL архива для конкретного проекта: `Archive/<ГОД>/<МЕСЯЦ>/<ИМЯ>.zip`.
    static func archiveURL(for project: Project) throws -> URL {
        try archiveDirectory()
            .appendingPathComponent(project.year, isDirectory: true)
            .appendingPathComponent(project.month, isDirectory: true)
            .appendingPathComponent("\(project.name).zip")
    }

    /// Относительный путь архива (хранится в манифесте, не зависит от машины).
    static func relativeArchivePath(for project: Project) -> String {
        "Archive/\(project.year)/\(project.month)/\(project.name).zip"
    }

    /// Восстановить абсолютный URL архива из относительного пути в манифесте.
    static func resolveArchiveURL(relativePath: String) throws -> URL {
        guard let docs = documentsURL else { throw iCloudError.unavailable }
        return docs.appendingPathComponent(relativePath)
    }

    /// Если файл в iCloud ещё не скачан локально — запросить загрузку и подождать.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120) throws {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if values?.ubiquitousItemDownloadingStatus == .current { return }

        try fm.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if status == .current || fm.fileExists(atPath: url.path) {
                // Файл может всё ещё иметь префикс .icloud — проверяем реальное наличие.
                if fm.fileExists(atPath: url.path) { return }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

import Foundation

/// Доступ к выбранной пользователем папке архива в iCloud Drive.
///
/// Раньше использовался app-container (`forUbiquityContainerIdentifier:`), но он
/// macOS-специфичен и не виден iCloud for Windows. Теперь корень архива — это
/// обычная папка iCloud Drive, выбранная пользователем (например
/// `iCloud Drive/EditHub` или существующая `iCloud Drive/Videos`), сохранённая
/// как security-scoped bookmark. На диске и в манифестах хранятся только
/// относительные пути, поэтому каждая машина резолвит их от своего корня.
///
/// Архивы лежат по пути `<корень>/Archive/<ГОД>/<МЕСЯЦ>/<ИМЯ>.zip`.
@MainActor
@Observable
final class iCloudStore {
    enum iCloudError: LocalizedError {
        case rootNotSelected
        case downloadTimedOut(URL)

        var errorDescription: String? {
            switch self {
            case .rootNotSelected:
                return "ICLOUD ARCHIVE FOLDER IS NOT SELECTED. CHOOSE A FOLDER INSIDE ICLOUD DRIVE."
            case .downloadTimedOut(let url):
                return "ICLOUD ARCHIVE DID NOT FINISH DOWNLOADING: \(url.lastPathComponent)"
            }
        }
    }

    /// Общий инстанс — корень архива один на приложение.
    static let shared = iCloudStore()

    @ObservationIgnored
    private let bookmarkStore = FolderBookmarkStore(
        defaultsKey: "selectedICloudArchiveBookmark",
        pathDefaultsKey: "selectedICloudArchivePath"
    )

    /// Выбранный пользователем корень архива в iCloud Drive.
    var rootURL: URL? { bookmarkStore.selectedURL }

    var rootDisplayPath: String { bookmarkStore.displayPath }

    var isAvailable: Bool { bookmarkStore.selectedURL != nil }

    /// Запомнить выбранную папку как корень архива.
    func setRoot(_ url: URL) throws {
        try bookmarkStore.setSelectedURL(url)
    }

    /// Относительный путь архива (хранится в манифесте, не зависит от машины):
    /// `Archive/<ГОД>/<МЕСЯЦ>/<ИМЯ>.zip`. Чистая функция — не требует
    /// выбранного корня, поэтому статическая.
    nonisolated static func relativeArchivePath(for project: Project) -> String {
        "Archive/\(project.year)/\(project.month)/\(project.name).zip"
    }

    /// Абсолютный URL архива для проекта, резолвнутый из выбранного корня.
    func archiveURL(for project: Project) throws -> URL {
        try resolveArchiveURL(relativePath: Self.relativeArchivePath(for: project))
    }

    /// Восстановить абсолютный URL архива из относительного пути в манифесте.
    func resolveArchiveURL(relativePath: String) throws -> URL {
        guard let root = rootURL else { throw iCloudError.rootNotSelected }
        return root.appendingPathComponent(relativePath)
    }

    /// Если файл в iCloud ещё не скачан локально — запросить загрузку и подождать.
    ///
    /// Это macOS-реализация через ubiquity-API. На Windows эквивалент — просто
    /// прочитать файл целиком (чтение материализует placeholder), см. план.
    /// Статическая и `nonisolated` — безопасно звать из фонового контекста.
    nonisolated static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120) throws {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        let initialStatus = values?.ubiquitousItemDownloadingStatus
        if initialStatus == .current ||
            initialStatus == .downloaded ||
            (initialStatus == nil && fm.fileExists(atPath: url.path)) {
            return
        }

        try fm.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if status == .current || status == .downloaded ||
                (status == nil && fm.fileExists(atPath: url.path)) {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        throw iCloudError.downloadTimedOut(url)
    }
}

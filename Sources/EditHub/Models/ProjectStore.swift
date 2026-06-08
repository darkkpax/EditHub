import Foundation
import Combine

/// Сканирует корневую папку проектов (`<КОРЕНЬ>/<ГОД>/<МЕСЯЦ>/<ИМЯ>/`)
/// и держит актуальный список [[Project]]. Корень хранится через
/// [[FolderBookmarkStore]] (security-scoped bookmark для sandbox).
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var isScanning = false

    let bookmarkStore = FolderBookmarkStore()

    private var watcher: DirectoryWatcher?

    init() {
        if bookmarkStore.selectedURL != nil {
            refresh()
            startWatching()
        }
    }

    var rootURL: URL? { bookmarkStore.selectedURL }

    var rootDisplayPath: String { bookmarkStore.displayPath }

    func setRoot(_ url: URL) throws {
        try bookmarkStore.setSelectedURL(url)
        refresh()
        startWatching()
    }

    /// Проекты, сгруппированные по году и месяцу (для секций в списке).
    var grouped: [(key: String, projects: [Project])] {
        let groups = Dictionary(grouping: projects) { "\($0.year) · \($0.month)" }
        return groups
            .map { (key: $0.key, projects: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.key > $1.key }
    }

    func refresh() {
        guard let root = rootURL else {
            projects = []
            return
        }

        isScanning = true
        let scanned = Self.scan(root: root)
        projects = scanned
        isScanning = false
    }

    private func startWatching() {
        guard let root = rootURL else { return }
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Scanning

    private static func scan(root: URL) -> [Project] {
        let fm = FileManager.default
        var result: [Project] = []

        let years = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for yearURL in years where yearURL.hasDirectoryPath {
            let year = yearURL.lastPathComponent
            let months = (try? fm.contentsOfDirectory(at: yearURL, includingPropertiesForKeys: nil)) ?? []
            for monthURL in months where monthURL.hasDirectoryPath {
                let month = monthURL.lastPathComponent
                let projectDirs = (try? fm.contentsOfDirectory(
                    at: monthURL,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                for projectURL in projectDirs where projectURL.hasDirectoryPath {
                    let values = try? projectURL.resourceValues(forKeys: [.creationDateKey])
                    let created = values?.creationDate ?? Date.distantPast
                    let manifest = projectURL.appendingPathComponent("\(projectURL.lastPathComponent).edithub")
                    let isArchived = fm.fileExists(atPath: manifest.path)

                    result.append(
                        Project(
                            url: projectURL,
                            year: year,
                            month: month,
                            createdAt: created,
                            isArchived: isArchived
                        )
                    )
                }
            }
        }

        return result.sorted { $0.createdAt > $1.createdAt }
    }
}

/// Лёгкий наблюдатель за изменениями каталога через `DispatchSource`.
private final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32

    init?(url: URL, onChange: @escaping () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        var lastFire = Date.distantPast
        source.setEventHandler {
            // Дебаунс — каталог может «дёргаться» пачкой событий.
            let now = Date()
            guard now.timeIntervalSince(lastFire) > 0.4 else { return }
            lastFire = now
            onChange()
        }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

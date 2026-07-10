import Foundation
import Observation

/// Сканирует корневую папку проектов (`<КОРЕНЬ>/<ГОД>/<МЕСЯЦ>/<ИМЯ>/`)
/// и держит актуальный список [[Project]]. Корень хранится через
/// [[FolderBookmarkStore]] (security-scoped bookmark для sandbox).
@MainActor
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    private(set) var isScanning = false

    let bookmarkStore = FolderBookmarkStore()

    @ObservationIgnored
    private var watcher: DirectoryWatcher?

    init() {
        if bookmarkStore.selectedURL != nil {
            refresh()
            startWatching()
        }
    }

    var rootURL: URL? { bookmarkStore.selectedURL }

    var rootDisplayPath: String { bookmarkStore.displayPath }

    /// Есть ли в текущем корне хоть одна папка-год. Если корень выбран,
    /// но `false` — значит выбрали не ту папку (например на уровень выше/ниже).
    var hasYearFolders: Bool {
        guard let root = rootURL else { return false }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return entries.contains { $0.hasDirectoryPath && Self.isYearFolder($0.lastPathComponent) }
    }

    /// Если внутри корня есть РОВНО одна подпапка, а в ней уже лежат годы —
    /// это и есть настоящий корень проектов. Возвращаем подсказку для авто-фикса.
    var suggestedRoot: URL? {
        guard let root = rootURL, !hasYearFolders else { return nil }
        let dirs = ((try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []).filter(\.hasDirectoryPath)
        return dirs.first { candidate in
            let inner = (try? FileManager.default.contentsOfDirectory(
                at: candidate, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            return inner.contains { $0.hasDirectoryPath && Self.isYearFolder($0.lastPathComponent) }
        }
    }

    func setRoot(_ url: URL) throws {
        try bookmarkStore.setSelectedURL(url)
        refresh()
        startWatching()
    }

    /// Проекты, сгруппированные по году и месяцу (для секций в списке).
    ///
    /// Группировка идёт по каноническому ключу месяца (`monthKey`), чтобы
    /// `October` и `OCTOBER` не расходились в две секции. Сортировка — по
    /// стабильному `год/номер-месяца` (убывание), а в заголовке показываем имя
    /// месяца как оно записано на диске у первого проекта группы.
    var grouped: [(key: String, projects: [Project])] {
        let groups = Dictionary(grouping: projects) { "\($0.year)/\($0.monthKey)" }
        return groups
            .map { (sortKey, items) -> (sortKey: String, key: String, projects: [Project]) in
                let sorted = items.sorted { $0.name < $1.name }
                let label = "\(sorted[0].year) · \(sorted[0].month)"
                return (sortKey: sortKey, key: label, projects: sorted)
            }
            .sorted { $0.sortKey > $1.sortKey }
            .map { (key: $0.key, projects: $0.projects) }
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

    /// Отправляет текущий локальный список на сервер и добавляет в UI проекты,
    /// которые есть только на сервере (remoteOnly — заархивированы, нет локальной папки).
    func syncWithServer() {
        guard AuthStore.shared.isLoggedIn else { return }
        Task {
            do {
                let localPayloads = projects.compactMap { p -> LocalScanProject? in
                    guard !p.isRemoteOnly else { return nil }
                    let meta = p.metadata
                    let fmt = ISO8601DateFormatter()
                    return LocalScanProject(
                        id: p.id,
                        name: p.name,
                        year: p.year,
                        month: p.month,
                        template: nil,
                        footageLinks: meta.footageLinks,
                        archiveRelativePath: p.isArchived
                            ? iCloudStore.relativeArchivePath(for: p) : nil,
                        archiveByteCount: nil,
                        archivedAt: p.isArchived ? fmt.string(from: Date()) : nil,
                        updatedAt: fmt.string(from: Date())
                    )
                }
                let response = try await NetworkClient.shared.localScan(projects: localPayloads)
                mergeRemoteProjects(response.projects)
            } catch {
                NSLog("[ProjectStore] syncWithServer error: \(error)")
            }
        }
    }

    /// Добавляет в список проекты с сервера, которых нет локально.
    private func mergeRemoteProjects(_ serverProjects: [ServerProject]) {
        let localIDs = Set(projects.compactMap { $0.isRemoteOnly ? nil : $0.id })
        let remoteOnly = serverProjects
            .filter { !localIDs.contains($0.id) && $0.archivedAt != nil }
            .map { Project(serverProject: $0) }

        // Убираем устаревшие remoteOnly, добавляем свежие.
        var updated = projects.filter { !$0.isRemoteOnly }
        updated.append(contentsOf: remoteOnly)
        projects = updated
    }

    private func startWatching() {
        guard let root = rootURL else { return }
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Scanning

    /// Год = ровно 4 цифры (2020, 2026 …). Любые другие папки в корне
    /// (заметки, мусор, .DS_Store-подобное) игнорируются — иначе список
    /// «уезжает» и реальные годы не видно.
    static func isYearFolder(_ name: String) -> Bool {
        name.count == 4 && name.allSatisfy(\.isNumber)
    }

    private static func scan(root: URL) -> [Project] {
        let fm = FileManager.default
        var result: [Project] = []

        let years = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for yearURL in years where yearURL.hasDirectoryPath {
            let year = yearURL.lastPathComponent
            guard isYearFolder(year) else { continue }
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

                    // Стабильный id из метаданных (мигрирует/создаётся при загрузке).
                    let projectId = ProjectMetadataStore.load(projectURL: projectURL).projectId

                    result.append(
                        Project(
                            id: projectId,
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

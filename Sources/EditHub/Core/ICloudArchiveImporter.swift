import Foundation

/// Импортирует существующие zip-архивы из iCloud Drive в список проектов
/// EditHub, создавая для каждого пустую папку-заглушку + манифест `.edithub`.
///
/// Понимает две раскладки (обе без предварительной конвертации):
/// - Старая: `<корень>/ГОД/Месяц/ИМЯ.zip` (например `Videos/2025/October/...`)
/// - Новая:  `<корень>/Archive/ГОД/Месяц/ИМЯ.zip`
///
/// После импорта обычный `ProjectStore.scan` подхватывает папки автоматически —
/// они выглядят как законсервированные проекты (`isArchived == true`).
enum ICloudArchiveImporter {
    struct ImportResult {
        var imported: Int = 0    // новые
        var skipped: Int = 0     // уже есть
        var failed: Int = 0
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if imported > 0 { parts.append("\(imported) imported") }
            if skipped  > 0 { parts.append("\(skipped) already exist") }
            if failed   > 0 { parts.append("\(failed) failed") }
            return parts.isEmpty ? "Nothing found" : parts.joined(separator: ", ")
        }
    }

    /// Отсканировать `iCloudRoot` и создать заглушки в `projectsRoot`.
    ///
    /// - Parameters:
    ///   - iCloudRoot: выбранный пользователем корень архива iCloud (например
    ///     `iCloud Drive/Videos` или `iCloud Drive/EditHub`).
    ///   - projectsRoot: корень проектов (`VIDEOS`), куда создаются заглушки.
    ///   - progress: замыкание, вызываемое на каждом найденном zip.
    ///     Принимает `(current, total)`.
    static func `import`(
        from iCloudRoot: URL,
        into projectsRoot: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> ImportResult {
        let zips = findArchives(in: iCloudRoot)
        var result = ImportResult()
        let total = zips.count

        for (idx, entry) in zips.enumerated() {
            progress?(idx + 1, total)
            do {
                let created = try importOne(entry: entry, projectsRoot: projectsRoot)
                if created { result.imported += 1 } else { result.skipped += 1 }
            } catch {
                result.failed += 1
                result.errors.append("\(entry.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    // MARK: - Scanning

    struct ArchiveEntry {
        var zipURL: URL
        var year: String
        var month: String       // как на диске: "October", "OCTOBER" и т.п.
        var name: String        // имя без .zip
        /// Относительный путь от iCloudRoot для хранения в манифесте.
        var relativePath: String
    }

    /// Найти все zip-архивы в корне, принимая обе раскладки.
    static func findArchives(in root: URL) -> [ArchiveEntry] {
        let fm = FileManager.default
        var result: [ArchiveEntry] = []

        // Уровень 1: папки года (4 цифры) или "Archive"
        guard let topDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        for top in topDirs where top.hasDirectoryPath {
            let topName = top.lastPathComponent

            if topName == "Archive" {
                // Новая схема: Archive/ГОД/Месяц/ИМЯ.zip
                result += scanYearLevel(root: top, archivePrefix: "Archive", iCloudRoot: root)
            } else if isYear(topName) {
                // Старая схема: ГОД/Месяц/ИМЯ.zip
                result += scanMonthLevel(yearURL: top, year: topName, archivePrefix: topName, iCloudRoot: root)
            }
        }
        return result
    }

    private static func scanYearLevel(root: URL, archivePrefix: String, iCloudRoot: URL) -> [ArchiveEntry] {
        let fm = FileManager.default
        var result: [ArchiveEntry] = []
        guard let yearDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        for yearURL in yearDirs where yearURL.hasDirectoryPath {
            let year = yearURL.lastPathComponent
            guard isYear(year) else { continue }
            result += scanMonthLevel(
                yearURL: yearURL, year: year,
                archivePrefix: "\(archivePrefix)/\(year)", iCloudRoot: iCloudRoot
            )
        }
        return result
    }

    private static func scanMonthLevel(
        yearURL: URL, year: String, archivePrefix: String, iCloudRoot: URL
    ) -> [ArchiveEntry] {
        let fm = FileManager.default
        var result: [ArchiveEntry] = []
        guard let monthDirs = try? fm.contentsOfDirectory(
            at: yearURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        for monthURL in monthDirs where monthURL.hasDirectoryPath {
            let month = monthURL.lastPathComponent
            // Принимаем только папки, которые MonthKey распознаёт как месяц.
            guard MonthKey.number(from: month) != nil else { continue }

            guard let zips = try? fm.contentsOfDirectory(
                at: monthURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for zip in zips where zip.pathExtension.lowercased() == "zip" {
                let name = zip.deletingPathExtension().lastPathComponent
                let rel  = "\(archivePrefix)/\(month)/\(zip.lastPathComponent)"
                result.append(ArchiveEntry(
                    zipURL: zip, year: year, month: month, name: name, relativePath: rel
                ))
            }
        }
        return result
    }

    // MARK: - Per-archive import

    /// Создать папку-заглушку + манифест в projectsRoot.
    /// Возвращает `true` если создано новое, `false` если уже существует.
    @discardableResult
    private static func importOne(entry: ArchiveEntry, projectsRoot: URL) throws -> Bool {
        let fm = FileManager.default

        let projectURL = projectsRoot
            .appendingPathComponent(entry.year, isDirectory: true)
            .appendingPathComponent(entry.month.uppercased(), isDirectory: true)
            .appendingPathComponent(entry.name, isDirectory: true)

        let manifestURL = projectURL.appendingPathComponent("\(entry.name).edithub")

        // Уже импортировано — манифест есть.
        if fm.fileExists(atPath: manifestURL.path) { return false }

        // Создаём папку (и год/месяц если нет).
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        // Достаём размер архива (может быть placeholder — тогда 0).
        let size = (try? entry.zipURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize).map(Int64.init) ?? 0

        // Генерируем projectId и сохраняем метаданные.
        let metadata = ProjectMetadataStore.load(projectURL: projectURL)
        let metaURL  = ProjectMetadataStore.url(for: projectURL)
        try? metadata.write(to: metaURL)

        // Пишем манифест — проект считается законсервированным.
        let manifest = ProjectManifest(
            projectId: metadata.projectId,
            projectName: entry.name,
            year: entry.year,
            month: entry.month,
            archivedAt: Date(),
            archiveRelativePath: entry.relativePath,
            removedHeavyFolders: [],
            archiveByteCount: size > 0 ? size : nil,
            footageLinks: nil
        )
        try manifest.write(to: manifestURL)

        return true
    }

    // MARK: - Helpers

    private static func isYear(_ name: String) -> Bool {
        name.count == 4 && name.allSatisfy(\.isNumber)
    }
}

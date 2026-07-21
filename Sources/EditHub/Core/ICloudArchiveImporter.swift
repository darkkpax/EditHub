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
        var isDirectory: Bool
        var year: String
        var month: String       // как на диске: "October", "OCTOBER" и т.п.
        var name: String        // имя без .zip
        /// Относительный путь от iCloudRoot для хранения в манифесте.
        var relativePath: String
    }

    /// Finds both Mac ZIP archives and Flutter/Windows directory archives.
    /// Flutter stores them below `edithub/Videos/<year>/<month>/<project>`.
    static func findArchives(in root: URL) -> [ArchiveEntry] {
        let fm = FileManager.default
        var result: [ArchiveEntry] = []

        let candidates = [
            root,
            root.appendingPathComponent("Archive", isDirectory: true),
            root.appendingPathComponent("Videos", isDirectory: true),
            root.appendingPathComponent("EditHub/Videos", isDirectory: true),
            root.appendingPathComponent("Edit Hub/Videos", isDirectory: true),
            root.appendingPathComponent("edithub/Videos", isDirectory: true)
        ]

        var visited = Set<String>()
        for archiveRoot in candidates {
            let path = archiveRoot.standardizedFileURL.path
            guard visited.insert(path).inserted,
                  fm.fileExists(atPath: path),
                  let yearDirs = try? fm.contentsOfDirectory(
                    at: archiveRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }

            let prefix = relativePath(of: archiveRoot, from: root)
            for yearURL in yearDirs where yearURL.hasDirectoryPath && isYear(yearURL.lastPathComponent) {
                let year = yearURL.lastPathComponent
                let yearPrefix = prefix.isEmpty ? year : "\(prefix)/\(year)"
                result += scanMonthLevel(
                    yearURL: yearURL,
                    year: year,
                    archivePrefix: yearPrefix,
                    iCloudRoot: root
                )
            }
        }
        return Dictionary(grouping: result, by: \.relativePath).compactMap(\.value.first)
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

            guard let archives = try? fm.contentsOfDirectory(
                at: monthURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for archive in archives {
                let isDirectory = archive.hasDirectoryPath
                guard isDirectory || archive.pathExtension.lowercased() == "zip" else { continue }
                let name = isDirectory ? archive.lastPathComponent : archive.deletingPathExtension().lastPathComponent
                let rel  = "\(archivePrefix)/\(month)/\(archive.lastPathComponent)"
                result.append(ArchiveEntry(
                    zipURL: archive,
                    isDirectory: isDirectory,
                    year: year,
                    month: month,
                    name: name,
                    relativePath: rel
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

        // Existing active local projects win over an archived iCloud copy.
        if fm.fileExists(atPath: manifestURL.path) { return false }
        if fm.fileExists(atPath: projectURL.path) { return false }

        // Создаём папку (и год/месяц если нет).
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        // Достаём размер архива (может быть placeholder — тогда 0).
        let size = entry.isDirectory ? 0 : (try? entry.zipURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize).map(Int64.init) ?? 0

        // Preserve Flutter identity and footage links when the archive is a folder.
        var metadata = ProjectMetadataStore.load(projectURL: projectURL)
        if entry.isDirectory,
           let data = try? Data(contentsOf: entry.zipURL.appendingPathComponent(".edithub.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let id = json["id"] as? String, !id.isEmpty { metadata.projectId = id }
            metadata.footageLinks = (json["footageUrls"] as? [String]) ?? metadata.footageLinks
        }
        try? ProjectMetadataStore.save(metadata, projectURL: projectURL)

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
            footageLinks: metadata.footageLinks
        )
        try manifest.write(to: manifestURL)

        return true
    }

    // MARK: - Helpers

    private static func isYear(_ name: String) -> Bool {
        name.count == 4 && name.allSatisfy(\.isNumber)
    }

    private static func relativePath(of child: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        guard childPath != rootPath, childPath.hasPrefix(rootPath + "/") else { return "" }
        return String(childPath.dropFirst(rootPath.count + 1))
    }
}

import Foundation

/// Консервация и восстановление проектов.
///
/// **Консервация**: ценные папки ([[ProjectFolder]] где `isValuable`) + файлы
/// проекта пакуются в zip и уходят в iCloud ([[iCloudStore]]). Тяжёлые папки
/// (FOOTAGE) удаляются локально. В корне остаётся манифест `.edithub`
/// ([[ProjectManifest]]).
///
/// **Восстановление**: архив тянется из iCloud и распаковывается обратно.
enum ProjectArchiver {
    enum ArchiverError: LocalizedError {
        case alreadyArchived
        case notArchived
        case manifestMissing

        var errorDescription: String? {
            switch self {
            case .alreadyArchived: return "PROJECT IS ALREADY ARCHIVED."
            case .notArchived: return "PROJECT IS NOT ARCHIVED."
            case .manifestMissing: return "MANIFEST FILE IS MISSING OR INVALID."
            }
        }
    }

    // MARK: - Консервация

    /// Законсервировать проект: упаковать ценное в iCloud, удалить выбранные
    /// тяжёлые папки.
    /// - Parameters:
    ///   - project: проект для консервации.
    ///   - foldersToRemove: какие тяжёлые папки очистить локально. По умолчанию —
    ///     все тяжёлые (`ProjectFolder.removableOnArchive`). Пользователь может
    ///     передать подмножество, чтобы что-то оставить на диске.
    /// - Parameter destinationURL: абсолютный URL архива в iCloud, заранее
    ///   резолвнутый из выбранного корня (`iCloudStore.archiveURL(for:)`) на
    ///   MainActor. Передаётся параметром, чтобы тяжёлую работу можно было
    ///   выполнять в фоне, не обращаясь к `@MainActor`-стору.
    static func archive(
        _ project: Project,
        destinationURL: URL,
        foldersToRemove: Set<ProjectFolder> = Set(ProjectFolder.removableOnArchive)
    ) throws {
        guard !project.isArchived else { throw ArchiverError.alreadyArchived }

        let fm = FileManager.default

        let localURL = project.localURL
        let metadata = ProjectMetadataStore.load(projectURL: localURL)

        // 1. Staging — копируем ценные папки, метаданные и файлы проекта во временный каталог.
        let staging = fm.temporaryDirectory
            .appendingPathComponent("edithub-archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let metadataURL = ProjectMetadataStore.url(for: localURL)
        if fm.fileExists(atPath: metadataURL.path) {
            try? fm.copyItem(at: metadataURL, to: staging.appendingPathComponent(ProjectMetadataStore.fileName))
        }

        for folder in ProjectFolder.allCases where folder.isValuable {
            guard let src = project.folderURL(folder) else { continue }
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = staging.appendingPathComponent(folder.folderName, isDirectory: true)
            try fm.copyItem(at: src, to: dst)
        }

        // Файлы проекта в корне (.prproj/.aep/.drp и т.п.) — тоже в архив.
        let rootEntries = (try? fm.contentsOfDirectory(at: localURL, includingPropertiesForKeys: nil)) ?? []
        for entry in rootEntries where !entry.hasDirectoryPath {
            let ext = entry.pathExtension.lowercased()
            guard ["prproj", "aep", "drp", "fcpbundle", "txt", "pdf"].contains(ext) else { continue }
            try? fm.copyItem(at: entry, to: staging.appendingPathComponent(entry.lastPathComponent))
        }

        // 2. Zip → iCloud. Папки года/месяца внутри Archive создаём здесь.
        try fm.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ZipArchiver.archive(directory: staging, outputURL: destinationURL)
        let size = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let checksum = try? FileChecksum.sha256(of: destinationURL)

        // 3. Удаляем выбранные тяжёлые папки локально (содержимое; папку оставляем пустой).
        var removed: [String] = []
        for folder in ProjectFolder.allCases where folder.isHeavy && foldersToRemove.contains(folder) {
            guard let dir = project.folderURL(folder) else { continue }
            guard fm.fileExists(atPath: dir.path) else { continue }
            let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in contents { try? fm.removeItem(at: item) }
            removed.append(folder.folderName)
        }

        // 4. Удаляем ценные папки локально (они теперь в архиве), оставляем структуру.
        for folder in ProjectFolder.allCases where folder.isValuable {
            guard let dir = project.folderURL(folder) else { continue }
            let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in contents { try? fm.removeItem(at: item) }
        }

        // 5. Пишем манифест.
        guard let manifestURL = project.manifestURL else { return }
        let manifest = ProjectManifest(
            projectId: metadata.projectId,
            projectName: project.name,
            year: project.year,
            month: project.month,
            archivedAt: Date(),
            archiveRelativePath: iCloudStore.relativeArchivePath(for: project),
            removedHeavyFolders: removed,
            archiveByteCount: size,
            archiveChecksum: checksum,
            footageLinks: metadata.footageLinks
        )
        try manifest.write(to: manifestURL)
    }

    // MARK: - Восстановление

    /// Восстановить проект из архива в iCloud. Возвращает URL проекта.
    /// - Parameter archiveRoot: выбранный корень iCloud, от которого резолвится
    ///   относительный путь архива из манифеста. Передаётся параметром, чтобы
    ///   распаковку можно было крутить в фоне без обращения к `@MainActor`-стору.
    @discardableResult
    static func restore(manifestURL: URL, archiveRoot: URL) throws -> URL {
        let fm = FileManager.default
        let projectURL = manifestURL.deletingLastPathComponent()

        let manifest: ProjectManifest
        do {
            manifest = try ProjectManifest.load(from: manifestURL)
        } catch {
            throw ArchiverError.manifestMissing
        }

        let archiveURL = archiveRoot.appendingPathComponent(manifest.archiveRelativePath)
        let isDirectory = (try? archiveURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory {
            // Flutter/Windows archives are complete project directories rather than ZIP files.
            try copyDirectoryContents(from: archiveURL, to: projectURL)
        } else {
            try iCloudStore.ensureDownloaded(archiveURL)
            if let expected = manifest.archiveChecksum {
                try FileChecksum.verify(url: archiveURL, expected: expected)
            }
            try ZipArchiver.unzip(archive: archiveURL, destination: projectURL)
        }

        var metadata = ProjectMetadataStore.load(projectURL: projectURL)
        // Сохраняем идентичность из манифеста, если в распакованных метаданных
        // её не было (старый архив без `.edithub-metadata.json`).
        var metadataChanged = false
        if let id = manifest.projectId, metadata.projectId != id {
            metadata.projectId = id
            metadataChanged = true
        }
        for link in (manifest.footageLinks ?? []).reversed() {
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            metadata.footageLinks.removeAll { $0 == trimmed }
            metadata.footageLinks.insert(trimmed, at: 0)
            metadataChanged = true
        }
        if metadataChanged {
            try? ProjectMetadataStore.save(metadata, projectURL: projectURL)
        }

        // Убираем манифест — проект снова «живой».
        try? fm.removeItem(at: manifestURL)

        return projectURL
    }

    private static func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: entry, to: target)
        }
        // Hidden compatibility manifests are intentionally copied as well.
        for hiddenName in [".edithub.json", ".edithub-metadata.json"] {
            let entry = source.appendingPathComponent(hiddenName)
            guard fm.fileExists(atPath: entry.path) else { continue }
            let target = destination.appendingPathComponent(hiddenName)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: entry, to: target)
        }
    }

    // MARK: - Восстановление remoteOnly-проекта

    /// Восстановить проект, у которого нет локальной папки (только запись на сервере).
    /// Создаёт `<projectsRoot>/<year>/<MONTH_UPPER>/<name>/`, распаковывает архив из iCloud.
    /// - Returns: URL созданной папки проекта.
    @discardableResult
    static func restoreRemoteOnly(
        project: Project,
        projectsRoot: URL,
        archiveRoot: URL
    ) throws -> URL {
        guard let relativePath = project.serverArchiveRelativePath else {
            throw ArchiverError.manifestMissing
        }

        let fm = FileManager.default
        let month = project.month.uppercased()
        let projectDir = projectsRoot
            .appendingPathComponent(project.year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(project.name, isDirectory: true)

        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Стандартные подпапки — чтобы структура была сразу на месте.
        for folder in ProjectFolder.allCases {
            let sub = projectDir.appendingPathComponent(folder.folderName, isDirectory: true)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: false)
        }

        let archiveURL = archiveRoot.appendingPathComponent(relativePath)
        let isDirectory = (try? archiveURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory {
            try copyDirectoryContents(from: archiveURL, to: projectDir)
        } else {
            try iCloudStore.ensureDownloaded(archiveURL)
            try ZipArchiver.unzip(archive: archiveURL, destination: projectDir)
        }

        // Фиксируем UUID.
        var metadata = ProjectMetadataStore.load(projectURL: projectDir)
        let targetID = project.id
        if metadata.projectId != targetID {
            metadata.projectId = targetID
            try? ProjectMetadataStore.save(metadata, projectURL: projectDir)
        }

        return projectDir
    }
}

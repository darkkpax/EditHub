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
    static func archive(
        _ project: Project,
        foldersToRemove: Set<ProjectFolder> = Set(ProjectFolder.removableOnArchive)
    ) throws {
        guard !project.isArchived else { throw ArchiverError.alreadyArchived }

        let fm = FileManager.default

        // 1. Staging — копируем ценные папки и файлы проекта во временный каталог.
        let staging = fm.temporaryDirectory
            .appendingPathComponent("edithub-archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for folder in ProjectFolder.allCases where folder.isValuable {
            let src = project.folderURL(folder)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = staging.appendingPathComponent(folder.folderName, isDirectory: true)
            try fm.copyItem(at: src, to: dst)
        }

        // Файлы проекта в корне (.prproj/.aep/.drp и т.п.) — тоже в архив.
        let rootEntries = (try? fm.contentsOfDirectory(at: project.url, includingPropertiesForKeys: nil)) ?? []
        for entry in rootEntries where !entry.hasDirectoryPath {
            let ext = entry.pathExtension.lowercased()
            guard ["prproj", "aep", "drp", "fcpbundle", "txt", "pdf"].contains(ext) else { continue }
            try? fm.copyItem(at: entry, to: staging.appendingPathComponent(entry.lastPathComponent))
        }

        // 2. Zip → iCloud.
        let destinationURL = try iCloudStore.archiveURL(for: project)
        try ZipArchiver.archive(directory: staging, outputURL: destinationURL)
        let size = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)

        // 3. Удаляем выбранные тяжёлые папки локально (содержимое; папку оставляем пустой).
        var removed: [String] = []
        for folder in ProjectFolder.allCases where folder.isHeavy && foldersToRemove.contains(folder) {
            let dir = project.folderURL(folder)
            guard fm.fileExists(atPath: dir.path) else { continue }
            let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in contents { try? fm.removeItem(at: item) }
            removed.append(folder.folderName)
        }

        // 4. Удаляем ценные папки локально (они теперь в архиве), оставляем структуру.
        for folder in ProjectFolder.allCases where folder.isValuable {
            let dir = project.folderURL(folder)
            let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in contents { try? fm.removeItem(at: item) }
        }

        // 5. Пишем манифест.
        let manifest = ProjectManifest(
            projectName: project.name,
            year: project.year,
            month: project.month,
            archivedAt: Date(),
            archiveRelativePath: iCloudStore.relativeArchivePath(for: project),
            removedHeavyFolders: removed,
            archiveByteCount: size
        )
        try manifest.write(to: project.manifestURL)
    }

    // MARK: - Восстановление

    /// Восстановить проект из архива в iCloud. Возвращает URL проекта.
    @discardableResult
    static func restore(manifestURL: URL) throws -> URL {
        let fm = FileManager.default
        let projectURL = manifestURL.deletingLastPathComponent()

        let manifest: ProjectManifest
        do {
            manifest = try ProjectManifest.load(from: manifestURL)
        } catch {
            throw ArchiverError.manifestMissing
        }

        let archiveURL = try iCloudStore.resolveArchiveURL(relativePath: manifest.archiveRelativePath)
        try iCloudStore.ensureDownloaded(archiveURL)

        // Распаковываем поверх проекта — ценные папки и файлы вернутся на места.
        try ZipArchiver.unzip(archive: archiveURL, destination: projectURL)

        // Убираем манифест — проект снова «живой».
        try? fm.removeItem(at: manifestURL)

        return projectURL
    }
}

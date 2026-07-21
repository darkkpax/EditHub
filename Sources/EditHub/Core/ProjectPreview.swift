import SwiftUI
import QuickLookThumbnailing
import AVFoundation
import Observation

/// Generates a cover thumbnail for a project using QuickLook — Apple's own
/// preview engine (same one Finder uses). Footage is the primary source so the
/// project row resembles the media the editor is actually working with.
@MainActor
@Observable
final class ProjectThumbnailLoader {
    var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()
    @ObservationIgnored
    private var task: Task<Void, Never>?

    func load(for project: Project, size: CGFloat = 120) {
        if let pURL = project.url, let cached = Self.cache.object(forKey: pURL as NSURL) {
            image = cached
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            guard let asset = Self.firstVisualAsset(in: project) else { return }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let request = QLThumbnailGenerator.Request(
                fileAt: asset,
                size: CGSize(width: size, height: size),
                scale: scale,
                representationTypes: .all
            )
            let generator = QLThumbnailGenerator.shared
            let nsImage: NSImage? = await withCheckedContinuation { cont in
                generator.generateBestRepresentation(for: request) { rep, _ in
                    cont.resume(returning: rep?.nsImage)
                }
            }
            guard let nsImage, !Task.isCancelled, let pURL = project.url else { return }
            Self.cache.setObject(nsImage, forKey: pURL as NSURL)
            self?.image = nsImage
        }
    }

    /// Search visual folders for the first image/video file.
    static func firstVisualAsset(in project: Project) -> URL? {
        let order: [ProjectFolder] = [.footage, .readyVideo, .broll]
        let visualExts: Set<String> = [
            "mov", "mp4", "m4v", "avi", "mkv",
            "jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"
        ]
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        
        for folder in order {
            guard let dir = project.folderURL(folder) else { continue }
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let item as URL in enumerator {
                if visualExts.contains(item.pathExtension.lowercased()) {
                    let values = try? item.resourceValues(forKeys: Set(resourceKeys))
                    if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                        continue // Skip iCloud-offloaded files to avoid triggering full download
                    }
                    return item
                }
            }
        }
        return nil
    }
}

// MARK: - Project statistics

struct ProjectStats {
    var fileCount = 0
    var totalBytes: Int64 = 0
    var reclaimableBytes: Int64 = 0   // bytes in heavy folders (freed on archive)

    var totalSizeText: String { totalBytes.formatted(.byteCount(style: .file)) }
    var reclaimableText: String { reclaimableBytes.formatted(.byteCount(style: .file)) }

    static func compute(for project: Project) -> ProjectStats {
        var stats = ProjectStats()
        let fm = FileManager.default
        guard let projectURL = project.url,
              let enumerator = fm.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
        ) else { return stats }

        let heavyPaths = ProjectFolder.allCases.filter(\.isHeavy)
            .compactMap { project.folderURL($0)?.path }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            stats.fileCount += 1
            stats.totalBytes += Int64(size)
            if heavyPaths.contains(where: { url.path.hasPrefix($0) }) {
                stats.reclaimableBytes += Int64(size)
            }
        }
        return stats
    }
}

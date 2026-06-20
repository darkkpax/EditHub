import SwiftUI
import QuickLookThumbnailing
import AVFoundation
import Observation

/// Generates a cover thumbnail for a project using QuickLook — Apple's own
/// preview engine (same one Finder uses). Looks for the first visual asset
/// in READY VIDEO, then FOOTAGE, then B-ROLL.
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
        let order: [ProjectFolder] = [.readyVideo, .broll, .footage]
        let visualExts: Set<String> = [
            "mov", "mp4", "m4v", "avi", "mkv",
            "jpg", "jpeg", "png", "heic", "tiff", "gif", "webp"
        ]
        let fm = FileManager.default
        for folder in order {
            guard let dir = project.folderURL(folder) else { continue }
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            if let hit = items
                .filter({ visualExts.contains($0.pathExtension.lowercased()) })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first {
                return hit
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

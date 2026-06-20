import Foundation

/// Координирует восстановление проекта из манифеста `.edithub`
/// (например, при двойном клике в Finder). Запускает [[ProjectArchiver]]
/// в фоне и обновляет [[ProjectStore]].
@MainActor
final class RestoreCoordinator {
    static let shared = RestoreCoordinator()

    private init() {}

    func restore(manifestURL: URL, store: ProjectStore) async {
        let accessed = manifestURL.startAccessingSecurityScopedResource()
        defer { if accessed { manifestURL.stopAccessingSecurityScopedResource() } }

        guard let archiveRoot = iCloudStore.shared.rootURL else {
            NSLog("EditHub restore failed: iCloud archive root is not selected")
            return
        }

        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try ProjectArchiver.restore(manifestURL: manifestURL, archiveRoot: archiveRoot)
            }.value
            store.refresh()
        } catch {
            NSLog("EditHub restore failed: \(error.localizedDescription)")
        }
    }
}

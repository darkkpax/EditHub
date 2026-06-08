import Foundation

final class FolderBookmarkStore: ObservableObject {
    @Published private(set) var selectedURL: URL?
    @Published private(set) var displayPath: String = ""

    private let defaultsKey = "selectedRootFolderBookmark"
    private let pathDefaultsKey = "selectedRootFolderPath"
    private var hasScopedAccess = false

    init() {
        loadBookmark()
    }

    deinit {
        stopAccessingIfNeeded()
    }

    func setSelectedURL(_ url: URL) throws {
        stopAccessingIfNeeded()

        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
        UserDefaults.standard.set(url.path, forKey: pathDefaultsKey)

        selectedURL = url
        displayPath = url.path
        startAccessingIfPossible(url)
    }

    private func loadBookmark() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            displayPath = UserDefaults.standard.string(forKey: pathDefaultsKey) ?? ""
            return
        }

        do {
            var stale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            selectedURL = resolvedURL
            displayPath = resolvedURL.path
            startAccessingIfPossible(resolvedURL)

            if stale {
                try setSelectedURL(resolvedURL)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            selectedURL = nil
            displayPath = UserDefaults.standard.string(forKey: pathDefaultsKey) ?? ""
        }
    }

    private func startAccessingIfPossible(_ url: URL) {
        hasScopedAccess = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingIfNeeded() {
        guard hasScopedAccess, let url = selectedURL else { return }
        url.stopAccessingSecurityScopedResource()
        hasScopedAccess = false
    }
}

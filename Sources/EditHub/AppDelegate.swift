import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Очередь URL-ов манифестов, открытых до того как стор был готов.
    private var pendingRestoreURLs: [URL] = []
    private weak var store: ProjectStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Открытие .edithub файла из Finder (двойной клик).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleOpen(url, store: store) }
    }

    @MainActor
    func handleOpen(_ url: URL, store: ProjectStore?) {
        self.store = store
        guard url.pathExtension.lowercased() == "edithub" else { return }

        guard let store else {
            pendingRestoreURLs.append(url)
            return
        }

        Task { await RestoreCoordinator.shared.restore(manifestURL: url, store: store) }
    }
}

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Очередь URL-ов манифестов, открытых до того как стор был готов.
    private var pendingRestoreURLs: [URL] = []
    private weak var store: ProjectStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
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

    /// Called once the SwiftUI scene has the store. Drains any manifests that
    /// were opened from Finder before the store existed (cold start).
    @MainActor
    func attach(store: ProjectStore) {
        self.store = store
        guard !pendingRestoreURLs.isEmpty else { return }
        let queued = pendingRestoreURLs
        pendingRestoreURLs.removeAll()
        for url in queued {
            Task { await RestoreCoordinator.shared.restore(manifestURL: url, store: store) }
        }
    }

    @MainActor
    func handleOpen(_ url: URL, store: ProjectStore?) {
        // Remember the store the moment we get one, and flush anything that
        // arrived before it was ready (cold start: Finder opens a .edithub
        // before the WindowGroup has injected the store).
        if let store { self.store = store }

        guard url.pathExtension.lowercased() == "edithub" else { return }

        guard let activeStore = self.store else {
            pendingRestoreURLs.append(url)
            return
        }

        let queued = pendingRestoreURLs
        pendingRestoreURLs.removeAll()
        for pending in queued {
            Task { await RestoreCoordinator.shared.restore(manifestURL: pending, store: activeStore) }
        }
        Task { await RestoreCoordinator.shared.restore(manifestURL: url, store: activeStore) }
    }
}

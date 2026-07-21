import SwiftUI

@main
struct EditHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ProjectStore()
    private var auth = AuthStore.shared

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environment(store)
                .frame(minWidth: 880, minHeight: 560)
                .background(WindowChromeConfigurator())
                .onAppear {
                    appDelegate.attach(store: store)
                    if auth.isLoggedIn { store.syncWithServer() }
                }
                .onOpenURL { url in
                    appDelegate.handleOpen(url, store: store)
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        // window.toolbar = nil // Removed to restore hit-testing for custom titlebar buttons
        // Keep custom controls in the full-size title-bar region interactive.
        // The native title bar itself remains draggable.
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

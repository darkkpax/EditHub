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
                .background(MainWindowConfigurator())
                .onAppear {
                    appDelegate.attach(store: store)
                    if auth.isLoggedIn { store.syncWithServer() }
                }
                .onOpenURL { url in
                    appDelegate.handleOpen(url, store: store)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Raises the main window to the front once it attaches. SwiftUI handles sizing
/// and centering now that the window is resizable (`.contentMinSize` +
/// `.defaultPosition(.center)`), so this no longer fights the window frame.
private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.makeKeyAndOrderFront(nil) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

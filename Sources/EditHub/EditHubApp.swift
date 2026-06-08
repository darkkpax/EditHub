import SwiftUI

@main
struct EditHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environmentObject(store)
                .frame(minWidth: 880, minHeight: 560)
                .onOpenURL { url in
                    // Открытие файла-манифеста .edithub запускает восстановление.
                    appDelegate.handleOpen(url, store: store)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

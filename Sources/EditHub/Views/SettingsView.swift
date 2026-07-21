import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(ProjectStore.self) private var store
    @Bindable var downloadViewModel: DownloadViewModel

    @State private var iCloud = iCloudStore.shared
    @State private var auth = AuthStore.shared
    @ObservedObject private var googleDrive = GoogleDriveAuthController.shared
    @StateObject private var dropFXStore = FolderBookmarkStore(
        defaultsKey: "dropFXLibraryBookmark",
        pathDefaultsKey: "dropFXLibraryPath"
    )

    @AppStorage("davinciResolvePath") private var davinciPath = "/Applications/DaVinci Resolve/DaVinci Resolve.app"
    @AppStorage("premiereProPath") private var premierePath = "/Applications/Adobe Premiere Pro 2026/Adobe Premiere Pro 2026.app"
    @AppStorage("autoArchiveDays") private var autoArchiveDays = 30

    var body: some View {
        Form {
            Section("Storage") {
                FolderSettingRow(
                    title: "Projects folder",
                    systemImage: "folder",
                    path: store.rootDisplayPath,
                    action: chooseProjectsFolder
                )
                FolderSettingRow(
                    title: "iCloud Drive",
                    systemImage: "icloud",
                    path: iCloud.rootDisplayPath,
                    action: chooseICloudFolder
                )
                FolderSettingRow(
                    title: "Downloads folder",
                    systemImage: "arrow.down.circle",
                    path: downloadViewModel.destinationDisplayPath,
                    action: downloadViewModel.chooseDestinationFolder
                )
                FolderSettingRow(
                    title: "DropFX library (SFX)",
                    systemImage: "waveform",
                    path: dropFXStore.displayPath,
                    action: chooseDropFXFolder
                )
            }

            Section("Editors") {
                LabeledContent("DaVinci Resolve path") {
                    TextField("Application path", text: $davinciPath)
                        .frame(minWidth: 320)
                }
                LabeledContent("Adobe Premiere Pro path") {
                    TextField("Application path", text: $premierePath)
                        .frame(minWidth: 320)
                }
            }

            Section("Connections") {
                LabeledContent("Google Drive") {
                    HStack {
                        Label(
                            googleDrive.isAuthenticated ? "Connected" : "Not connected",
                            systemImage: googleDrive.isAuthenticated ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(googleDrive.isAuthenticated ? .green : .secondary)
                        Button(googleDrive.isAuthenticated ? "Disconnect" : "Connect") {
                            googleDrive.isAuthenticated ? googleDrive.signOut() : googleDrive.signIn()
                        }
                    }
                }

                LabeledContent("EditHub account") {
                    HStack {
                        Label(
                            auth.isLoggedIn ? (auth.userEmail ?? "Connected") : "Waiting for iCloud auth.json",
                            systemImage: auth.isLoggedIn ? "checkmark.circle.fill" : "icloud.slash"
                        )
                        .foregroundStyle(auth.isLoggedIn ? .green : .secondary)
                        Button("Reload from iCloud", action: reloadICloudSession)
                    }
                }
            }

            Section("Automation") {
                Stepper("Auto-offload after \(autoArchiveDays) days", value: $autoArchiveDays, in: 1...365)
                Text("Offloaded projects keep valuable folders in iCloud and can be restored later.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func chooseProjectsFolder() {
        chooseFolder(current: store.rootURL) { try store.setRoot($0) }
    }

    private func chooseICloudFolder() {
        chooseFolder(current: iCloud.rootURL) {
            try iCloud.setRoot($0)
            reloadICloudSession()
        }
    }

    private func chooseDropFXFolder() {
        chooseFolder(current: dropFXStore.selectedURL) { try dropFXStore.setSelectedURL($0) }
    }

    private func chooseFolder(current: URL?, action: (URL) throws -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = current
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? action(url)
    }

    private func reloadICloudSession() {
        guard let root = iCloud.rootURL else { return }
        auth.importSharedSession(from: root)
        if auth.isLoggedIn { store.syncWithServer() }
    }
}

private struct FolderSettingRow: View {
    let title: String
    let systemImage: String
    let path: String
    let action: () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                Text(path.isEmpty ? "Not selected" : path)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 300, alignment: .trailing)
                Button("Choose…", action: action)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

import SwiftUI

struct RootSplitView: View {
    @Environment(ProjectStore.self) private var store

    @State private var selectedProject: Project?
    @State private var downloadViewModel = DownloadViewModel()
    @State private var showCreatePopover = false
    @State private var iCloud = iCloudStore.shared
    @State private var isImporting = false
    @State private var importAlert: ImportAlert?
    @Namespace private var createMorphNamespace

    struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            projectsLayout
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showCreatePopover {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { dismissCreate() }
                    .zIndex(20)
            }

            createProjectSurface
                .padding(.trailing, 22)
                .padding(.bottom, 22)
                .zIndex(30)
        }
        .background(WindowBackdrop())
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func dismissCreate() {
        withAnimation(SoftIOSMotion.morph) {
            showCreatePopover = false
        }
    }

    private var createProjectSurface: some View {
        ZStack(alignment: .bottomTrailing) {
            GlassEffectContainer(spacing: 28) {
                VStack(alignment: .trailing, spacing: 12) {
                    if showCreatePopover {
                        CreateAndDownloadPopover(
                            downloadViewModel: downloadViewModel,
                            onCreated: { project in
                                withAnimation(SoftIOSMotion.entry) {
                                    store.refresh()
                                    selectedProject = project
                                }
                            },
                            onDismiss: dismissCreate,
                            morphNamespace: createMorphNamespace
                        )
                        .frame(width: 390)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.86, anchor: .bottomTrailing)
                                    .combined(with: .opacity),
                                removal: .scale(scale: 0.92, anchor: .bottomTrailing)
                                    .combined(with: .opacity)
                            )
                        )
                    }

                    Button {
                        withAnimation(SoftIOSMotion.morph) {
                            showCreatePopover.toggle()
                        }
                    } label: {
                        ZStack {
                            if showCreatePopover {
                                Circle()
                                    .fill(Theme.accent)
                                    .glassEffect(
                                        .regular.tint(Theme.accent.opacity(0.95)).interactive(),
                                        in: .circle
                                    )
                            } else {
                                Circle()
                                    .fill(Theme.accent)
                                    .glassEffect(
                                        .regular.tint(Theme.accent.opacity(0.95)).interactive(),
                                        in: .circle
                                    )
                            }

                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(Color.white)
                                .rotationEffect(.degrees(showCreatePopover ? 45 : 0))
                                .zIndex(2)
                        }
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                        .shadow(color: Theme.accent.opacity(0.32), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help(showCreatePopover ? "Close" : "New project")
                }
            }
            .zIndex(1)
        }
    }

    private var importAction: (() -> Void)? {
        guard iCloud.isAvailable, store.rootURL != nil else { return nil }
        return importArchives
    }

    private var projectsLayout: some View {
        HSplitView {
            ProjectListView(
                selectedProject: $selectedProject,
                downloadViewModel: downloadViewModel,
                onChooseRoot: chooseRoot,
                rootStatusIcon: rootStatusIcon,
                rootStatusColor: rootStatusColor,
                onChooseICloud: chooseICloud,
                iCloudStatusIcon: iCloud.isAvailable ? "icloud.fill" : "icloud",
                iCloudStatusColor: iCloud.isAvailable ? .green : .secondary,
                onImportArchives: importAction,
                isImporting: isImporting
            )
            .ignoresSafeArea()
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)

            Group {
                if let project = selectedProject {
                    ProjectDetailView(project: project, downloadViewModel: downloadViewModel)
                        .id(project.id)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 380, maxWidth: .infinity)
        }
    }

    // MARK: - Root status

    private var rootStatusIcon: String {
        if store.rootURL == nil { return "questionmark.folder" }
        return store.hasYearFolders ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var rootStatusColor: Color {
        if store.rootURL == nil { return .secondary }
        return store.hasYearFolders ? .green : .orange
    }

    // MARK: - Actions

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select the folder that contains your year folders."
        panel.directoryURL = store.rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.setRoot(url)
    }

    private func importArchives() {
        guard let iCloudRoot = iCloud.rootURL, let projectsRoot = store.rootURL else { return }
        isImporting = true
        Task.detached(priority: .userInitiated) {
            let result = try? ICloudArchiveImporter.import(from: iCloudRoot, into: projectsRoot)
            await MainActor.run {
                isImporting = false
                store.refresh()
                let r = result ?? ICloudArchiveImporter.ImportResult()
                importAlert = ImportAlert(
                    title: r.imported > 0 ? "Import complete" : "Nothing new",
                    message: r.errors.isEmpty
                        ? r.summary
                        : r.summary + "\n\nErrors:\n" + r.errors.prefix(5).joined(separator: "\n")
                )
            }
        }
    }

    private func chooseICloud() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a folder inside iCloud Drive for project archives (e.g. iCloud Drive/EditHub)."
        panel.directoryURL = iCloud.rootURL ?? FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try iCloud.setRoot(url)
            if AuthStore.shared.isLoggedIn { store.syncWithServer() }
        } catch {}
    }
}


// MARK: - Empty detail

struct EmptyDetail: View {
    var icon: String = "square.dashed"
    var title: String = ""
    let message: String

    init(text: String) {
        self.message = text
    }

    init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    var body: some View {
        ContentUnavailableView {
            Label(title.isEmpty ? "Nothing Here" : title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}

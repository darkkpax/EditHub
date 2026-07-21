import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case projects
    case settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String { self == .projects ? "folder" : "gearshape" }
}

struct AppSectionControl: View {
    @Binding var selection: AppSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                let isSelected = selection == section
                Button {
                    selection = section
                } label: {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .tactileSymbol()
                        .frame(width: 34, height: 28)
                        .background(isSelected ? Color.primary.opacity(0.08) : .clear, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .help(section.title)
            }
        }
        .padding(2)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct RootSplitView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var section: AppSection = .projects
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedProject: Project?
    @State private var downloadViewModel = DownloadViewModel()
    @State private var showCreateProject = false
    @State private var iCloud = iCloudStore.shared
    @State private var isImporting = false
    @State private var importAlert: ImportAlert?
    @Namespace private var createNamespace

    struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            projectsView

            if section == .projects {
                if showCreateProject {
                    Button(action: dismissCreate) { Color.clear }
                        .buttonStyle(.plain)
                        .ignoresSafeArea()
                }

                VStack(alignment: .trailing, spacing: 4) {
                    if showCreateProject {
                        CreateAndDownloadPopover(
                            downloadViewModel: downloadViewModel,
                            onCreated: { project in
                                store.refresh()
                                selectedProject = project
                            },
                            onDismiss: dismissCreate,
                            morphNamespace: createNamespace
                        )
                        .frame(width: 320)
                        // Grow out of / collapse back into the plus button.
                        .transition(
                            .scale(scale: 0.05, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                        )
                    }

                    createProjectButton(glassID: "create")
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(reduceMotion ? .none : Motion.state, value: section)
        .task {
            if iCloud.isAvailable, store.rootURL != nil {
                importArchives(showResult: false)
            }
        }
        .alert(item: $importAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var projectsView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectListView(
                section: $section,
                selectedProject: $selectedProject,
                downloadViewModel: downloadViewModel,
                onChooseRoot: chooseRoot,
                rootStatusIcon: rootStatusIcon,
                rootStatusColor: rootStatusColor,
                onChooseICloud: chooseICloud,
                iCloudStatusIcon: iCloud.isAvailable ? "icloud.fill" : "icloud",
                iCloudStatusColor: iCloud.isAvailable ? .green : .secondary,
                onImportArchives: importAction,
                isImporting: isImporting,
                onToggleSidebar: toggleSidebar
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 300)
        } detail: {
            if section == .settings {
                SettingsView(downloadViewModel: downloadViewModel)
                    .transition(.opacity)
            } else if let project = selectedProject {
                ProjectDetailView(project: project, downloadViewModel: downloadViewModel)
                    .id(project.id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "folder",
                    description: Text("Choose a project in the sidebar or create a new one.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .animation(reduceMotion ? .none : Motion.reveal, value: selectedProject?.id)
        .animation(reduceMotion ? .none : Motion.state, value: section)
    }

    private func dismissCreate() {
        withAnimation(reduceMotion ? .none : Motion.morph) {
            showCreateProject = false
        }
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? .none : Motion.state) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func createProjectButton(glassID: String) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : Motion.morph) {
                showCreateProject.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .tactileSymbol()
                .rotationEffect(.degrees(showCreateProject ? 45 : 0))
                .frame(width: 50, height: 50)
                .contentShape(.circle)
                .glassEffect(
                    .regular.tint(Theme.accent).interactive(),
                    in: .circle
                )
                .glassEffectID(glassID, in: createNamespace)
                .glassEffectTransition(.matchedGeometry)
        }
        .buttonStyle(.plain)
        .shadow(color: Theme.accent.opacity(0.3), radius: 15, y: 7)
        .help(showCreateProject ? "Close" : "New project")
    }

    private var rootStatusIcon: String {
        guard store.rootURL != nil else { return "questionmark.folder" }
        return store.hasYearFolders ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var rootStatusColor: Color {
        guard store.rootURL != nil else { return .secondary }
        return store.hasYearFolders ? .green : .orange
    }

    private var importAction: (() -> Void)? {
        guard iCloud.isAvailable, store.rootURL != nil else { return nil }
        return { importArchives() }
    }

    private func chooseRoot() {
        chooseFolder(
            message: "Select the folder that contains your year folders.",
            directoryURL: store.rootURL
        ) { try store.setRoot($0) }
    }

    private func chooseICloud() {
        chooseFolder(
            message: "Select iCloud Drive or its EditHub folder. EditHub will read EditHub/auth.json automatically.",
            directoryURL: iCloud.rootURL
        ) {
            try iCloud.setRoot($0)
            if store.rootURL != nil { importArchives(showResult: false) }
        }
    }

    private func chooseFolder(
        message: String,
        directoryURL: URL?,
        action: (URL) throws -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = message
        panel.directoryURL = directoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try action(url) } catch {
            importAlert = ImportAlert(title: "Folder Error", message: error.localizedDescription)
        }
    }

    private func importArchives(showResult: Bool = true) {
        guard let iCloudRoot = iCloud.rootURL, let projectsRoot = store.rootURL else { return }
        isImporting = true
        Task.detached(priority: .userInitiated) {
            let result = try? ICloudArchiveImporter.import(from: iCloudRoot, into: projectsRoot)
            await MainActor.run {
                isImporting = false
                store.refresh()
                let result = result ?? ICloudArchiveImporter.ImportResult()
                if showResult {
                    importAlert = ImportAlert(
                        title: result.imported > 0 ? "Import Complete" : "Nothing New",
                        message: result.errors.isEmpty
                            ? result.summary
                            : result.summary + "\n\n" + result.errors.prefix(5).joined(separator: "\n")
                    )
                }
            }
        }
    }
}

struct EmptyDetail: View {
    var icon = "square.dashed"
    var title = ""
    let message: String

    init(text: String) { message = text }

    init(icon: String, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    var body: some View {
        ContentUnavailableView(
            title.isEmpty ? "Nothing Here" : title,
            systemImage: icon,
            description: Text(message)
        )
    }
}

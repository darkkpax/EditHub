import SwiftUI

/// Главное окно: сайдбар (разделы) → список проектов → деталь.
struct RootSplitView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var section: AppSection = .projects
    @State private var selectedProject: Project?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            detailColumn
        }
        .frame(minWidth: 880, minHeight: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("EDITHUB") {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            rootFolderFooter
        }
    }

    private var rootFolderFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(store.rootDisplayPath.isEmpty ? "КОРЕНЬ НЕ ВЫБРАН" : store.rootDisplayPath)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("ВЫБРАТЬ КОРЕНЬ ПРОЕКТОВ") { chooseRoot() }
                .font(.system(size: 9, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .projects:
            ProjectListView(selectedProject: $selectedProject, archivedOnly: false)
        case .archive:
            ProjectListView(selectedProject: $selectedProject, archivedOnly: true)
        case .create:
            CreateProjectView(selectedProject: $selectedProject, switchToProjects: { section = .projects })
        case .download:
            DownloadView(targetProject: selectedProject)
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if section == .create {
            EmptyDetail(text: "Заполни форму слева и создай новый проект.")
        } else if section == .download {
            EmptyDetail(text: "Вставь ссылку Google Drive или Dropbox.")
        } else if let project = selectedProject {
            ProjectDetailView(project: project)
        } else {
            EmptyDetail(text: "Выбери проект, чтобы увидеть структуру папок и действия.")
        }
    }

    // MARK: - Actions

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "ВЫБРАТЬ"
        panel.directoryURL = store.rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.setRoot(url)
    }
}

struct EmptyDetail: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

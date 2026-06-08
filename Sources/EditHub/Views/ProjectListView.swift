import SwiftUI
import UniformTypeIdentifiers

/// Список проектов, сгруппированный по году/месяцу. Поддерживает поиск
/// и drag-and-drop файлов прямо на строку проекта для авто-раскладки.
struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var selectedProject: Project?
    let archivedOnly: Bool

    @State private var search = ""
    @State private var dropTargetID: Project.ID?
    @State private var lastSummary: SortSummary?

    private var groups: [(key: String, projects: [Project])] {
        store.grouped.compactMap { group in
            let filtered = group.projects.filter { project in
                (!archivedOnly || project.isArchived)
                    && (search.isEmpty || project.name.localizedCaseInsensitiveContains(search))
            }
            return filtered.isEmpty ? nil : (key: group.key, projects: filtered)
        }
    }

    var body: some View {
        Group {
            if store.rootURL == nil {
                EmptyDetail(text: "Сначала выбери корневую папку проектов в сайдбаре снизу.")
            } else if groups.isEmpty {
                EmptyDetail(text: archivedOnly ? "Законсервированных проектов пока нет." : "Проектов не найдено.")
            } else {
                list
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Поиск проекта")
        .navigationTitle(archivedOnly ? "Архив" : "Проекты")
        .overlay(alignment: .bottom) { summaryToast }
    }

    private var list: some View {
        List(selection: $selectedProject) {
            ForEach(groups, id: \.key) { group in
                Section(group.key.uppercased()) {
                    ForEach(group.projects) { project in
                        ProjectRow(project: project, isDropTarget: dropTargetID == project.id)
                            .tag(project)
                            .onDrop(
                                of: [UTType.fileURL],
                                isTargeted: targetBinding(for: project)
                            ) { providers in
                                handleDrop(providers, into: project)
                            }
                    }
                }
            }
        }
    }

    private func targetBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { dropTargetID == project.id },
            set: { dropTargetID = $0 ? project.id : nil }
        )
    }

    @ViewBuilder
    private var summaryToast: some View {
        if let summary = lastSummary, !summary.isEmpty {
            Text(summary.caption)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider], into project: Project) -> Bool {
        guard !project.isArchived else { return false }
        DropURLLoader.load(providers) { urls in
            guard !urls.isEmpty else { return }
            let summary = FileSorter.sort(fileURLs: urls, into: project)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                lastSummary = summary
                selectedProject = project
            }
            store.refresh()
            hideToastAfterDelay()
        }
        return true
    }

    private func hideToastAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { lastSummary = nil }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let isDropTarget: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.isArchived ? "archivebox.fill" : "folder.fill")
                .foregroundStyle(project.isArchived ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if project.isArchived {
                    Text("ЗАКОНСЕРВИРОВАН")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, lineWidth: isDropTarget ? 2 : 0)
                .padding(.vertical, -2)
        )
    }
}

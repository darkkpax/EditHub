import SwiftUI
import UniformTypeIdentifiers

/// Деталь проекта: дерево папок + действия (открыть, скачать, законсервировать).
/// Большая drop-зона для сортировки файлов.
struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project

    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastSummary: SortSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            FolderTreeView(rootURL: project.url)
                .id(project.id)
        }
        .overlay(dropOverlay)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: project.isArchived ? "archivebox.fill" : "folder.fill")
                    .foregroundStyle(project.isArchived ? Color.orange : Color.accentColor)
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold))
                if project.isArchived {
                    Text("ЗАКОНСЕРВИРОВАН")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Text("\(project.year) · \(project.month)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NSWorkspace.shared.open(project.url)
            } label: { Label("Открыть в Finder", systemImage: "arrow.up.forward.app") }

            if project.isArchived {
                Button {
                    runRestore()
                } label: { Label("Восстановить", systemImage: "arrow.down.circle") }
                .disabled(isWorking)
            } else {
                Button {
                    runArchive()
                } label: { Label("Законсервировать", systemImage: "archivebox") }
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Drop overlay

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted && !project.isArchived {
            ZStack {
                Color.accentColor.opacity(0.08)
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 34, weight: .light))
                    Text("ОТПУСТИ — РАЗЛОЖУ ПО ПАПКАМ")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
            )
            .allowsHitTesting(false)
        } else if let summary = lastSummary, !summary.isEmpty {
            VStack {
                Spacer()
                Text(summary.caption)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !project.isArchived else { return false }
        DropURLLoader.load(providers) { urls in
            guard !urls.isEmpty else { return }
            let summary = FileSorter.sort(fileURLs: urls, into: project)
            withAnimation { lastSummary = summary }
            store.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { lastSummary = nil }
            }
        }
        return true
    }

    private func runArchive() {
        isWorking = true
        message = "Консервирую в iCloud…"
        isError = false
        let project = project
        Task.detached(priority: .userInitiated) {
            do {
                try ProjectArchiver.archive(project)
                await finish(success: "Готово. FOOTAGE удалён, ценное в iCloud.")
            } catch {
                await finish(error: error.localizedDescription)
            }
        }
    }

    private func runRestore() {
        isWorking = true
        message = "Восстанавливаю из iCloud…"
        isError = false
        let manifest = project.manifestURL
        Task.detached(priority: .userInitiated) {
            do {
                try ProjectArchiver.restore(manifestURL: manifest)
                await finish(success: "Восстановлено. Осталось дозалить FOOTAGE.")
            } catch {
                await finish(error: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func finish(success: String? = nil, error: String? = nil) {
        isWorking = false
        message = success ?? error
        isError = (error != nil)
        store.refresh()
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var section: AppSection
    @Binding var selectedProject: Project?
    var downloadViewModel: DownloadViewModel?
    var externalSearch: String = ""
    var onChooseRoot: (() -> Void)?
    var rootStatusIcon: String = "folder"
    var rootStatusColor: Color = .secondary
    var onChooseICloud: (() -> Void)?
    var iCloudStatusIcon: String = "icloud"
    var iCloudStatusColor: Color = .secondary
    var onImportArchives: (() -> Void)?
    var isImporting: Bool = false
    var onToggleSidebar: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""
    @State private var dropTargetID: Project.ID?
    @State private var lastSummary: SortSummary?
    @State private var showAccountPopover = false
    @State private var auth = AuthStore.shared

    // Multi-select
    @State private var selectedIDs: Set<Project.ID> = []
    @State private var isSelecting = false
    @State private var showMultiArchiveSheet = false
    @State private var showDeleteConfirm = false

    private var effectiveSearch: String {
        externalSearch.isEmpty ? searchText : externalSearch
    }

    /// Every animation in this view routes through here so Reduce Motion is
    /// honoured in one place rather than at each of the ~20 call sites.
    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    private var groups: [(key: String, projects: [Project])] {
        store.grouped.compactMap { group in
            let filtered = group.projects.filter { project in
                effectiveSearch.isEmpty || project.name.localizedCaseInsensitiveContains(effectiveSearch)
            }
            return filtered.isEmpty ? nil : (key: group.key, projects: filtered)
        }
    }

    private var selectedProjects: [Project] {
        store.projects.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The window uses `.fullSizeContentView`, so the title bar overlaps
            // this view. Subtract whatever the safe area already reserves —
            // the detail pane derives its header the same way, which is what
            // keeps the two columns' chrome on a single baseline.
            GeometryReader { geometry in
                sidebarHeader(topInset: max(0, Theme.headerTopInset - geometry.safeAreaInsets.top))
            }
            .frame(height: Theme.headerHeight)

            if isSelecting && !selectedIDs.isEmpty {
                selectionToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            content
        }
        .background(DefaultLiquidGlassBackground())
        .overlay(alignment: .bottom) { summaryToast }
        .animation(motion(Motion.standard), value: lastSummary?.caption)
        .animation(motion(SoftIOSMotion.state), value: isSelecting)
        .animation(motion(SoftIOSMotion.state), value: selectedIDs.isEmpty)
        .sheet(isPresented: $showMultiArchiveSheet) {
            MultiArchiveSheet(projects: selectedProjects) { foldersToRemove in
                showMultiArchiveSheet = false
                performMultiArchive(foldersToRemove: foldersToRemove)
            } onCancel: {
                showMultiArchiveSheet = false
            }
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) project\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performMultiDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the selected project folders from disk.")
        }
    }

    // MARK: - Sidebar Header

    private func sidebarHeader(topInset: CGFloat) -> some View {
        VStack(spacing: Theme.controlSpacing) {
            HStack(spacing: Theme.controlSpacing) {
                // Traffic lights own the left of the title bar; the section
                // control sits to their right, trailing-aligned.
                Spacer(minLength: 72)

                AppSectionControl(selection: $section)
            }
            .frame(height: Theme.controlHeight)
            .padding(.horizontal, Theme.headerHorizontalPadding)

            searchBar
                .padding(.horizontal, Theme.headerHorizontalPadding)
                .padding(.bottom, Theme.headerTopInset)
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            // The panel behind this already lays down `.ultraThinMaterial`;
            // stacking a second translucent layer on top of it is what Apple
            // warns against — legibility drops and the blur reads muddy. Use a
            // thin opaque scrim instead, which still separates the header from
            // the scrolling list underneath.
            Rectangle()
                .fill(.background.secondary)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search projects", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: Theme.controlHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Selection toolbar

    private var selectionToolbar: some View {
        HStack(spacing: 0) {
            // Counter
            HStack(spacing: 6) {
                Button {
                    withAnimation(motion(SoftIOSMotion.state)) {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .tactileSymbol()
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Exit selection")
                .accessibilityLabel("Exit selection")

                Text(selectedIDs.isEmpty ? "Select items" : "\(selectedIDs.count) selected")
                    .font(.callout.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(motion(SoftIOSMotion.text), value: selectedIDs.count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !selectedIDs.isEmpty {
                HStack(spacing: 6) {
                    // Archive button (only non-archived)
                    let archivable = selectedProjects.filter { !$0.isArchived && !$0.isRemoteOnly }
                    if !archivable.isEmpty {
                        Button {
                            showMultiArchiveSheet = true
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }

                    // Delete button
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassEffect(.regular.tint(Color.red.opacity(0.12)).interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.rootURL == nil {
            EmptyDetail(
                icon: "folder.badge.questionmark",
                title: "No Library",
                message: "Choose a projects root folder using the button in the bottom-left."
            )
        } else if !store.hasYearFolders {
            wrongRootDetail
        } else if groups.isEmpty {
            EmptyDetail(
                icon: effectiveSearch.isEmpty ? "tray" : "magnifyingglass",
                title: effectiveSearch.isEmpty ? "No Projects" : "No Results",
                message: effectiveSearch.isEmpty
                    ? "Create your first project to get started."
                    : "No projects match \"\(effectiveSearch)\"."
            )
        } else {
            list
        }
    }

    private var wrongRootDetail: some View {
        ContentUnavailableView {
            Label("No Year Folders", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text("EditHub expects a Year / Month / Project structure. The selected folder doesn't contain year folders.")
        } actions: {
            if let suggested = store.suggestedRoot {
                Button {
                    try? store.setRoot(suggested)
                } label: {
                    Label("Open \"\(suggested.lastPathComponent)\"", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.projects) { project in
                        ProjectRow(
                            project: project,
                            isDropTarget: dropTargetID == project.id,
                            download: downloadInfo(for: project),
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(project.id)
                        )
                        .tag(project.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                withAnimation(motion(SoftIOSMotion.bouncySlide)) {
                                    if selectedIDs.contains(project.id) {
                                        selectedIDs.remove(project.id)
                                    } else {
                                        selectedIDs.insert(project.id)
                                    }
                                }
                            } else {
                                withAnimation(motion(SoftIOSMotion.state)) {
                                    selectedProject = project
                                }
                            }
                        }
                        .listRowBackground(
                            selectedIDs.contains(project.id)
                                ? Theme.accent.opacity(0.12)
                                : Color.clear
                        )
                        .contextMenu {
                            projectContextMenu(project)
                        }
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
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .contentMargins(.bottom, 92, for: .scrollContent)
        .animation(motion(SoftIOSMotion.entry), value: store.projects.count)
        .animation(motion(SoftIOSMotion.bouncySlide), value: selectedIDs)
    }

    // MARK: - Helpers

    private func downloadInfo(for project: Project) -> RowDownload? {
        guard let vm = downloadViewModel,
              vm.isLoading,
              let active = vm.activeDownloadProjectURL,
              let pURL = project.url,
              active.standardizedFileURL == pURL.standardizedFileURL
        else { return nil }
        return RowDownload(
            fraction: vm.progressFraction,
            fileName: vm.progressCaption,
            isPaused: vm.isPaused,
            speedText: vm.downloadSpeedText,
            downloadedText: vm.downloadedSizeText,
            totalText: vm.totalSizeText,
            remainingText: vm.remainingTimeText,
            queuedCount: vm.queue.count
        )
    }

    private func targetBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { dropTargetID == project.id },
            set: { dropTargetID = $0 ? project.id : nil }
        )
    }

    // MARK: - Multi-select actions

    private func performMultiDelete() {
        let toDelete = selectedProjects
        withAnimation(motion(SoftIOSMotion.state)) {
            selectedIDs.removeAll()
            isSelecting = false
            if let sel = selectedProject, toDelete.contains(where: { $0.id == sel.id }) {
                selectedProject = nil
            }
        }
        Task.detached(priority: .userInitiated) {
            for project in toDelete {
                guard let url = project.url else { continue }
                try? FileManager.default.removeItem(at: url)
            }
            await MainActor.run { store.refresh() }
        }
    }

    private func performMultiArchive(foldersToRemove: Set<ProjectFolder>) {
        let toArchive = selectedProjects.filter { !$0.isArchived && !$0.isRemoteOnly }
        withAnimation(motion(SoftIOSMotion.state)) {
            selectedIDs.removeAll()
            isSelecting = false
        }
        Task.detached(priority: .userInitiated) {
            for project in toArchive {
                guard let destURL = try? await MainActor.run(body: {
                    try iCloudStore.shared.archiveURL(for: project)
                }) else { continue }
                try? ProjectArchiver.archive(project, destinationURL: destURL, foldersToRemove: foldersToRemove)
            }
            await MainActor.run { store.refresh() }
        }
    }

    // MARK: - Summary toast

    @ViewBuilder
    private var summaryToast: some View {
        if let summary = lastSummary, !summary.isEmpty {
            Label(summary.caption, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(Theme.accent.opacity(0.85)), in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        // The only entry point into multi-select now that the search field is
        // a plain search field again.
        Button {
            withAnimation(motion(SoftIOSMotion.state)) {
                isSelecting = true
                selectedIDs.insert(project.id)
            }
        } label: {
            Label("Select Multiple", systemImage: "checkmark.circle")
        }

        Divider()

        if !project.isRemoteOnly {
            Button {
                withAnimation(motion(SoftIOSMotion.state)) { selectedProject = project }
                if let u = project.url { NSWorkspace.shared.open(u) }
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }
        }

        Divider()

        if project.isArchived || project.isRemoteOnly {
            Button {
                withAnimation(motion(SoftIOSMotion.state)) { selectedProject = project }
            } label: {
                Label("Restore from iCloud", systemImage: "arrow.down.circle")
            }
        } else {
            Button {
                withAnimation(motion(SoftIOSMotion.state)) { selectedProject = project }
                // открываем sheet архивации через selectedProject — detail view покажет его
            } label: {
                Label("Archive to iCloud", systemImage: "archivebox")
            }
        }

        Divider()

        Button(role: .destructive) {
            guard let url = project.url else { return }
            Task.detached {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { store.refresh() }
            }
        } label: {
            Label("Delete Project", systemImage: "trash")
        }
        .disabled(project.isRemoteOnly)
    }

    // MARK: - Account popover

    @ViewBuilder
    private var accountPopover: some View {
        if auth.isLoggedIn {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text(auth.userEmail ?? "Signed in")
                    .font(.subheadline.weight(.medium))
                Button {
                    showAccountPopover = false
                    Task {
                        try? await NetworkClient.shared.logout()
                        AuthStore.shared.logout()
                    }
                } label: {
                    Text("Sign out")
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
            .padding(20)
            .frame(width: 220)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Not signed in")
                    .font(.headline)
                Text("Please connect your iCloud account in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(width: 220)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider], into project: Project) -> Bool {
        guard !project.isArchived else { return false }
        DropURLLoader.load(providers) { urls in
            guard !urls.isEmpty else { return }
            let summary = FileSorter.sort(fileURLs: urls, into: project)
            withAnimation(motion(Motion.standard)) {
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

// MARK: - Multi-archive sheet

private struct MultiArchiveSheet: View {
    let projects: [Project]
    let onArchive: (Set<ProjectFolder>) -> Void
    let onCancel: () -> Void

    @State private var toRemove: Set<ProjectFolder> = []

    private var archivable: [Project] { projects.filter { !$0.isArchived && !$0.isRemoteOnly } }
    private var heavyFolders: [ProjectFolder] { ProjectFolder.removableOnArchive }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text("Archive \(archivable.count) project\(archivable.count == 1 ? "" : "s")")
                        .font(.title3.weight(.semibold))
                }
                Text("Valuable folders go to iCloud. Choose which heavy folders to delete locally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Project list
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(archivable) { p in
                            Text(p.name)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            // Folder toggles
            VStack(spacing: 0) {
                ForEach(heavyFolders) { folder in
                    Toggle(isOn: Binding(
                        get: { toRemove.contains(folder) },
                        set: { on in if on { toRemove.insert(folder) } else { toRemove.remove(folder) } }
                    )) {
                        HStack(spacing: 9) {
                            Image(systemName: folder.systemImage)
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(folder.folderName)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    if folder != heavyFolders.last {
                        Divider().padding(.leading, 49)
                    }
                }
            }
            .padding(.vertical, 6)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Archive All") { onArchive(toRemove) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
            .padding(20)
        }
        .frame(width: 440)
        .onAppear {
            toRemove = Set(heavyFolders)
        }
    }
}

// MARK: - Project row

struct RowDownload {
    let fraction: Double
    /// Name of the file currently transferring. Shown only in the hover
    /// popover — the row itself stays on the percentage.
    let fileName: String
    let isPaused: Bool
    let speedText: String
    let downloadedText: String
    let totalText: String
    let remainingText: String
    let queuedCount: Int

    var percentText: String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }
}

/// Detailed transfer readout shown when the pointer rests on a downloading row.
/// The row stays quiet (a bar and a percentage); everything else lives here.
private struct DownloadDetailPopover: View {
    let download: RowDownload
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(download.fileName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(value: download.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    detail("Progress", download.percentText)
                    detail("Speed", download.isPaused ? "Paused" : download.speedText)
                }
                GridRow {
                    detail("Downloaded", "\(download.downloadedText) / \(download.totalText)")
                    detail("Remaining", download.isPaused ? "--" : download.remainingText)
                }
                if download.queuedCount > 0 {
                    GridRow {
                        detail("In queue", "\(download.queuedCount) more")
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 288)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .contentTransition(.numericText())
        }
        .gridColumnAlignment(.leading)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isDropTarget: Bool
    var download: RowDownload?
    var isSelecting: Bool = false
    var isSelected: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumb = ProjectThumbnailLoader()
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showDownloadDetail = false
    @State private var hoverDetailTask: Task<Void, Never>?

    private var accent: Color { project.isArchived ? .orange : Theme.accent }

    var body: some View {
        HStack(spacing: 11) {
            // Selection checkbox
            if isSelecting {
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.accent : Color.clear)
                        .frame(width: 22, height: 22)
                    Circle()
                        .strokeBorder(isSelected ? Theme.accent : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(isSelected ? 1.08 : 1)
                .animation(reduceMotion ? nil : SoftIOSMotion.bouncySlide, value: isSelected)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            cover
                .scaleEffect(isSelected ? 0.92 : 1)
                .animation(reduceMotion ? nil : SoftIOSMotion.bouncySlide, value: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let download {
                    downloadProgress(download)
                } else {
                    HStack(spacing: 6) {
                        Text("\(project.year) · \(project.month)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if project.isArchived {
                            Text("Archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.16), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : Motion.standard, value: download != nil)
        .animation(reduceMotion ? nil : SoftIOSMotion.state, value: isSelecting)
        .scaleEffect(isPressed ? 0.97 : 1)
        .onHover { hovering in
            isHovered = hovering
            // Only a downloading row has anything extra to show, and a short
            // delay keeps the popover from flashing as the pointer crosses the
            // list on its way somewhere else.
            guard download != nil else {
                showDownloadDetail = false
                return
            }
            hoverDetailTask?.cancel()
            guard hovering else {
                showDownloadDetail = false
                return
            }
            hoverDetailTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                showDownloadDetail = true
            }
        }
        .onDisappear { hoverDetailTask?.cancel() }
        .popover(isPresented: $showDownloadDetail, arrowEdge: .trailing) {
            if let download {
                DownloadDetailPopover(download: download, projectName: project.name)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .padding(-4)
            }
        }
        .onAppear { thumb.load(for: project) }
    }

    /// The row deliberately shows only a bar and a percentage: filenames are
    /// long, change constantly, and made the list jitter. The full readout is
    /// one hover away in `DownloadDetailPopover`.
    private func downloadProgress(_ download: RowDownload) -> some View {
        HStack(spacing: 7) {
            ProgressView(value: download.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(maxWidth: 130)

            Text(download.isPaused ? "Paused" : download.percentText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : SoftIOSMotion.text, value: download.fraction)
        }
        .padding(.top, 1)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .fill(accent.opacity(0.15))
            if let image = thumb.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: project.isArchived ? "archivebox.fill" : "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, value: isSelected)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}

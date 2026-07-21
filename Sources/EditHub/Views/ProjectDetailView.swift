import SwiftUI
import UniformTypeIdentifiers

/// Project detail: a floating glass header over the folder tree.
/// Dropping files anywhere sorts them into the right folders.
struct ProjectDetailView: View {
    @Environment(ProjectStore.self) private var store
    let project: Project
    var downloadViewModel: DownloadViewModel?

    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false
    @State private var isDropTargeted = false
    @State private var lastSummary: SortSummary?
    @State private var showArchiveSheet = false
    @State private var showAddFootageSheet = false
    @State private var stats: ProjectStats?
    @State private var footageLink = ""
    @State private var hasSavedFootageLink = false
    @State private var showDeleteConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { project.isArchived ? .orange : Theme.accent }
    private let headerHeight: CGFloat = Theme.headerHeight

    var body: some View {
        GeometryReader { geometry in
            let contentHeaderInset = max(0, headerHeight - geometry.safeAreaInsets.top)

            ZStack(alignment: .top) {
                if let cloudDirectoryURL {
                    FolderTreeView(rootURL: cloudDirectoryURL, topContentInset: contentHeaderInset)
                        .id("cloud-\(project.id)")
                } else if project.isRemoteOnly {
                    remoteOnlyPlaceholder
                        .padding(.top, contentHeaderInset)
                } else {
                    FolderTreeView(
                        rootURL: project.url ?? URL(fileURLWithPath: "/"),
                        topContentInset: contentHeaderInset
                    )
                        .id(project.id)
                }

                header
                    .padding(.horizontal, Theme.headerHorizontalPadding)
                    .frame(height: Theme.headerContentHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.headerTopInset)
                    .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .top)
                    .glassEffect(.regular, in: .rect(cornerRadius: 0))
                    .ignoresSafeArea(edges: .top)
                    .zIndex(2)
            }
        }
        .task(id: project.id) {
            let p = project
            stats = await Task.detached { ProjectStats.compute(for: p) }.value
            loadFootageLink()
        }
        .overlay(dropOverlay)
        .overlay(alignment: .bottom) { messageBanner }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .sheet(isPresented: $showArchiveSheet) {
            ArchiveOptionsSheet(project: project) { foldersToRemove in
                showArchiveSheet = false
                performArchive(removing: foldersToRemove)
            } onCancel: {
                showArchiveSheet = false
            }
        }
        .sheet(isPresented: $showAddFootageSheet) {
            AddFootageSheet(projectName: project.name) { links in
                showAddFootageSheet = false
                queueAdditionalFootage(links)
            } onCancel: {
                showAddFootageSheet = false
            }
        }
        .confirmationDialog(
            "Delete \(project.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive, action: deleteProject)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project folder and all of its contents will be permanently removed from this Mac.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: project.isArchived ? "archivebox.fill" : "folder.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(accent)
                .symbolEffect(.bounce.byLayer, value: project.id)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.tint(accent.opacity(0.22)), in: .rect(cornerRadius: Theme.cardRadius))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    if project.isArchived {
                        Text("In iCloud")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                HStack(spacing: 10) {
                    Text("\(project.month.capitalized) \(project.year)")
                    if let stats { Text("Size \(stats.totalSizeText)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
            }

            GlassEffectContainer(spacing: Theme.controlSpacing) {
                HStack(spacing: Theme.controlSpacing) {
                if !project.isArchived && !project.isRemoteOnly {
                    Button(action: openProject) {
                        Image(systemName: "play.fill")
                            .tactileSymbol()
                            .headerActionLabel()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .help("Open project")
                    .accessibilityLabel("Open project")

                    Button {
                        showAddFootageSheet = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .tactileSymbol()
                            .headerActionLabel()
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Add footage links")
                    .accessibilityLabel("Add footage links")
                    .disabled(project.url == nil)
                }

                Button {
                    if let u = project.url { NSWorkspace.shared.open(u) }
                } label: {
                    Image(systemName: "folder")
                        .tactileSymbol()
                        .headerActionLabel()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal in Finder")
                .disabled(project.url == nil)

                if project.isArchived {
                    Button {
                        runRestore(downloadFootage: hasSavedFootageLink)
                } label: {
                    Image(systemName: "icloud.and.arrow.down")
                        .tactileSymbol()
                        .headerActionLabel()
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help(hasSavedFootageLink ? "Restore and download footage" : "Restore")
                    .accessibilityLabel(hasSavedFootageLink ? "Restore and download footage" : "Restore")
                    .disabled(isWorking)
                } else {
                    Button {
                        showArchiveSheet = true
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .tactileSymbol()
                        .headerActionLabel()
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Move project to iCloud")
                    .accessibilityLabel("Move project to iCloud")
                    .disabled(isWorking)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .tactileSymbol()
                        .headerActionLabel()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.red)
                .help("Delete project")
                .accessibilityLabel("Delete project")
                .disabled(project.isRemoteOnly || isWorking)
                }
            }
        }
    }

    // MARK: - Drop overlay

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted && !project.isArchived {
            ZStack {
                Rectangle().fill(accent.opacity(0.08))
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 38, weight: .light))
                    Text("Drop to sort into folders")
                        .font(.headline)
                }
                .foregroundStyle(accent)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .padding(8)
            )
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var remoteOnlyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("This project is stored in iCloud")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press Restore to bring it back to your local drive.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// Complete projects shared by Windows/Flutter are directories, so their
    /// real contents can be browsed without restoring them first.
    private var cloudDirectoryURL: URL? {
        guard project.isArchived, let root = iCloudStore.shared.rootURL else { return nil }
        let relativePath: String?
        if project.isRemoteOnly {
            relativePath = project.serverArchiveRelativePath
        } else if let manifestURL = project.manifestURL {
            relativePath = (try? ProjectManifest.load(from: manifestURL))?.archiveRelativePath
        } else {
            relativePath = nil
        }
        guard let relativePath else { return nil }
        let candidate = root.appendingPathComponent(relativePath)
        guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return candidate
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let summary = lastSummary, !summary.isEmpty {
            Label(summary.caption, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular.tint(accent.opacity(0.12)), in: .capsule)
                .glassEffectTransition(.materialize)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let message {
            Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(isError ? .red : .primary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(
                    .regular.tint((isError ? Color.red : accent).opacity(0.12)),
                    in: .capsule
                )
                .glassEffectTransition(.materialize)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func openProject() {
        guard let projectURL = project.url else { return }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        let projectFile = (enumerator?.allObjects as? [URL])?.first {
            ["prproj", "drp", "aep"].contains($0.pathExtension.lowercased())
        }
        NSWorkspace.shared.open(projectFile ?? projectURL)
    }

    private func deleteProject() {
        guard let url = project.url else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.removeItem(at: url)
                await MainActor.run {
                    isWorking = false
                    store.refresh()
                }
            } catch {
                await finish(error: error.localizedDescription)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !project.isArchived else { return false }
        DropURLLoader.load(providers) { urls in
            guard !urls.isEmpty else { return }
            let summary = FileSorter.sort(fileURLs: urls, into: project)
            withAnimation(reduceMotion ? .none : Motion.state) { lastSummary = summary }
            store.refresh()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(reduceMotion ? .none : Motion.feedback) { lastSummary = nil }
            }
        }
        return true
    }

    private func performArchive(removing foldersToRemove: Set<ProjectFolder>) {
        let destinationURL: URL
        do {
            destinationURL = try iCloudStore.shared.archiveURL(for: project)
        } catch {
            withAnimation(reduceMotion ? .none : Motion.feedback) { message = error.localizedDescription; isError = true }
            return
        }

        isWorking = true
        withAnimation(reduceMotion ? .none : Motion.feedback) { message = "Archiving to iCloud…"; isError = false }
        let project = project
        Task.detached(priority: .userInitiated) {
            do {
                try ProjectArchiver.archive(project, destinationURL: destinationURL, foldersToRemove: foldersToRemove)
                let removedNames = foldersToRemove.map(\.folderName).sorted().joined(separator: ", ")
                let detail = removedNames.isEmpty ? "nothing removed" : "removed: \(removedNames)"
                await finish(success: "Moved to iCloud. Valuables saved, \(detail).")
                await patchArchiveOnServer(project: project, destinationURL: destinationURL)
            } catch {
                await finish(error: error.localizedDescription)
            }
        }
    }

    private func runRestore(downloadFootage: Bool = false) {
        isWorking = true
        withAnimation(reduceMotion ? .none : Motion.feedback) {
            message = downloadFootage ? "Restoring from iCloud and queueing footage…" : "Restoring from iCloud…"
            isError = false
        }
        guard let archiveRoot = iCloudStore.shared.rootURL else {
            withAnimation(reduceMotion ? .none : Motion.feedback) {
                message = iCloudStore.iCloudError.rootNotSelected.localizedDescription
                isError = true
            }
            isWorking = false
            return
        }
        let footageLink = savedFootageLink()
        let project = project

        if project.isRemoteOnly {
            // Нет локальной папки — восстанавливаем в корень проектов.
            guard let projectsRoot = store.rootURL else {
                withAnimation(reduceMotion ? .none : Motion.feedback) {
                    message = "Projects folder is not selected."
                    isError = true
                }
                isWorking = false
                return
            }
            Task.detached(priority: .userInitiated) {
                do {
                    let restoredURL = try ProjectArchiver.restoreRemoteOnly(
                        project: project,
                        projectsRoot: projectsRoot,
                        archiveRoot: archiveRoot
                    )
                    await finishRestore(
                        projectURL: restoredURL,
                        footageLink: downloadFootage ? footageLink : nil
                    )
                } catch {
                    await finish(error: error.localizedDescription)
                }
            }
        } else {
            guard let manifest = project.manifestURL else {
                withAnimation(reduceMotion ? .none : Motion.feedback) {
                    message = "No manifest URL for this project."
                    isError = true
                }
                isWorking = false
                return
            }
            Task.detached(priority: .userInitiated) {
                do {
                    let restoredURL = try ProjectArchiver.restore(manifestURL: manifest, archiveRoot: archiveRoot)
                    await finishRestore(
                        projectURL: restoredURL,
                        footageLink: downloadFootage ? footageLink : nil
                    )
                } catch {
                    await finish(error: error.localizedDescription)
                }
            }
        }
    }

    private func saveFootageLink() {
        let trimmed = footageLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            guard let projectURL = project.url else { return }
            try ProjectMetadataStore.setFootageLink(trimmed, projectURL: projectURL)
            withAnimation(reduceMotion ? .none : Motion.feedback) {
                hasSavedFootageLink = true
                message = "Footage link saved."
                isError = false
            }
            hideMessageAfterDelay()
        } catch {
            withAnimation(reduceMotion ? .none : Motion.feedback) {
                message = error.localizedDescription
                isError = true
            }
        }
    }

    /// Queue extra links onto an existing project, downloading each into its
    /// FOOTAGE folder. Links are recorded in the manifest too, so a later
    /// archive/restore round trip can fetch them again.
    private func queueAdditionalFootage(_ links: [String]) {
        guard let projectURL = project.url, let downloadViewModel else { return }
        let footage = projectURL.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)

        for link in links {
            try? ProjectMetadataStore.setFootageLink(link, projectURL: projectURL)
            downloadViewModel.queueDownload(link: link, into: footage)
        }

        withAnimation(reduceMotion ? .none : Motion.feedback) {
            hasSavedFootageLink = true
            message = links.count == 1
                ? "Added 1 download."
                : "Added \(links.count) downloads."
            isError = false
        }
        hideMessageAfterDelay()
    }

    private func queueSavedFootageDownload(projectURL: URL) {
        guard let link = savedFootageLink(), let downloadViewModel else { return }
        let footage = projectURL.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)
        downloadViewModel.queueDownload(link: link, into: footage)
        withAnimation(reduceMotion ? .none : Motion.feedback) {
            message = "Footage download queued."
            isError = false
        }
        hideMessageAfterDelay()
    }

    private func loadFootageLink() {
        let link = savedFootageLink() ?? ""
        footageLink = link
        hasSavedFootageLink = !link.isEmpty
    }

    private func savedFootageLink() -> String? {
        if project.isArchived,
           let mURL = project.manifestURL,
           let manifest = try? ProjectManifest.load(from: mURL),
           let link = manifest.primaryFootageLink {
            return link
        }

        return project.metadata.primaryFootageLink
    }

    @MainActor
    private func finishRestore(projectURL: URL, footageLink: String?) {
        isWorking = false
        store.refresh()

        if let footageLink {
            let footage = projectURL.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)
            downloadViewModel?.queueDownload(link: footageLink, into: footage)
        }

        withAnimation(reduceMotion ? .none : Motion.feedback) {
            message = footageLink == nil
                ? "Restored. Re-download the heavy folders when needed."
                : "Restored. Footage download queued."
            isError = false
        }
        hideMessageAfterDelay()
    }

    @MainActor
    private func finish(success: String? = nil, error: String? = nil) {
        isWorking = false
        withAnimation(reduceMotion ? .none : Motion.feedback) {
            message = success ?? error
            isError = (error != nil)
        }
        store.refresh()
        hideMessageAfterDelay(expected: success ?? error)
    }

    private func hideMessageAfterDelay(expected: String? = nil) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? .none : Motion.state) {
                if expected == nil || message == expected {
                    message = nil
                }
            }
        }
    }

    @MainActor
    private func patchArchiveOnServer(project: Project, destinationURL: URL) async {
        guard AuthStore.shared.isLoggedIn else { return }
        let relativePath = iCloudStore.relativeArchivePath(for: project)
        let byteCount = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        let checksum = try? FileChecksum.sha256(of: destinationURL)
        let fmt = ISO8601DateFormatter()
        let patch = ProjectPatch(
            archiveRelativePath: relativePath,
            archiveByteCount: byteCount.map(Int.init),
            archiveChecksum: checksum,
            archivedAt: fmt.string(from: Date())
        )
        _ = try? await NetworkClient.shared.updateProject(id: project.id, patch: patch)
    }
}

// MARK: - Stat pill

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    var accent: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: Theme.smallRadius))
    }
}

// MARK: - Add footage sheet

/// Paste one or more links to download into an existing project's FOOTAGE
/// folder. One link per line, so a batch copied out of a brief can be pasted
/// in a single go.
private struct AddFootageSheet: View {
    let projectName: String
    let onAdd: ([String]) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var editorFocused: Bool

    private var links: [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text("Add Footage")
                        .font(.title3.weight(.semibold))
                }
                Text("Paste Google Drive or Dropbox links for \(projectName) — one per line. They download into FOOTAGE.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 150)
                .background(.quaternary.opacity(0.5))
                .focused($editorFocused)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            HStack {
                Text(links.isEmpty ? "No links yet" : "\(links.count) link\(links.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(Motion.continuous, value: links.count)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Download") { onAdd(links) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(links.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 460)
        .onAppear { editorFocused = true }
    }
}

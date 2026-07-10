import SwiftUI
import UniformTypeIdentifiers

/// Project detail: header with actions, a stats bar, and the folder tree.
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
    @State private var stats: ProjectStats?
    @State private var footageLink = ""
    @State private var hasSavedFootageLink = false

    private var accent: Color { project.isArchived ? .orange : Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: 116)
                .background { FrostedHeaderStrip() }
            Divider()
            statsBar
            Divider()
            if project.isRemoteOnly {
                remoteOnlyPlaceholder
            } else {
                FolderTreeView(rootURL: project.url ?? URL(fileURLWithPath: "/"))
                    .id(project.id)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: project.isArchived ? "archivebox.fill" : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, value: project.isArchived)
            }
            .popEntrance(delay: 0.04)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    if project.isArchived {
                        Text("Archived")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                Text("\(project.year) · \(project.month)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .popEntrance(delay: 0.08)

            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
            }

            // Action circles (VPN-style)
            HStack(spacing: 12) {
                ActionCircle(
                    systemImage: "arrow.up.forward.app",
                    label: "Reveal",
                    accent: accent
                ) {
                    if let u = project.url { NSWorkspace.shared.open(u) }
                }
                .disabled(project.url == nil)
                .popEntrance(delay: 0.10)

                if project.isArchived {
                    ActionCircle(
                        systemImage: hasSavedFootageLink ? "arrow.down.circle.fill" : "arrow.down.circle",
                        label: hasSavedFootageLink ? "Restore+" : "Restore",
                        accent: accent
                    ) {
                        runRestore(downloadFootage: hasSavedFootageLink)
                    }
                    .disabled(isWorking)
                    .popEntrance(delay: 0.14)
                } else {
                    ActionCircle(
                        systemImage: "archivebox",
                        label: "Archive",
                        accent: accent
                    ) {
                        showArchiveSheet = true
                    }
                    .disabled(isWorking)
                    .popEntrance(delay: 0.14)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(SoftIOSMotion.state, value: isWorking)
        .animation(SoftIOSMotion.state, value: project.isArchived)
    }

    // MARK: - Stats bar

    @ViewBuilder
    private var statsBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 10) {
                if let stats {
                    StatPill(icon: "doc.on.doc", value: "\(stats.fileCount)", label: "Files")
                    StatPill(icon: "internaldrive", value: stats.totalSizeText, label: "Size")
                    if stats.reclaimableBytes > 0 && !project.isArchived {
                        StatPill(icon: "arrow.down.circle", value: stats.reclaimableText,
                                 label: "Frees up", accent: .green)
                    }
                    footageLinkControl
                } else {
                    ProgressView().controlSize(.small)
                    Text("Calculating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var footageLinkControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(hasSavedFootageLink ? Theme.accent : .secondary)

            TextField("Footage link", text: $footageLink)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(minWidth: 170)
                .disabled(project.isArchived)
                .onSubmit(saveFootageLink)

            if project.isArchived {
                if hasSavedFootageLink {
                    Button {
                        if let u = project.url { queueSavedFootageDownload(projectURL: u) }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .buttonStyle(.plain)
                    .help("Download footage into this project's FOOTAGE folder")
                    .disabled(downloadViewModel == nil || isWorking)
                }
            } else {
                Button {
                    saveFootageLink()
                } label: {
                    Image(systemName: hasSavedFootageLink ? "checkmark.circle.fill" : "tray.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save footage link")
                .disabled(footageLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
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
                RoundedRectangle(cornerRadius: 12)
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
            Text("This project is archived in iCloud")
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

    @ViewBuilder
    private var messageBanner: some View {
        if let summary = lastSummary, !summary.isEmpty {
            Label(summary.caption, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular.tint(Theme.accent.opacity(0.85)), in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let message {
            Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular.tint((isError ? Color.red : Color.green).opacity(0.85)), in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !project.isArchived else { return false }
        DropURLLoader.load(providers) { urls in
            guard !urls.isEmpty else { return }
            let summary = FileSorter.sort(fileURLs: urls, into: project)
            withAnimation(Motion.standard) { lastSummary = summary }
            store.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { lastSummary = nil }
            }
        }
        return true
    }

    private func performArchive(removing foldersToRemove: Set<ProjectFolder>) {
        let destinationURL: URL
        do {
            destinationURL = try iCloudStore.shared.archiveURL(for: project)
        } catch {
            withAnimation(Motion.quick) { message = error.localizedDescription; isError = true }
            return
        }

        isWorking = true
        withAnimation(Motion.quick) { message = "Archiving to iCloud…"; isError = false }
        let project = project
        Task.detached(priority: .userInitiated) {
            do {
                try ProjectArchiver.archive(project, destinationURL: destinationURL, foldersToRemove: foldersToRemove)
                let removedNames = foldersToRemove.map(\.folderName).sorted().joined(separator: ", ")
                let detail = removedNames.isEmpty ? "nothing removed" : "removed: \(removedNames)"
                await finish(success: "Archived. Valuables in iCloud, \(detail).")
                await patchArchiveOnServer(project: project, destinationURL: destinationURL)
            } catch {
                await finish(error: error.localizedDescription)
            }
        }
    }

    private func runRestore(downloadFootage: Bool = false) {
        isWorking = true
        withAnimation(Motion.quick) {
            message = downloadFootage ? "Restoring from iCloud and queueing footage…" : "Restoring from iCloud…"
            isError = false
        }
        guard let archiveRoot = iCloudStore.shared.rootURL else {
            withAnimation(Motion.quick) {
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
                withAnimation(Motion.quick) {
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
                withAnimation(Motion.quick) {
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
            withAnimation(Motion.quick) {
                hasSavedFootageLink = true
                message = "Footage link saved."
                isError = false
            }
            hideMessageAfterDelay()
        } catch {
            withAnimation(Motion.quick) {
                message = error.localizedDescription
                isError = true
            }
        }
    }

    private func queueSavedFootageDownload(projectURL: URL) {
        guard let link = savedFootageLink(), let downloadViewModel else { return }
        let footage = projectURL.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)
        downloadViewModel.queueDownload(link: link, into: footage)
        withAnimation(Motion.quick) {
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

        withAnimation(Motion.quick) {
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
        withAnimation(Motion.quick) {
            message = success ?? error
            isError = (error != nil)
        }
        store.refresh()
        hideMessageAfterDelay(expected: success ?? error)
    }

    private func hideMessageAfterDelay(expected: String? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation {
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

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accent)
                .scaleEffect(isHovered ? 1.15 : 1)
                .animation(SoftIOSMotion.hover, value: isHovered)
                .symbolEffect(.bounce, value: isHovered)
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
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        .onHover { isHovered = $0 }
    }
}

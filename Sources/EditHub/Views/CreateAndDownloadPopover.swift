import AppKit
import SwiftUI

extension ProjectTemplate {
    /// Short label for the segmented control / type toggle.
    var shortTitle: String {
        switch self {
        case .premiere: return "Premiere + AE"
        case .davinci: return "DaVinci Resolve"
        }
    }

    /// SF Symbol shown on the one-tap type toggle.
    var primaryIcon: String {
        switch self {
        case .premiere: return "film.stack"
        case .davinci: return "camera.aperture"
        }
    }
}

/// The single create + download surface, shown from the floating "+" button.
///
/// Enter a project name and (optionally) a download link. The month is read
/// from the system clock; tap the calendar button to target a different month.
/// The project type toggles between Premiere and DaVinci with one button.
/// Pressing "Add to queue" creates the project, queues the link into its
/// FOOTAGE folder, and clears the fields for the next one — downloads run in
/// the background and show their progress on the project in the list.
struct CreateAndDownloadPopover: View {
    @Environment(ProjectStore.self) private var store
    @Bindable var downloadViewModel: DownloadViewModel
    /// Called with the freshly created project so the list can select it.
    let onCreated: (Project) -> Void
    /// Closes the popover (used after a successful create so it "lands" in the hub).
    var onDismiss: () -> Void = {}
    let morphNamespace: Namespace.ID

    @State private var projectName = ""
    @State private var link = ""
    @State private var template: ProjectTemplate = .premiere
    @State private var monthOffset = 0   // 0 = this month, -1 = last month, …
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    @AppStorage(ProjectTemplate.storageKey) private var storedTemplateRawValue = ProjectTemplate.premiere.rawValue

    private var sanitizedName: String {
        ProjectScaffolder.sanitizeProjectName(projectName)
    }

    private var canCreate: Bool {
        store.rootURL != nil && !sanitizedName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var targetDate: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthLabel: String {
        let (year, month) = ProjectScaffolder.yearMonth(for: targetDate)
        return "\(month.capitalized) \(year)"
    }

    // Shared metrics: capsule fields and matching round buttons beside them.
    private let fieldHeight: CGFloat = 52
    private let panelRadius: CGFloat = 30

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: panelRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            header

            // Name field + round project-type toggle, facing each other.
            HStack(spacing: 10) {
                nameField
                typeButton
            }

            // Link field + round month picker, facing each other.
            HStack(spacing: 10) {
                linkField
                monthButton
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .transition(.opacity)
            }

            if !downloadViewModel.queue.isEmpty || downloadViewModel.isLoading {
                queueStatus
            }

            createButton
                .padding(.top, 2)
        }
        .padding(20)
        .background {
            panelShape
                .fill(.regularMaterial)
                .overlay {
                    panelShape
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                }
                .glassEffect(.regular, in: panelShape)
                .glassEffectID("create-surface", in: morphNamespace)
        }
        .overlay {
            panelShape
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        }
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .animation(SoftIOSMotion.state, value: errorMessage)
        .animation(SoftIOSMotion.state, value: downloadViewModel.queue.count)
        .onAppear {
            template = ProjectTemplate(rawValue: storedTemplateRawValue) ?? .premiere
            nameFocused = true
        }
    }

    /// Capsule chrome shared by the text fields.
    private func fieldChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = Capsule()

        return content()
            .font(.callout)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: fieldHeight)
            .background {
                shape
                    .fill(.regularMaterial)
                    .overlay {
                        shape.fill(Color(nsColor: .textBackgroundColor).opacity(0.58))
                    }
            }
            .overlay {
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    /// Round icon button shared by the month picker and type toggle.
    private func roundButtonChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: fieldHeight, height: fieldHeight)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("New Project")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if store.rootURL == nil {
                Label("No library", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: - Fields

    private var nameField: some View {
        fieldChrome {
            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .foregroundStyle(.secondary)
                TextField("Project name", text: $projectName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .focused($nameFocused)
                    .onSubmit(create)
            }
        }
    }

    private var linkField: some View {
        fieldChrome {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Download link (optional)", text: $link)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.primary)
                if !link.isEmpty {
                    Button {
                        link = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Round buttons

    private var monthButton: some View {
        Menu {
            ForEach(0..<12, id: \.self) { back in
                let date = Calendar.current.date(byAdding: .month, value: -back, to: Date()) ?? Date()
                let (year, month) = ProjectScaffolder.yearMonth(for: date)
                Button("\(month.capitalized) \(year)") { monthOffset = -back }
            }
        } label: {
            roundButtonChrome {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Target month: \(monthLabel) — click to change")
    }

    private var typeButton: some View {
        Button {
            template = (template == .premiere) ? .davinci : .premiere
            storedTemplateRawValue = template.rawValue
        } label: {
            roundButtonChrome {
                Image(systemName: template.primaryIcon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .help("Project type: \(template.menuTitle) — click to switch")
    }

    // MARK: - Queue status

    private var queueStatus: some View {
        HStack(spacing: 8) {
            if downloadViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text(downloadViewModel.progressCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "tray.full")
                    .foregroundStyle(.secondary)
                Text("\(downloadViewModel.queue.count) waiting in queue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !downloadViewModel.queue.isEmpty {
                Button("Clear") { downloadViewModel.clearQueue() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Create

    private var createButton: some View {
        Button(action: create) {
            Label(link.isEmpty ? "Create Project" : "Create & Download", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: fieldHeight)
        }
        .keyboardShortcut(.return, modifiers: [])
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canCreate)
    }

    // MARK: - Server sync

    private func pushToServer(_ project: Project) {
        guard AuthStore.shared.isLoggedIn else { return }
        Task {
            let fmt = ISO8601DateFormatter()
            let payload = ProjectPayload(
                id: project.id.uuidString,
                name: project.name,
                year: project.year,
                month: project.month,
                template: nil,
                footageLinks: project.metadata.footageLinks,
                archiveRelativePath: nil,
                archiveByteCount: nil,
                archiveChecksum: nil,
                archivedAt: nil
            )
            _ = try? await NetworkClient.shared.createProject(payload)
            _ = fmt  // suppress unused warning
        }
    }

    // MARK: - Action

    private func create() {
        guard let root = store.rootURL else {
            withAnimation(SoftIOSMotion.state) { errorMessage = "Choose a root folder first." }
            return
        }
        do {
            let url = try ProjectScaffolder.createStructure(
                rootURL: root,
                rawProjectName: projectName,
                template: template,
                date: targetDate
            )
            store.refresh()

            // Queue the download into the new project's FOOTAGE, if a link was given.
            let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLink.isEmpty {
                try? ProjectMetadataStore.setFootageLink(trimmedLink, projectURL: url)
                let footage = url.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)
                downloadViewModel.queueDownload(link: trimmedLink, into: footage)
            }

            // Select the new project so it "lands" in the hub, then close the
            // popover — the list animates the new row in.
            if let project = store.projects.first(where: { $0.url == url }) {
                onCreated(project)
                pushToServer(project)
            }

            projectName = ""
            link = ""
            errorMessage = nil
            onDismiss()
        } catch {
            withAnimation(SoftIOSMotion.state) { errorMessage = error.localizedDescription }
        }
    }
}

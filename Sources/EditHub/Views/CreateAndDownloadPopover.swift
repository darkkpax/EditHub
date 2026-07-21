import SwiftUI

extension ProjectTemplate {
    var shortTitle: String {
        switch self {
        case .premiere: "Premiere Pro"
        case .davinci: "DaVinci Resolve"
        }
    }

    var primaryIcon: String {
        switch self {
        case .premiere: "film.stack"
        case .davinci: "camera.aperture"
        }
    }
}

/// Native macOS counterpart of Flutter's NewProjectPopover: editor toggle,
/// project name, optional footage link, and one primary action.
struct CreateAndDownloadPopover: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var downloadViewModel: DownloadViewModel
    let onCreated: (Project) -> Void
    var onDismiss: () -> Void = {}
    let morphNamespace: Namespace.ID

    @State private var projectName = ""
    @State private var link = ""
    @State private var template: ProjectTemplate = .davinci
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool
    @AppStorage(ProjectTemplate.storageKey) private var storedTemplate = ProjectTemplate.davinci.rawValue

    private var canCreate: Bool {
        store.rootURL != nil && !ProjectScaffolder.sanitizeProjectName(projectName).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? .none : Motion.feedback) {
                        template = template == .davinci ? .premiere : .davinci
                    }
                } label: {
                    Image(systemName: template.primaryIcon)
                        .font(.system(size: 15, weight: .medium))
                        .tactileSymbol()
                        .frame(width: 38, height: 38)
                        .contentTransition(.symbolEffect(.replace))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.controlRadius))
                }
                .buttonStyle(.plain)
                .help(template.shortTitle)

                glassField {
                    TextField("Name", text: $projectName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($nameFocused)
                        .onSubmit(create)
                }
            }

            glassField {
                TextField("Footage", text: $link)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit(create)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.blurReplace)
            }

            Button(action: create) {
                Text(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Create" : "Create & Download")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: Theme.controlRadius))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.035)), in: .rect(cornerRadius: Theme.popoverRadius))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .onAppear {
            template = ProjectTemplate(rawValue: storedTemplate) ?? .davinci
            nameFocused = true
        }
        .onChange(of: template) { _, newValue in storedTemplate = newValue.rawValue }
        .animation(reduceMotion ? .none : Motion.reveal, value: errorMessage)
    }

    private func glassField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.controlRadius))
    }

    private func create() {
        guard let root = store.rootURL else {
            errorMessage = "Choose a projects folder first."
            return
        }

        do {
            let url = try ProjectScaffolder.createStructure(
                rootURL: root,
                rawProjectName: projectName,
                template: template,
                date: Date()
            )
            store.refresh()

            let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLink.isEmpty {
                try? ProjectMetadataStore.setFootageLink(trimmedLink, projectURL: url)
                let footage = url.appendingPathComponent(ProjectFolder.footage.folderName, isDirectory: true)
                downloadViewModel.queueDownload(link: trimmedLink, into: footage)
            }

            if let project = store.projects.first(where: { $0.url == url }) {
                onCreated(project)
                pushToServer(project)
            }
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pushToServer(_ project: Project) {
        guard AuthStore.shared.isLoggedIn else { return }
        Task {
            let payload = ProjectPayload(
                id: project.id,
                name: project.name,
                year: project.year,
                month: project.month,
                template: template.rawValue,
                footageLinks: project.metadata.footageLinks,
                archiveRelativePath: nil,
                archiveByteCount: nil,
                archiveChecksum: nil,
                archivedAt: nil
            )
            _ = try? await NetworkClient.shared.createProject(payload)
        }
    }
}

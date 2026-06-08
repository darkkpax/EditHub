import SwiftUI

/// Раздел «Скачать»: ссылка Google Drive / Dropbox + выбор целевого проекта
/// и папки. По умолчанию качает в FOOTAGE выбранного проекта.
struct DownloadView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var viewModel = DownloadViewModel()

    let targetProject: Project?

    @State private var selectedProjectID: Project.ID?
    @State private var targetFolder: ProjectFolder = .footage

    private var activeProjects: [Project] {
        store.projects.filter { !$0.isArchived }
    }

    private var resolvedProject: Project? {
        if let id = selectedProjectID {
            return store.projects.first { $0.id == id }
        }
        return targetProject ?? activeProjects.first
    }

    var body: some View {
        Form {
            Section("ССЫЛКА") {
                TextField("Google Drive или Dropbox ссылка", text: $viewModel.linkText)
            }

            Section("КУДА СКАЧАТЬ") {
                Picker("Проект", selection: Binding(
                    get: { resolvedProject?.id },
                    set: { selectedProjectID = $0 }
                )) {
                    ForEach(activeProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker("Папка", selection: $targetFolder) {
                    ForEach(ProjectFolder.allCases) { folder in
                        Text(folder.folderName).tag(folder)
                    }
                }

                Text(viewModel.destinationDisplayPath.isEmpty ? "Папка не задана" : viewModel.destinationDisplayPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            if viewModel.isLoading {
                Section {
                    ProgressView(value: viewModel.progressFraction) {
                        Text(viewModel.progressCaption)
                            .font(.system(size: 10))
                    }
                    Text(viewModel.downloadSpeedText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage, viewModel.hasError {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            Button(viewModel.isLoading ? "СКАЧИВАЕТСЯ…" : "СКАЧАТЬ") {
                applyDestination()
                viewModel.startDownload()
            }
            .disabled(resolvedProject == nil || viewModel.linkText.isEmpty || viewModel.isLoading)
        }
        .formStyle(.grouped)
        .navigationTitle("Скачать")
        .onChange(of: targetFolder) { _ in applyDestination() }
        .onChange(of: selectedProjectID) { _ in applyDestination() }
        .onAppear { applyDestination() }
    }

    private func applyDestination() {
        guard let project = resolvedProject else { return }
        viewModel.setDestination(project.folderURL(targetFolder))
    }
}

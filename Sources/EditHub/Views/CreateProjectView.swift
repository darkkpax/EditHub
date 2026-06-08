import SwiftUI

/// Форма создания нового проекта через [[ProjectScaffolder]].
struct CreateProjectView: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var selectedProject: Project?
    let switchToProjects: () -> Void

    @State private var projectName = ""
    @State private var template: ProjectTemplate = .premiere
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section("НОВЫЙ ПРОЕКТ") {
                TextField("Название проекта", text: $projectName)
                    .focused($nameFocused)
                    .onSubmit(create)

                Picker("Шаблон", selection: $template) {
                    ForEach(ProjectTemplate.allCases) { tmpl in
                        Text(tmpl.menuTitle).tag(tmpl)
                    }
                }
            }

            Section {
                Text(rootHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            Button("СОЗДАТЬ СТРУКТУРУ", action: create)
                .disabled(store.rootURL == nil || projectName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .formStyle(.grouped)
        .navigationTitle("Создать проект")
        .onAppear { nameFocused = true }
    }

    private var rootHint: String {
        if let path = store.rootURL?.path {
            return "Структура \(ProjectScaffolder.subfolders.joined(separator: ", ")) создаётся в:\n\(path)/<ГОД>/<МЕСЯЦ>/<ИМЯ>"
        }
        return "Сначала выбери корневую папку проектов в сайдбаре снизу."
    }

    private func create() {
        guard let root = store.rootURL else {
            errorMessage = "Выбери корневую папку."
            return
        }
        do {
            let url = try ProjectScaffolder.createStructure(
                rootURL: root,
                rawProjectName: projectName,
                template: template
            )
            store.refresh()
            errorMessage = nil
            projectName = ""
            if let created = store.projects.first(where: { $0.url == url }) {
                selectedProject = created
            }
            switchToProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

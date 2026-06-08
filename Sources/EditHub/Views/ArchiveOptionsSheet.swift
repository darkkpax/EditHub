import SwiftUI

/// Диалог перед консервацией: пользователь выбирает, какие тяжёлые папки
/// удалить локально (по умолчанию — все). Ценные папки всегда уходят в архив.
struct ArchiveOptionsSheet: View {
    let project: Project
    let onArchive: (Set<ProjectFolder>) -> Void
    let onCancel: () -> Void

    /// Выбранные для удаления тяжёлые папки. По умолчанию — все непустые.
    @State private var toRemove: Set<ProjectFolder> = []
    @State private var sizes: [ProjectFolder: Int64] = [:]
    @State private var didLoad = false

    private var heavyFolders: [ProjectFolder] {
        ProjectFolder.removableOnArchive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Консервация «\(project.name)»")
                    .font(.system(size: 14, weight: .semibold))
                Text("Ценные папки (музыка, войсы, броллы, sfx, сабы) уйдут в iCloud. Выбери, какие тяжёлые папки удалить локально — их легко перекачать заново.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("УДАЛИТЬ ЛОКАЛЬНО")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                ForEach(heavyFolders) { folder in
                    Toggle(isOn: binding(for: folder)) {
                        HStack(spacing: 8) {
                            Image(systemName: folder.systemImage)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(folder.folderName)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(sizeText(for: folder))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            HStack {
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Законсервировать") {
                    onArchive(toRemove)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: loadOnce)
    }

    private func binding(for folder: ProjectFolder) -> Binding<Bool> {
        Binding(
            get: { toRemove.contains(folder) },
            set: { isOn in
                if isOn { toRemove.insert(folder) } else { toRemove.remove(folder) }
            }
        )
    }

    private func sizeText(for folder: ProjectFolder) -> String {
        guard let bytes = sizes[folder] else { return "—" }
        if bytes == 0 { return "пусто" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Считаем размеры папок и по умолчанию помечаем непустые для удаления.
    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        var computed: [ProjectFolder: Int64] = [:]
        var defaults: Set<ProjectFolder> = []
        for folder in heavyFolders {
            let size = directorySize(project.folderURL(folder))
            computed[folder] = size
            if size > 0 { defaults.insert(folder) }
        }
        sizes = computed
        toRemove = defaults
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

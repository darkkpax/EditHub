import SwiftUI

/// Shown before archiving: the user picks which heavy folders to delete locally
/// (all non-empty ones by default). Valuable folders always go to iCloud.
struct ArchiveOptionsSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: Project
    let onArchive: (Set<ProjectFolder>) -> Void
    let onCancel: () -> Void

    @State private var toRemove: Set<ProjectFolder> = []
    @State private var sizes: [ProjectFolder: Int64] = [:]
    @State private var didLoad = false

    private var heavyFolders: [ProjectFolder] {
        ProjectFolder.removableOnArchive
    }

    private var reclaimable: Int64 {
        toRemove.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            folderList
            Divider()
            footer
        }
        .frame(width: 440)
        .onAppear(perform: loadOnce)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce.byLayer, value: didLoad)
                Text("Move “\(project.name)” to iCloud")
                    .font(.title3.weight(.semibold))
            }
            Text("Valuable folders (Music, Voice, B-Roll, SFX, Subs) are saved to iCloud. Choose which heavy folders to delete locally — they're easy to re-download.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var folderList: some View {
        VStack(spacing: 0) {
            ForEach(heavyFolders) { folder in
                Toggle(isOn: binding(for: folder)) {
                    HStack(spacing: 9) {
                        Image(systemName: folder.systemImage)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.bounce.byLayer, value: toRemove.contains(folder))
                        Text(folder.folderName)
                        Spacer()
                        Text(sizeText(for: folder))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
    }

    private var footer: some View {
        HStack {
            if reclaimable > 0 {
                Label("Frees up \(reclaimable.formatted(.byteCount(style: .file)))",
                      systemImage: "arrow.down.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Move to iCloud") {
                onArchive(toRemove)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func binding(for folder: ProjectFolder) -> Binding<Bool> {
        Binding(
            get: { toRemove.contains(folder) },
            set: { isOn in
                withAnimation(reduceMotion ? .none : Motion.feedback) {
                    if isOn { toRemove.insert(folder) } else { toRemove.remove(folder) }
                }
            }
        )
    }

    private func sizeText(for folder: ProjectFolder) -> String {
        guard let bytes = sizes[folder] else { return "—" }
        if bytes == 0 { return "Empty" }
        return bytes.formatted(.byteCount(style: .file))
    }

    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        var computed: [ProjectFolder: Int64] = [:]
        var defaults: Set<ProjectFolder> = []
        for folder in heavyFolders {
            let size = project.folderURL(folder).map { directorySize($0) } ?? 0
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

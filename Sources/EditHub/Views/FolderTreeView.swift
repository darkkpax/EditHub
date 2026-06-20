import SwiftUI

/// A single file-system entry. Cheap to create — holds no children; the tree
/// scans a directory's contents lazily and only when a row is expanded.
struct FileNode: Identifiable {
    let id: URL
    let url: URL
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool) {
        self.id = url
        self.url = url
        self.isDirectory = isDirectory
    }

    /// One synchronous directory read. Callers cache the result — never call
    /// this from a SwiftUI `body`/computed property, or it runs on every frame.
    static func scan(_ url: URL) -> [FileNode] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .sorted { lhs, rhs in
                let lDir = lhs.hasDirectoryPath, rDir = rhs.hasDirectoryPath
                if lDir != rDir { return lDir && !rDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { FileNode(url: $0, isDirectory: $0.hasDirectoryPath) }
    }
}

/// Finder-like folder tree using a native disclosure list. The root is scanned
/// once into state (and on the project id changing), not on every render.
struct FolderTreeView: View {
    let rootURL: URL

    @State private var rootNodes: [FileNode] = []
    @State private var didLoad = false

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rootNodes.isEmpty {
                ContentUnavailableView("Empty Project", systemImage: "folder",
                                       description: Text("Drop files here to sort them into folders."))
            } else {
                List {
                    ForEach(rootNodes) { node in
                        FolderTreeRow(node: node, depth: 0)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .task(id: rootURL) {
            didLoad = false
            let url = rootURL
            let nodes = await Task.detached { FileNode.scan(url) }.value
            guard !Task.isCancelled else { return }
            rootNodes = nodes
            didLoad = true
        }
    }
}

/// One row with disclosure. Project folders (FOOTAGE, MUSIC …) get an accent
/// icon and a content count.
private struct FolderTreeRow: View {
    let node: FileNode
    let depth: Int

    @State private var isExpanded = false
    @State private var children: [FileNode]?
    @State private var childCount: Int?

    private var projectFolder: ProjectFolder? {
        node.isDirectory ? ProjectFolder(rawValue: node.url.lastPathComponent) : nil
    }

    private var accent: Color {
        projectFolder != nil ? Theme.accent : (node.isDirectory ? Color.accentColor : .secondary)
    }

    var body: some View {
        Group {
            row
            if isExpanded, let children {
                ForEach(children) { child in
                    FolderTreeRow(node: child, depth: depth + 1)
                }
            }
        }
        // Read the child count once for directories so the row can show a count
        // and a disclosure chevron without scanning on every render.
        .task(id: node.id) {
            guard node.isDirectory, childCount == nil else { return }
            let url = node.url
            let scanned = await Task.detached { FileNode.scan(url) }.value
            childCount = scanned.count
            if isExpanded { children = scanned }
        }
    }

    private var row: some View {
        HStack(spacing: 7) {
            if node.isDirectory && (childCount ?? 0) > 0 {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(accent)
                .frame(width: 18)

            Text(node.url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let count = childCount, count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                toggleExpansion()
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        }
    }

    private func toggleExpansion() {
        // Lazily scan children the first time this folder opens, off the main
        // thread, then expand once they're loaded.
        if !isExpanded, children == nil {
            let url = node.url
            Task {
                let scanned = await Task.detached { FileNode.scan(url) }.value
                children = scanned
                childCount = scanned.count
                withAnimation(Motion.snappy) { isExpanded = true }
            }
        } else {
            withAnimation(Motion.snappy) { isExpanded.toggle() }
        }
    }

    private var icon: String {
        if let folder = projectFolder { return folder.systemImage }
        if node.isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return "doc"
    }
}

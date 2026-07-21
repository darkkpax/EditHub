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
    var topContentInset: CGFloat = 0

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
                    if topContentInset > 0 {
                        Color.clear
                            .frame(height: topContentInset)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .accessibilityHidden(true)
                    }
                    ForEach(rootNodes) { node in
                        FolderTreeRow(node: node, depth: 0)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 12, for: .scrollContent)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .listRowSeparator(.hidden)
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
        Button {
            if node.isDirectory {
                toggleExpansion()
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        } label: {
            HStack(spacing: 10) {
            if node.isDirectory && (childCount ?? 0) > 0 {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .symbolEffect(.bounce.byLayer, value: isExpanded)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            // One optical size for every glyph in the tree: a mixed 18/22pt
            // ramp made sibling rows look misaligned. `.frame` alone does not
            // equalise them — SF Symbols scale by font size, not by frame.
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
                .tactileSymbol()
                .frame(width: 24, height: 24)

            Text(node.url.lastPathComponent)
                .font(projectFolder == nil ? .body : .headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let count = childCount, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, projectFolder == nil ? 7 : 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
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
                withAnimation(reduceMotion ? .none : Motion.state) { isExpanded = true }
            }
        } else {
            withAnimation(reduceMotion ? .none : Motion.state) { isExpanded.toggle() }
        }
    }

    private var icon: String {
        if let folder = projectFolder { return folder.systemImage }
        if node.isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return "doc"
    }
}

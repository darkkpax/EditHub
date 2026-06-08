import SwiftUI

/// Узел дерева файловой системы (ленивая подгрузка детей).
struct FileNode: Identifiable {
    let id: URL
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]? {
        guard isDirectory else { return nil }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let nodes = entries
            .sorted { lhs, rhs in
                let lDir = lhs.hasDirectoryPath, rDir = rhs.hasDirectoryPath
                if lDir != rDir { return lDir && !rDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { FileNode(id: $0, url: $0, isDirectory: $0.hasDirectoryPath, children: nil) }
        return nodes.isEmpty ? nil : nodes
    }

    init(id: URL, url: URL, isDirectory: Bool, children: [FileNode]?) {
        self.id = id
        self.url = url
        self.isDirectory = isDirectory
    }
}

/// Finder-подобное дерево папок проекта.
struct FolderTreeView: View {
    let rootURL: URL

    private var rootNodes: [FileNode] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .sorted { lhs, rhs in
                let lDir = lhs.hasDirectoryPath, rDir = rhs.hasDirectoryPath
                if lDir != rDir { return lDir && !rDir }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { FileNode(id: $0, url: $0, isDirectory: $0.hasDirectoryPath, children: nil) }
    }

    var body: some View {
        List(rootNodes, children: \.children) { node in
            HStack(spacing: 6) {
                Image(systemName: icon(for: node))
                    .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(node.url.lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .onTapGesture(count: 2) {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        }
    }

    private func icon(for node: FileNode) -> String {
        if node.isDirectory {
            if let folder = ProjectFolder(rawValue: node.url.lastPathComponent) {
                return folder.systemImage
            }
            return "folder"
        }
        return "doc"
    }
}

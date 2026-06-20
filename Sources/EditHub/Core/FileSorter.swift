import Foundation
import UniformTypeIdentifiers

/// Безопасно собрать список file-URL из провайдеров drag-and-drop.
/// Потокобезопасно аккумулирует результаты и вызывает completion на main.
enum DropURLLoader {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let box = Box()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(box.all) }
    }
}

/// Результат раскладки одного дропа: сколько файлов ушло в каждую папку.
struct SortSummary {
    private(set) var counts: [ProjectFolder: Int] = [:]
    private(set) var failures: [String] = []

    var total: Int { counts.values.reduce(0, +) }
    var isEmpty: Bool { total == 0 && failures.isEmpty }

    mutating func record(_ folder: ProjectFolder) {
        counts[folder, default: 0] += 1
    }

    mutating func fail(_ name: String) {
        failures.append(name)
    }

    /// Человекочитаемая сводка: «3 → MUSIC · 2 → FOOTAGE».
    var caption: String {
        let parts = counts
            .sorted { $0.value > $1.value }
            .map { "\($0.value) → \($0.key.folderName)" }
        var text = parts.joined(separator: " · ")
        if !failures.isEmpty {
            text += text.isEmpty ? "" : " · "
            text += "\(failures.count) FAILED"
        }
        return text.isEmpty ? "NOTHING TO SORT" : text
    }
}

/// Перемещает файлы в подпапки проекта согласно [[FileClassifier]].
enum FileSorter {
    /// Разложить набор файлов по папкам проекта.
    /// - Returns: сводка по раскладке.
    @discardableResult
    static func sort(fileURLs: [URL], into project: Project) -> SortSummary {
        let fm = FileManager.default
        var summary = SortSummary()

        for source in fileURLs {
            let sourceFolderName = source.deletingLastPathComponent().lastPathComponent
            let target = FileClassifier.classify(
                fileName: source.lastPathComponent,
                sourceFolderName: sourceFolderName
            )
            guard let targetDir = project.folderURL(target) else { continue }

            do {
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                let destination = uniqueDestination(for: source.lastPathComponent, in: targetDir)
                try fm.moveItem(at: source, to: destination)
                summary.record(target)
            } catch {
                summary.fail(source.lastPathComponent)
            }
        }

        return summary
    }

    /// Подобрать незанятое имя в папке: `name.ext`, `name 2.ext`, `name 3.ext`…
    private static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        var candidate = directory.appendingPathComponent(fileName)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }
}

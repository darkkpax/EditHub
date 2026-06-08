import Foundation

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case premiere
    case davinci

    static let storageKey = "selectedProjectTemplate"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .premiere:
            return "Premiere + After Effects"
        case .davinci:
            return "DaVinci Resolve"
        }
    }
}

enum ProjectScaffolderError: LocalizedError {
    case invalidProjectName
    case missingTemplate(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectName:
            return "Project name is empty after sanitization."
        case let .missingTemplate(name):
            return "Template file is missing in app bundle: \(name)."
        }
    }
}

struct ProjectScaffolder {
    /// Подпапки проекта. Единый источник истины — [[ProjectFolder]].
    static let subfolders = ProjectFolder.allCases.map(\.folderName)

    static let voiceSubfolders = [
        "NOT ENHANCE",
        "ENHANCE"
    ]

    static func sanitizeProjectName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "[/:\\\\?%*|\"<>]"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return trimmed.uppercased()
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let sanitized = regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "-")
        return sanitized.uppercased()
    }

    static func createStructure(rootURL: URL, rawProjectName: String, template: ProjectTemplate) throws -> URL {
        let projectName = sanitizeProjectName(rawProjectName)
        guard !projectName.isEmpty else { throw ProjectScaffolderError.invalidProjectName }

        let date = Date()
        let yearFormatter = DateFormatter()
        yearFormatter.locale = Locale(identifier: "en_US_POSIX")
        yearFormatter.dateFormat = "yyyy"

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthFormatter.dateFormat = "LLLL"

        let year = yearFormatter.string(from: date)
        let month = monthFormatter.string(from: date).uppercased()

        let projectURL = rootURL
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)

        for folder in subfolders {
            let folderURL = projectURL.appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let voiceURL = projectURL.appendingPathComponent("VOICE", isDirectory: true)
        for folder in voiceSubfolders {
            let folderURL = voiceURL.appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        switch template {
        case .premiere:
            try copyTemplateIfNeeded(
                resource: "PremiereTemplate",
                ext: "prproj",
                destination: projectURL.appendingPathComponent("\(projectName).prproj")
            )

            try copyTemplateIfNeeded(
                resource: "AfterEffectsTemplate",
                ext: "aep",
                destination: projectURL.appendingPathComponent("\(projectName).aep")
            )

        case .davinci:
            try copyTemplateIfNeeded(
                resource: "DaVinciTemplate",
                ext: "drp",
                destination: projectURL.appendingPathComponent("\(projectName).drp")
            )
        }

        return projectURL
    }

    private static func copyTemplateIfNeeded(resource: String, ext: String, destination: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            return
        }

        // Если шаблон не вложен в бандл — мягко пропускаем (структура папок
        // важнее, чем заготовка .prproj). Шаблоны можно добавить позже.
        guard let templateURL = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return
        }

        try fileManager.copyItem(at: templateURL, to: destination)
    }
}

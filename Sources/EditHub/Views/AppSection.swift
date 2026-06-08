import SwiftUI

/// Разделы сайдбара.
enum AppSection: String, CaseIterable, Identifiable {
    case projects
    case create
    case download
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Проекты"
        case .create: return "Создать"
        case .download: return "Скачать"
        case .archive: return "Архив"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: return "folder"
        case .create: return "plus.square.on.square"
        case .download: return "arrow.down.circle"
        case .archive: return "archivebox"
        }
    }
}

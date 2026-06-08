import Foundation

/// Единый источник истины о папках проекта.
///
/// Здесь описаны канонические подпапки проекта, их семантика для
/// drag-and-drop сортировки ([[FileClassifier]]) и поведение при консервации
/// ([[ProjectArchiver]]): какие папки «тяжёлые» (удаляются и перекачиваются),
/// а какие «ценные» (уходят в архив на iCloud).
enum ProjectFolder: String, CaseIterable, Identifiable {
    case footage = "FOOTAGE"
    case readyVideo = "READY VIDEO"
    case music = "MUSIC"
    case voice = "VOICE"
    case broll = "B-ROLL"
    case subs = "SUBS"
    case misc = "MISC"

    var id: String { rawValue }

    /// Имя папки на диске.
    var folderName: String { rawValue }

    /// «Тяжёлая» папка — её содержимое легко перекачать заново, поэтому
    /// при консервации она удаляется локально и не уходит в архив.
    var isHeavy: Bool {
        switch self {
        case .footage:
            return true
        case .readyVideo, .music, .voice, .broll, .subs, .misc:
            return false
        }
    }

    /// «Ценная» папка — её содержимое трудно найти заново
    /// (музыка, войсы, броллы, сабы), поэтому она пакуется в архив на iCloud.
    var isValuable: Bool { !isHeavy }

    /// SF Symbol для отображения в UI.
    var systemImage: String {
        switch self {
        case .footage: return "film"
        case .readyVideo: return "checkmark.rectangle.stack"
        case .music: return "music.note"
        case .voice: return "mic"
        case .broll: return "sparkles.tv"
        case .subs: return "captions.bubble"
        case .misc: return "shippingbox"
        }
    }
}

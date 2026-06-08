import Foundation

/// Единый источник истины о папках проекта.
///
/// Здесь описаны канонические подпапки проекта, их семантика для
/// drag-and-drop сортировки ([[FileClassifier]]) и поведение при консервации
/// ([[ProjectArchiver]]): какие папки «тяжёлые» (по умолчанию удаляются и
/// перекачиваются), а какие «ценные» (уходят в архив на iCloud).
///
/// При консервации пользователь может переопределить, что именно удалять
/// для конкретного проекта — см. `removableOnArchive`.
enum ProjectFolder: String, CaseIterable, Identifiable {
    case footage = "FOOTAGE"
    case readyVideo = "READY VIDEO"
    case music = "MUSIC"
    case voice = "VOICE"
    case broll = "B-ROLL"
    case sfx = "SFX"
    case subs = "SUBS"
    case misc = "MISC"

    var id: String { rawValue }

    /// Имя папки на диске.
    var folderName: String { rawValue }

    /// «Тяжёлая» папка — её содержимое легко перекачать заново, поэтому
    /// при консервации её МОЖНО удалить локально (и она не уходит в архив).
    /// FOOTAGE и READY VIDEO — тяжёлые (исходники и финальные рендеры).
    var isHeavy: Bool {
        switch self {
        case .footage, .readyVideo:
            return true
        case .music, .voice, .broll, .sfx, .subs, .misc:
            return false
        }
    }

    /// «Ценная» папка — её содержимое трудно найти заново
    /// (музыка, войсы, броллы, sfx, сабы), поэтому она всегда пакуется в архив.
    var isValuable: Bool { !isHeavy }

    /// Тяжёлые папки, которые предлагается удалить при консервации.
    /// Пользователь выбирает подмножество для конкретного проекта.
    static var removableOnArchive: [ProjectFolder] {
        allCases.filter(\.isHeavy)
    }

    /// SF Symbol для отображения в UI.
    var systemImage: String {
        switch self {
        case .footage: return "film"
        case .readyVideo: return "checkmark.rectangle.stack"
        case .music: return "music.note"
        case .voice: return "mic"
        case .broll: return "sparkles.tv"
        case .sfx: return "waveform"
        case .subs: return "captions.bubble"
        case .misc: return "shippingbox"
        }
    }
}

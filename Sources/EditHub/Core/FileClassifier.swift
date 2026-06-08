import Foundation

/// Классификатор: определяет, в какую папку проекта положить файл.
///
/// Сначала смотрит на расширение, затем уточняет по ключевым словам
/// в имени файла и в имени папки-источника. Используется при
/// drag-and-drop ([[DropTargetView]]) и после скачивания.
enum FileClassifier {
    // MARK: - Extension sets

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "mxf", "avi", "mkv", "m4v", "mts", "m2ts", "wmv", "flv", "webm", "prores", "braw", "r3d"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "opus", "wma"
    ]
    private static let subtitleExtensions: Set<String> = [
        "srt", "vtt", "ass", "ssa", "sub", "sbv"
    ]

    // MARK: - Keyword sets (имя файла / папка-источник)

    private static let voiceKeywords = [
        "voice", "vo_", "_vo", "vox", "dub", "narration", "narr", "speech",
        "войс", "голос", "озвуч", "диктор", "говор"
    ]
    private static let musicKeywords = [
        "music", "track", "bgm", "song", "beat", "soundtrack", "ost", "score",
        "музык", "трек", "бит", "песн"
    ]
    private static let brollKeywords = [
        "broll", "b-roll", "b_roll", "cutaway", "бролл"
    ]
    private static let sfxKeywords = [
        "sfx", "fx_", "_fx", "foley", "sound", "whoosh", "transition", "riser", "impact",
        "звук", "эффект", "шум"
    ]

    /// Определить целевую папку для файла.
    /// - Parameters:
    ///   - fileName: имя файла (с расширением).
    ///   - sourceFolderName: имя папки, из которой перетащили (опционально).
    static func classify(fileName: String, sourceFolderName: String? = nil) -> ProjectFolder {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let haystack = (fileName + " " + (sourceFolderName ?? "")).lowercased()

        if subtitleExtensions.contains(ext) {
            return .subs
        }

        if videoExtensions.contains(ext) {
            // Видео-файлы: по умолчанию футаж, но «broll» уводит в B-ROLL.
            if matches(haystack, brollKeywords) { return .broll }
            return .footage
        }

        if audioExtensions.contains(ext) {
            // Аудио различаем только по ключевым словам.
            if matches(haystack, voiceKeywords) { return .voice }
            if matches(haystack, sfxKeywords) { return .misc }
            if matches(haystack, musicKeywords) { return .music }
            // Без явных маркеров — по умолчанию музыка.
            return .music
        }

        // Изображения / прочее.
        return .misc
    }

    private static func matches(_ haystack: String, _ keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }
}

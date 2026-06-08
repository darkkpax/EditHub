import Foundation

/// Один проект монтажа на диске: `<КОРЕНЬ>/<ГОД>/<МЕСЯЦ>/<ИМЯ>/`.
///
/// Сканируется с диска через [[ProjectStore]]. Признак консервации
/// определяется наличием файла-манифеста `<ИМЯ>.edithub` (см. [[ProjectArchiver]]).
struct Project: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let year: String
    let month: String
    let createdAt: Date
    /// Проект законсервирован — тяжёлые папки удалены, ценное в архиве iCloud.
    let isArchived: Bool

    init(url: URL, year: String, month: String, createdAt: Date, isArchived: Bool) {
        self.id = url
        self.name = url.lastPathComponent
        self.url = url
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    /// URL подпапки проекта (например FOOTAGE).
    func folderURL(_ folder: ProjectFolder) -> URL {
        url.appendingPathComponent(folder.folderName, isDirectory: true)
    }

    /// Путь к файлу-манифесту консервации.
    var manifestURL: URL {
        url.appendingPathComponent("\(name).edithub")
    }
}

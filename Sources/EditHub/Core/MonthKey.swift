import Foundation

/// Канонический ключ месяца — номер `1...12`.
///
/// На диске месяц может быть записан по-разному в зависимости от того, кто и
/// когда создал папку: `OCTOBER` (текущий код, `.uppercased()`), `October`
/// (старые архивы в iCloud), `Октябрь`/`ОКТЯБРЬ` (совсем старые), либо числом.
/// Сравнивать такие строки напрямую нельзя — `October != OCTOBER`, и один и тот
/// же месяц двоится. Поэтому везде, где месяцы группируются, мёрджатся или
/// дедуплицируются, ключом служит номер, а не строка.
///
/// Отображение остаётся за UI; здесь только нормализация.
enum MonthKey {
    /// Английские названия месяцев (POSIX), индекс = номер - 1.
    private static let english = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]

    /// Русские названия месяцев в именительном падеже, индекс = номер - 1.
    private static let russian = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]

    /// Разобрать строку месяца в номер `1...12`. Принимает английское или
    /// русское название в любом регистре, либо число (`10`, `06`, `6`).
    /// Возвращает `nil`, если распознать не удалось.
    static func number(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Число: "10", "06", "6".
        if let n = Int(trimmed), (1...12).contains(n) {
            return n
        }

        let lower = trimmed.lowercased()
        if let idx = english.firstIndex(of: lower) {
            return idx + 1
        }
        if let idx = russian.firstIndex(of: lower) {
            return idx + 1
        }
        return nil
    }

    /// Стабильный строковый ключ для группировки/дедупликации: двузначный
    /// номер (`"01"..."12"`). Если месяц не распознан — возвращаем исходную
    /// строку в верхнем регистре, чтобы такие папки хотя бы не схлопывались
    /// в одну и оставались видимыми.
    static func canonical(_ raw: String) -> String {
        guard let n = number(from: raw) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return String(format: "%02d", n)
    }
}

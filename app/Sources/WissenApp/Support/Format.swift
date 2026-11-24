import Foundation

enum Format {
    /// The interface is English, so dates and numbers are formatted to match – whatever the system language.
    static let locale = Locale(identifier: "en_US")
    /// Whole numbers with English grouping: 3,314.
    static let integer = IntegerFormatStyle<Int>.number.locale(locale)

    private static let isoWithZone: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoLocal: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Format.locale
        f.unitsStyle = .full
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoWithZone.date(from: s) ?? isoLocal.date(from: String(s.prefix(19)))
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "–" }
        if abs(date.timeIntervalSinceNow) < 10 { return "just now" }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    private static let shortRel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Format.locale
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Short for tables: “5 hr. ago”
    static func shortRelative(_ date: Date?) -> String {
        guard let date else { return "–" }
        if abs(date.timeIntervalSinceNow) < 60 { return "now" }
        return shortRel.localizedString(for: date, relativeTo: .now)
    }

    static func bytes(_ n: Int64) -> String {
        n.formatted(.byteCount(style: .memory).locale(locale))
    }

    /// Size on disk as Finder shows it (1 GB = 1000 MB).
    static func fileSize(_ n: Int64) -> String {
        n.formatted(.byteCount(style: .file).locale(locale))
    }

    static func number(_ x: Double, digits: Int = 1) -> String {
        x.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    static func duration(ms: Double) -> String {
        ms >= 1000 ? "\(number(ms / 1000)) s" : "\(Int(ms)) ms"
    }
}

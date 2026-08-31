//
//  AppFormat.swift
//  FeedbackHubViewer
//
//  Date and number formatting for the UI. The interface is written in Korean,
//  so dates are formatted in Korean too rather than following the device locale
//  — otherwise a Korean label ends up next to "3 weeks ago".
//

import Foundation

enum AppFormat {
    static let locale = Locale(identifier: "ko_KR")

    /// "2026. 8. 15. 오후 6:16"
    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// "오후 6:16"
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "3주 전"
    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// "1,240" — a running record count, grouped so a five-digit number is
    /// readable at a glance in the status line.
    static func count(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "+12" / "−3" / "±0" — a change, always carrying its sign. A bare "3"
    /// beside last week's number reads as a total, not a difference, which is
    /// why every delta on screen goes through here.
    ///
    /// The minus is the typographic one (U+2212), which lines up with the digits
    /// where a hyphen sits high and short.
    static func signed(_ value: Int) -> String {
        if value == 0 { return "±0" }
        return value > 0 ? "+\(value)" : "−\(-value)"
    }

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .short
        return f
    }()
}

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

    /// "9월 2일" — 차트가 가리킨 하루. 연도는 뺀다: 축이 이미 어느 해인지 말하고
    /// 있고, 값 패널은 짧을수록 선을 덜 가린다.
    static func chartDay(_ date: Date) -> String {
        chartDayFormatter.string(from: date)
    }

    /// "2026년 9월" — 달·해 단위 버킷을 가리킬 때.
    static func chartMonth(_ date: Date) -> String {
        chartMonthFormatter.string(from: date)
    }

    static func chartYear(_ date: Date) -> String {
        chartYearFormatter.string(from: date)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let chartDayFormatter = formatter("Md")
    private static let chartMonthFormatter = formatter("yMMM")
    private static let chartYearFormatter = formatter("y")

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

//
//  KeywordHistory+Trend.swift
//  FeedbackHubViewer
//
//  순위의 긴 추이와, 그 사이에 일어난 일.
//
//  줄마다 붙은 30일 스파크라인은 "오르는 중인가"에는 답하지만 "무슨 일이 있었나"에는
//  답하지 않는다. 여기서는 일주일 전의 확인과 지금의 확인을 나란히 놓고 달라진 것을
//  말로 뽑는다 — 크게 오름 · 새로 잡힘. 떨어진 것은 알리지 않는다: 할 일은 오르는 말을
//  더 밀어 올리는 것이다.
//

import Foundation

/// 일주일 사이 한 키워드에 일어난 일.
struct RankAlert: Identifiable {
    let keyword: TrackedKeyword
    let kind: Kind
    /// 비교한 두 날(yyyy-MM-dd).
    let from: String
    let to: String

    var id: String { keyword.id + kind.tag }

    /// 오른 것만 — 떨어진 것은 알리지 않는다.
    enum Kind {
        case climbed(from: Int, to: Int)
        case entered(to: Int)

        var tag: String {
            switch self {
            case .climbed: return "climbed"
            case .entered: return "entered"
            }
        }
    }
}

extension KeywordHistory {

    /// 몇 계단부터 "크게"인가. 하루 이틀 한두 계단은 스토어가 늘 흔드는 폭이다.
    static let bigMove = 5

    /// 한 키워드의 날짜별 순위(오래된 것부터). 확인 안 한 날과 안 잡힌 날은 nil.
    func rankSeries(_ keyword: TrackedKeyword, trackId: Int, days: Int,
                    calendar: Calendar = .current, now: Date = Date()) -> [(date: Date, rank: Int?)] {
        let history = checks[keyword.id] ?? [:]
        return UsageRollups.recentDayKeys(days, calendar: calendar, endingAt: now).map {
            ($0.date, history[$0.key]?.rank(of: trackId))
        }
    }

    /// 기록이 며칠 치 있는가 — 기간 고르개가 없는 기간을 내밀지 않게.
    func recordedDays(for project: String?) -> Int {
        let keys = keywords(for: project).flatMap { (checks[$0.id] ?? [:]).keys }
        guard let first = keys.min(), let date = Self.date(fromDayKey: first) else { return 0 }
        return (Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0) + 1
    }

    /// 최근 확인과 `days`일 전(또는 그 앞의 가장 가까운) 확인을 견준 변화들.
    func rankAlerts(for project: String?, trackId: Int?, days: Int = 7,
                    calendar: Calendar = .current, now: Date = Date()) -> [RankAlert] {
        guard let trackId else { return [] }
        var alerts: [RankAlert] = []
        for keyword in keywords(for: project) {
            let history = checks[keyword.id] ?? [:]
            guard let latestKey = history.keys.max(), let latest = history[latestKey],
                  let latestDate = Self.date(fromDayKey: latestKey),
                  let baseDate = calendar.date(byAdding: .day, value: -days, to: latestDate) else { continue }
            let baseLimit = UsageRollups.dayKey(baseDate, calendar: calendar)
            guard let baseKey = history.keys.filter({ $0 <= baseLimit }).max(),
                  let base = history[baseKey] else { continue }

            let now = latest.rank(of: trackId)
            let then = base.rank(of: trackId)
            func add(_ kind: RankAlert.Kind) {
                alerts.append(RankAlert(keyword: keyword, kind: kind, from: baseKey, to: latestKey))
            }

            switch (then, now) {
            case let (then?, now?) where then - now >= Self.bigMove: add(.climbed(from: then, to: now))
            case let (nil, now?): add(.entered(to: now))
            default: break
            }
        }
        // 더 높이 올라선 것이 먼저.
        return alerts.sorted { rank($0.kind) == rank($1.kind) ? $0.keyword.term < $1.keyword.term : rank($0.kind) < rank($1.kind) }
    }

    private func rank(_ kind: RankAlert.Kind) -> Int {
        switch kind {
        case .climbed(_, let to), .entered(let to): return to
        }
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

//
//  KeywordHistory+Trend.swift
//  FeedbackHubViewer
//
//  순위의 긴 추이와, 그 사이에 일어난 일.
//
//  줄마다 붙은 30일 스파크라인은 "오르는 중인가"에는 답하지만 "무슨 일이 있었나"에는
//  답하지 않는다. 여기서는 일주일 전의 확인과 지금의 확인을 나란히 놓고 달라진 것을
//  말로 뽑는다 — 크게 떨어짐 · 크게 오름 · 순위에서 빠짐 · 새로 잡힘, 그리고 **누가 나를
//  앞질렀나**. 마지막 것은 순위만 봐서는 안 보인다: 3위에서 5위로 간 것이 내가 밀린
//  것인지 두 앱이 올라온 것인지는 결과 목록을 봐야 안다.
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

    enum Kind {
        case dropped(from: Int, to: Int)
        case climbed(from: Int, to: Int)
        case lost(from: Int)
        case entered(to: Int)
        /// 나를 새로 앞지른 앱들의 이름.
        case overtaken(by: [String], myRank: Int)

        var tag: String {
            switch self {
            case .dropped: return "dropped"
            case .climbed: return "climbed"
            case .lost: return "lost"
            case .entered: return "entered"
            case .overtaken: return "overtaken"
            }
        }

        /// 나쁜 소식인가 — 색을 고를 때만 쓴다.
        var isBad: Bool {
            switch self {
            case .dropped, .lost, .overtaken: return true
            case .climbed, .entered: return false
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
            case let (then?, now?) where now - then >= Self.bigMove: add(.dropped(from: then, to: now))
            case let (then?, now?) where then - now >= Self.bigMove: add(.climbed(from: then, to: now))
            case let (then?, nil): add(.lost(from: then))
            case let (nil, now?): add(.entered(to: now))
            default: break
            }

            // 누가 나를 앞질렀나: 지금 내 위에 있는 앱 중, 그때는 내 아래(또는 목록 밖)였던 것.
            if let now, let then {
                let aboveNow = latest.top.prefix(max(0, now - 1))
                let passed = aboveNow.filter { id in
                    guard id != trackId else { return false }
                    if let index = base.top.firstIndex(of: id) { return index + 1 > then }
                    // 그때 목록(30위) 밖이었다면, 내가 목록 안에 있었을 때만 "아래"라고 안다.
                    return then <= base.top.count
                }
                if !passed.isEmpty {
                    add(.overtaken(by: passed.map { apps[String($0)]?.name ?? "앱 \($0)" }, myRank: now))
                }
            }
        }
        // 나쁜 소식이 먼저.
        return alerts.sorted { ($0.kind.isBad ? 0 : 1, $0.keyword.term) < ($1.kind.isBad ? 0 : 1, $1.keyword.term) }
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

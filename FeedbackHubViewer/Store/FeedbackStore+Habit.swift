//
//  FeedbackStore+Habit.swift
//  FeedbackHubViewer
//
//  "제품이 사용자 생활에 얼마나 자주 들어가 있나" — 사용 주기에 맞춘 주 지표, 고착도
//  (DAU/MAU · WAU/MAU)와 그 4주 전, 그리고 L28(지난 28일 중 며칠 왔나) 분포.
//
//  모든 창은 **어제로 끝난다.** 끝나지 않은 오늘을 섞으면 아침마다 비율이 내려간다.
//  견줄 앞 창은 정확히 28일(4주) 전 — 요일이 맞아야 주말 몫이 같다.
//
//  "활동"은 `ActivityDefinition.valueEvents` 가 있으면 그 이벤트를 보낸 날만이다. 그
//  기록(`UsageDayBucket.eventInstalls`)이 창을 다 덮지 못하면, 반쪽 숫자로 판정하지 않고
//  아무 이벤트 기준으로 돌아가며 그렇다고 적는다.
//

import Foundation

extension FeedbackStore {

    // MARK: - 정의

    /// 이 앱의 정의 — 뷰어에서 고른 것, 없으면 스펙, 없으면 빈 것.
    func activityDefinition(for project: String?) -> ActivityDefinition {
        guard let project else { return ActivityDefinition() }
        if let chosen = activityOverrides[project] { return chosen }
        return ProjectStatsSpecCatalog.spec(for: project)?.activity ?? ActivityDefinition()
    }

    /// 사용 주기. 안 정했으면 nil.
    func usageCycle(for project: String) -> UsageCycle? {
        activityDefinition(for: project).cycle
    }

    func setActivityDefinition(_ definition: ActivityDefinition, for project: String) {
        activityOverrides[project] = definition
    }

    // MARK: - 계산

    struct Habit {
        let cycle: UsageCycle?
        /// 실제로 쓴 가치 행동. 기록이 모자라 아무 이벤트로 돌아갔으면 비어 있다.
        let valueEvents: [String]
        /// 가치 행동을 골랐지만 기록이 창을 못 덮어 아무 이벤트로 셌다.
        let fellBackToAnyEvent: Bool
        /// 가치 행동 기록이 시작된 날.
        let valueSince: Date?

        /// 지난 30일(어제까지)의 하루 평균 · 7일 · 30일 활동.
        let dauAverage: Double
        let wau: Int
        let mau: Int
        /// 28일 전 같은 창.
        let previousDauAverage: Double
        let previousWau: Int
        let previousMAU: Int

        /// L28 — 지난 28일 중 n일 온 사람 수(인덱스 0 이 1일). 그리고 그 앞 28일.
        let curve: [Int]
        let previousCurve: [Int]

        var isEmpty: Bool { mau == 0 && previousMAU == 0 }

        var dauOverMau: Double? { mau > 0 ? dauAverage / Double(mau) : nil }
        var wauOverMau: Double? { mau > 0 ? Double(wau) / Double(mau) : nil }
        var previousDauOverMau: Double? { previousMAU > 0 ? previousDauAverage / Double(previousMAU) : nil }
        var previousWauOverMau: Double? { previousMAU > 0 ? Double(previousWau) / Double(previousMAU) : nil }

        /// 이 주기의 주 비율과 그 4주 전. 가끔 쓰는 앱은 비율이 주 지표가 아니라 nil.
        var mainRatio: (name: String, now: Double?, before: Double?)? {
            switch cycle {
            case .daily: ("DAU/MAU", dauOverMau, previousDauOverMau)
            case .weekly: ("WAU/MAU", wauOverMau, previousWauOverMau)
            case .occasional, nil: nil
            }
        }

        /// 이 주기의 주 지표(지금, 4주 전).
        var mainMetric: (now: Int, before: Int) {
            switch cycle {
            case .daily: (Int(dauAverage.rounded()), Int(previousDauAverage.rounded()))
            case .weekly: (wau, previousWau)
            case .occasional, nil: (mau, previousMAU)
            }
        }

        /// 오른쪽 끝 — "거의 매일" 오는 사람. 매일 쓰는 앱은 15일 이상, 매주 쓰는 앱은
        /// 매주(대략 4일 이상)를 문턱으로 본다. 가끔 쓰는 앱은 이 끝이 뜻이 없다.
        var tailThreshold: Int? {
            switch cycle {
            case .daily: 15
            case .weekly: 4
            case .occasional, nil: nil
            }
        }

        func tailShare(_ curve: [Int]) -> Double? {
            guard let threshold = tailThreshold else { return nil }
            let total = curve.reduce(0, +)
            guard total > 0 else { return nil }
            return Double(curve.dropFirst(threshold - 1).reduce(0, +)) / Double(total)
        }

        /// 규모가 작으면(MAU 1,000 미만) DAU 계열은 출시 · 피처링 하나에 크게 흔들린다.
        var isSmall: Bool { mau < 1_000 }
    }

    func habit(for project: String?, audience: Audience = .all,
               calendar: Calendar = .current) -> Habit {
        memoized(\.habit, ScopeKey(project: project, audience: audience)) {
            let definition = activityDefinition(for: project)
            let days = self.days(for: project, audience: audience)

            // 가치 행동 기록이 지금 창과 앞 창(어제부터 58일 전까지)을 다 덮나.
            let needed = UsageRollups.windowKeys(days: 30 + 28, endingDaysAgo: 1, calendar: calendar)
            let tracked = days.filter { $0.value.eventInstalls != nil }.keys.sorted()
            let valueSince = tracked.first.flatMap { UsageRollups.date(fromDayKey: $0, calendar: calendar) }
            let covers = needed.first.map { first in tracked.first.map { $0 <= first } ?? false } ?? false
            let useValue = !definition.valueEvents.isEmpty && covers
            let values = Set(definition.valueEvents)

            func active(_ key: String) -> Set<String> {
                guard let bucket = days[key] else { return [] }
                guard useValue else { return bucket.installs }
                var ids: Set<String> = []
                for (name, set) in bucket.eventInstalls ?? [:] where values.contains(name) { ids.formUnion(set) }
                return ids
            }

            func distinct(_ length: Int, endingDaysAgo offset: Int) -> Int {
                var ids: Set<String> = []
                for key in UsageRollups.windowKeys(days: length, endingDaysAgo: offset, calendar: calendar) {
                    ids.formUnion(active(key))
                }
                return ids.count
            }

            func averageDaily(endingDaysAgo offset: Int) -> Double {
                let keys = UsageRollups.windowKeys(days: 30, endingDaysAgo: offset, calendar: calendar)
                return Double(keys.reduce(0) { $0 + active($1).count }) / Double(keys.count)
            }

            func curve(endingDaysAgo offset: Int) -> [Int] {
                var counts: [String: Int] = [:]
                for key in UsageRollups.windowKeys(days: 28, endingDaysAgo: offset, calendar: calendar) {
                    for id in active(key) { counts[id, default: 0] += 1 }
                }
                var buckets = Array(repeating: 0, count: 28)
                for n in counts.values { buckets[min(n, 28) - 1] += 1 }
                return buckets
            }

            return Habit(cycle: definition.cycle,
                         valueEvents: useValue ? definition.valueEvents : [],
                         fellBackToAnyEvent: !definition.valueEvents.isEmpty && !useValue,
                         valueSince: valueSince,
                         dauAverage: averageDaily(endingDaysAgo: 1),
                         wau: distinct(7, endingDaysAgo: 1),
                         mau: distinct(30, endingDaysAgo: 1),
                         previousDauAverage: averageDaily(endingDaysAgo: 29),
                         previousWau: distinct(7, endingDaysAgo: 29),
                         previousMAU: distinct(30, endingDaysAgo: 29),
                         curve: curve(endingDaysAgo: 1),
                         previousCurve: curve(endingDaysAgo: 29))
        }
    }

    /// 가치 행동으로 고를 수 있는 이벤트 — 이 앱이 보낸 적 있는 이름(슬라이스 앞부분), 많이 보낸 것부터.
    func valueEventCandidates(for project: String) -> [(name: String, count: Int)] {
        var totals: [String: Int] = [:]
        for (name, total) in eventTallies(for: project, audience: .all) {
            totals[ProjectStatsSpec.eventBase(name), default: 0] += total.count
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }
}

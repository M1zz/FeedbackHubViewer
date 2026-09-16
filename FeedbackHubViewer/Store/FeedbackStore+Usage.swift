//
//  FeedbackStore+Usage.swift
//  FeedbackHubViewer
//
//  Aggregation over the usage records the apps report. Every number here is
//  computed the same way the apps' own statistics screens compute it
//  (ClipKeyboard's `UsageStatsView` / `UsageReportingService`), so the hub and
//  the app agree:
//
//   - 설치 수        = number of UsageSnapshot records (one per install)
//   - 최근 N일 활성   = snapshots whose `lastActiveAt` falls in the window
//   - 최근 N일 신규   = snapshots whose `installDate` falls in the window
//   - 활동한 사용자   = distinct `installID` among events in the bucket
//   - 사용 건수       = number of events in the bucket, by `occurredAt`
//
//  Nothing here interprets an app's own vocabulary: event names and `metrics`
//  keys are passed through as the app sent them.
//
//  Where the numbers come from: anything counted per *install* is read from the
//  `UsageSnapshot` records, which are re-read whole on every refresh and are
//  bounded by how many installs an app has. Anything counted per *event* is
//  read from `UsageRollups` — the day buckets each event was summed into when
//  it first arrived — and never from the raw stream, which is unbounded. The
//  raw events this device still holds back only the 사용 내역 list, which shows
//  events one at a time and so genuinely needs them.
//
//  One consequence worth knowing: an event-based "최근 7일" is seven whole days
//  (today and the six before it), not a rolling `now − 7 × 86,400`. Snapshot-
//  based windows (`active7`, `new7`) are still rolling, because a snapshot
//  carries its own timestamp rather than living in a bucket.
//

import Foundation

extension FeedbackStore {

    // MARK: - Types

    /// One project's usage numbers, with the previous week for comparison.
    struct ProjectUsage: Identifiable {
        var id: String { project }
        /// Grouping key (appId, or appName when there is no appId).
        let project: String
        let displayName: String
        /// 어느 무리의 숫자인가. 전체가 아니면 아래 **건수**들은 0이다 —
        /// 건수는 설치별로 나뉘어 있지 않아 무리로 가를 수 없다
        /// (`FeedbackStore+Audience.swift` 머리말).
        var audience: Audience = .all

        let installs: Int
        /// Snapshot-based activity, exactly as the apps report it.
        let active7: Int
        let active30: Int
        let new7: Int
        let previousNew7: Int
        let totalLaunches: Int
        /// Significant actions the apps counted locally (`eventCount`).
        let totalSignificantEvents: Int

        /// Event-based activity — the only definition that has history, so it
        /// is what the deltas and the trend chart use.
        let activeInstalls7: Int
        let previousActiveInstalls7: Int
        let events7: Int
        let previousEvents7: Int
        let totalEvents: Int

        let lastActiveAt: Date?
        /// Daily event counts for the last 14 days (oldest first).
        let sparkline: [FeedbackStore.DayCount]

        var hasUsageData: Bool { installs > 0 || totalEvents > 0 }
        /// 건수를 말할 수 있는가. 무리를 고른 동안은 사람·설치 수만 참이다.
        var hasEventCounts: Bool { !audience.isFiltered }
        var activeInstallsDelta: Int { activeInstalls7 - previousActiveInstalls7 }
        var eventsDelta: Int { events7 - previousEvents7 }
        var newDelta: Int { new7 - previousNew7 }
    }

    /// One event name, aggregated. Mirrors `UsageReportingService.EventStat`.
    struct EventStat: Identifiable {
        var id: String { name }
        /// The name as the app sent it, slice included ("paywall_view:memo").
        let name: String
        /// 몇 번 일어났는가. 무리를 골라 본 동안은 **nil**이다 — 건수는 설치별로
        /// 나뉘어 있지 않아 유료·무료로 가를 수 없다. 0으로 두지 않는 이유는
        /// "아무도 안 했다"와 "셀 수 없다"가 다른 말이기 때문이다.
        let count: Int?
        /// How many distinct installs produced it.
        let installs: Int
        let lastAt: Date?
    }

    /// A numeric `metrics` key, averaged over the installs that reported it.
    struct MetricAverage: Identifiable {
        var id: String { key }
        let key: String
        let average: Double
        let total: Double
        /// Installs that reported this key at all.
        let samples: Int
    }

    /// A 0/1 `metrics` flag (`flag.*`, `persona.*`) as a share of installs.
    struct FlagShare: Identifiable {
        var id: String { key }
        let key: String
        let count: Int
        let ratio: Double
    }

    /// A "how many installs are on X" bucket (version, platform, OS, locale).
    struct DistributionBucket: Identifiable {
        var id: String { key }
        let key: String
        let count: Int
    }

    /// One project's MetricKit diagnostics, rolled up.
    struct CrashSummary {
        let total: Int
        let last7Days: Int
        let previous7Days: Int
        /// Counts by `kind` ("crash" / "hang" / "disk_write"), most first.
        let byKind: [(kind: String, label: String, count: Int)]
        /// Counts by app version, most first.
        let byVersion: [DistributionBucket]
        /// Newest first, for the recent list.
        let recent: [CrashReport]
        let lastAt: Date?

        var isEmpty: Bool { total == 0 }
        var delta: Int { last7Days - previous7Days }
    }

    /// Chart bucket, same units the apps offer.
    enum TrendUnit: String, CaseIterable, Identifiable {
        case day, week, month, year
        var id: String { rawValue }

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }

        /// The rung of `UsageRollups` this unit reads.
        var granularity: UsageRollups.Granularity {
            switch self {
            case .day: return .day
            case .week: return .week
            case .month: return .month
            case .year: return .year
            }
        }

        var label: String {
            switch self {
            case .day: return "일간"
            case .week: return "주간"
            case .month: return "월간"
            case .year: return "연간"
            }
        }
    }

    /// One bucket of the trend chart.
    struct TrendPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let events: Int
        let activeInstalls: Int
        let newInstalls: Int
    }

    /// 일간·주간·월간 활성 사용자 — DAU · WAU · MAU.
    ///
    /// 셋은 다른 지표가 아니라 **같은 것을 재는 세 가지 창**이다: 그 창 안에서
    /// 이벤트를 보낸 서로 다른 `installID`의 수. 창이 서로 겹치므로 세 숫자는
    /// 절대 더하면 안 되고(오늘 쓴 사람은 이번 주에도 이번 달에도 들어 있다),
    /// 창 안에서도 합이 아니라 언제나 합집합이다 — 월·화 이틀 쓴 설치는 두 명이
    /// 아니라 한 명이다.
    ///
    /// 화면 위쪽 타일의 "최근 7일 활성"과 이름이 닮았지만 출처가 다르다. 그쪽은
    /// 스냅샷의 `lastActiveAt`, 즉 설치가 스스로 적어 보낸 마지막 활동 시각이고,
    /// 여기 WAU는 실제로 도착한 이벤트다. 이벤트를 보내지 않는 앱은 여기서 0으로
    /// 나오는 것이 맞다.
    struct ActiveUsers {

        /// 창 하나의 길이.
        ///
        /// 월간이 달력의 달이 아니라 30일 고정인 이유: 창끼리 비교하려면 길이가
        /// 같아야 한다. 2월 MAU와 3월 MAU가 다르게 나오면 그건 사용자가 아니라
        /// 날짜 수가 달라진 것이고, 그런 변화는 읽는 사람을 속인다.
        enum Span: String, CaseIterable, Identifiable {
            case day, week, month

            var id: String { rawValue }

            var days: Int {
                switch self {
                case .day: return 1
                case .week: return 7
                case .month: return 30
                }
            }

            var label: String {
                switch self {
                case .day: return "일간 (DAU)"
                case .week: return "주간 (WAU)"
                case .month: return "월간 (MAU)"
                }
            }

            /// 바로 앞의 같은 길이 창을 부르는 말 — 숫자 밑에 붙는다.
            var previousLabel: String {
                switch self {
                case .day: return "어제"
                case .week: return "지난 7일"
                case .month: return "지난 30일"
                }
            }
        }

        /// 한 창의 지금 값과, 바로 앞의 같은 길이 창.
        struct Window: Identifiable {
            let span: Span
            let current: Int
            let previous: Int

            var id: String { span.id }
            var delta: Int { current - previous }
        }

        let day: Window
        let week: Window
        let month: Window

        /// 하루씩 물러나며 같은 세 창을 다시 잰 값(오래된 것부터). 오늘 하루의
        /// 숫자만으로는 오르는 중인지 내리는 중인지 알 수 없다.
        let series: [Point]

        struct Point: Identifiable {
            var id: Date { date }
            let date: Date
            let day: Int
            let week: Int
            let month: Int
        }

        var windows: [Window] { [day, week, month] }

        /// 하루 평균 DAU — 오늘을 뺀, 지나간 날들만.
        ///
        /// 오늘은 아직 끝나지 않은 하루라 이른 아침이면 0이다. 그 0을 고착도에
        /// 넣으면 "이 앱은 아무도 안 쓴다"가 되는데, 그건 앱이 아니라 시계가 하는
        /// 말이다. 그래서 비율의 분자는 오늘 하루가 아니라 지나간 날들의 평균이다.
        var averageDay: Double? {
            let past = series.dropLast().map(\.day)
            guard !past.isEmpty else { return nil }
            return Double(past.reduce(0, +)) / Double(past.count)
        }

        /// 고착도 — 평균 DAU ÷ MAU. 한 달에 한 번 열어 보는 앱과 매일 여는 앱을
        /// 가르는 한 숫자다. 0.2면 한 달 안에 쓴 사람이 30일 중 평균 6일 썼다는 뜻.
        var stickiness: Double? {
            guard month.current > 0, let averageDay else { return nil }
            return averageDay / Double(month.current)
        }

        /// 30일 창에도 그 앞 30일에도 아무도 없으면 보여 줄 것이 없다.
        var isEmpty: Bool { month.current == 0 && month.previous == 0 }

        /// 추이를 며칠 치 그리는가. 가장 왼쪽 점의 30일 창도 온전히 채워져야 하므로
        /// 실제로 읽는 과거는 이보다 29일 더 길다.
        static let trendDays = 30
    }

    /// 유료 기능을 쓸 수 있는 설치와 무료 기능만 쓰는 설치, 그리고 그중 지금
    /// 살아 있는 사람.
    ///
    /// **왜 "결제"가 아니라 "쓸 수 있는가"가 이 카드의 숫자인가.** 허브는 결제
    /// 영수증을 받지 않는다. 아는 것은 앱이 스냅샷에 실어 보낸 0/1 플래그뿐인데,
    /// 그 플래그가 실제로 재고 있는 값은 거의 언제나 "지금 기능이 열려 있는가"다 —
    /// `flag.isPro`라는 이름이 붙어 있어도 그렇다. 그걸 결제로 읽으면 신규 설치의
    /// 99%가 유료가 되고(실제로 그랬다), 결제만 물으면 8,201대 중 5,726대가 모름이
    /// 된다. 쓸 수 있는가로 읽으면 둘 다 아니다: 참이면서, 모름이 52대(0.6%)뿐이다.
    ///
    /// 활성의 정의는 바로 위 타일(`최근 7일 활성`)과 **같은 것**을 쓴다. 스냅샷의
    /// `lastActiveAt`이다. 이벤트 기반(DAU·WAU·MAU)이 아니라 이쪽인 이유: 권한이
    /// 스냅샷에 있으므로 같은 레코드에서 두 값을 함께 읽으면 짝이 안 맞는 설치가
    /// 없다. 덕분에 `유료기능 + 무료기능 + 모름`은 언제나 그 타일의 숫자와 정확히
    /// 같다 — **모름까지 세어야** 같아진다는 점이 중요하다.
    struct AccessSplit {
        /// 한 창(전체 / 최근 7일 / 최근 30일)에서 갈린 수.
        /// 셋은 서로 겹치지 않아 더하면 `scanned`가 된다.
        struct Slice {
            let paidFeatures: Int
            let freeFeatures: Int
            /// 권한을 말해 주는 키를 하나도 안 보낸 설치 —
            /// 무료기능이 **아니라** 모름.
            let unknown: Int

            /// 갈린 설치.
            var total: Int { paidFeatures + freeFeatures }
            /// 이 창의 설치 전부 — 갈린 것 + 모름.
            var scanned: Int { total + unknown }
            /// 갈린 것이 이 창의 몇 할인가.
            var coverage: Double? {
                guard scanned > 0 else { return nil }
                return Double(total) / Double(scanned)
            }

            /// 갈린 설치가 이 창의 절반에도 못 미치는가.
            ///
            /// 그러면 **비중을 말하지 않는다.** 권한을 보내는 설치가 소수인 앱에서
            /// 그 소수는 "먼저 업데이트한 사람들"이지 무작위 표본이 아니다. 갈린
            /// 것이 하나도 없는 창(`total == 0`)도 여기 든다 — "유료기능 0명 ·
            /// 무료기능 0명"만 적어 두면 아무도 없는 것으로 읽히지, 아무도 안 보낸
            /// 것으로는 안 읽힌다.
            var isTooThin: Bool { unknown > 0 && (coverage ?? 1) < 0.5 }

            /// 유료 기능을 쓸 수 있는 사람의 비중 — 이 카드의 큰 숫자.
            var ratio: Double? {
                guard total > 0, !isTooThin else { return nil }
                return Double(paidFeatures) / Double(total)
            }

            func count(for audience: Audience) -> Int {
                switch audience {
                case .all:          return scanned
                case .paidFeatures: return paidFeatures
                case .freeFeatures: return freeFeatures
                }
            }
        }

        /// 이 값을 만든 앱과 그 앱에서 권한을 읽은 키. 전체 프로젝트에서는
        /// 앱마다 키가 다르므로 여럿이 된다.
        struct Source {
            let project: String
            let displayName: String
            let key: String
            /// 스펙이 그 키에 붙인 이름("Pro 사용자"). 없으면 키 원문을 쓴다.
            let label: String?
            /// 스펙이 직접 지정한 키인가, 규약·이름으로 찾아낸 것인가.
            let isDeclared: Bool
        }

        let sources: [Source]
        let all: Slice
        let active7: Slice
        let active30: Slice

        /// 권한을 읽을 수 있는 앱이 하나도 없으면 보여 줄 것이 없다.
        var isEmpty: Bool { sources.isEmpty || all.scanned == 0 }
        /// 이름만 보고 고른 키가 하나라도 섞여 있으면 화면에서 그렇다고 말해야 한다.
        var hasGuessedKey: Bool { sources.contains { !$0.isDeclared } }
    }

    // MARK: - Cache keys

    /// 한 화면분의 범위 — 어느 프로젝트를, 어느 무리로 보고 있는가.
    /// `project == nil`은 전체 프로젝트, `audience == .all`은 전체 사용자다.
    struct ScopeKey: Hashable {
        let project: String?
        let audience: Audience
    }

    /// What `distribution(for:by:)` was asked for. The keypath identifies the
    /// snapshot field, so the four distributions on the stats screen each get
    /// their own entry.
    struct DistributionKey: Hashable {
        let project: String?
        let audience: Audience
        let field: KeyPath<UsageSnapshot, String>
    }

    /// What `trend(for:unit:calendar:)` was asked for.
    struct TrendKey: Hashable {
        let project: String?
        let audience: Audience
        let unit: TrendUnit
        let calendar: Calendar
    }

    /// What `carryingCapacity(for:period:)` was asked for.
    struct CapacityKey: Hashable {
        let project: String?
        let audience: Audience
        let period: CarryingCapacity.Period
    }

    // MARK: - Scoping

    /// Every project key that appears anywhere — feedback, usage, or a crash.
    /// An app can report under an id that never shows up in feedback.
    var allProjectKeys: [String] {
        memoized(\.projectKeys) {
            var keys = Set(allFeedback.map(\.projectKey))
            keys.formUnion(allSnapshots.map(\.projectKey))
            // From the rollups, not the raw events: an app whose events have all
            // aged out of the retained window is still an app of yours, and its
            // history is still on file.
            keys.formUnion(rollups.projectKeys.subtracting(hiddenProjects))
            keys.formUnion(allCrashes.map(\.projectKey))
            let installs = snapshotsByProject.mapValues(\.count)
            return keys.sorted { lhs, rhs in
                if lhs == Feedback.unclassifiedProject { return false }
                if rhs == Feedback.unclassifiedProject { return true }
                let l = installs[lhs] ?? 0, r = installs[rhs] ?? 0
                if l != r { return l > r }
                return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
            }
        }
    }

    var hasUsageData: Bool { !allSnapshots.isEmpty || !rollups.isEmpty }

    // MARK: - Per-project rollup

    /// Usage for every project that reported any, most installs first.
    var projectUsages: [ProjectUsage] {
        allProjectKeys
            .map { usage(for: $0) }
            .filter(\.hasUsageData)
    }

    var overallUsage: ProjectUsage { usage(for: nil) }

    func usage(for project: String?, audience: Audience = .all) -> ProjectUsage {
        memoized(\.usage, ScopeKey(project: project, audience: audience)) {
        let snaps = snapshots(for: project, audience: audience)
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)

        // The event side of this comes from the day buckets, so it stays
        // correct however far back the hub goes and costs nothing to read.
        let days = self.days(for: project, audience: audience)
        let thisWeek = UsageRollups.window(days, keys: UsageRollups.windowKeys(days: 7))
        let lastWeek = UsageRollups.window(days, keys: UsageRollups.windowKeys(days: 7, endingDaysAgo: 7))
        let totalEvents = days.values.reduce(0) { $0 + $1.events }

        let value = ProjectUsage(
            project: project ?? "",
            displayName: project.map { displayName(for: $0) } ?? "전체 프로젝트",
            audience: audience,
            installs: snaps.count,
            active7: snaps.filter { ($0.lastActiveAt ?? .distantPast) >= weekAgo }.count,
            active30: snaps.filter { ($0.lastActiveAt ?? .distantPast) >= monthAgo }.count,
            new7: snaps.filter { ($0.installDate ?? .distantPast) >= weekAgo }.count,
            previousNew7: snaps.filter {
                guard let installed = $0.installDate else { return false }
                return installed >= twoWeeksAgo && installed < weekAgo
            }.count,
            totalLaunches: snaps.reduce(0) { $0 + $1.launchCount },
            totalSignificantEvents: snaps.reduce(0) { $0 + $1.eventCount },
            activeInstalls7: thisWeek.installs,
            previousActiveInstalls7: lastWeek.installs,
            events7: thisWeek.events,
            previousEvents7: lastWeek.events,
            totalEvents: totalEvents,
            lastActiveAt: snaps.compactMap(\.lastActiveAt).max(),
            sparkline: UsageRollups.recentDayKeys(14).map {
                DayCount(date: $0.date, count: days[$0.key]?.events ?? 0)
            }
        )
        return value
        }
    }

    /// 일간·주간·월간 활성 사용자(DAU · WAU · MAU).
    ///
    /// 일 버킷이 이미 그날의 `installID` 집합을 들고 있으므로 창 하나는 집합
    /// 합집합 한 번이고, 이벤트 원본 보관 기간과도 무관하다 — 90일이 지나 원본이
    /// 사라진 날의 사용자도 그 날 버킷에는 남아 있다.
    ///
    /// 창은 언제나 **온전한 하루들**이다. `now − 30 × 86,400`이 아니라 오늘과 그
    /// 앞 29일이라, 몇 초 간격의 두 렌더가 다른 숫자를 내지 않는다.
    func activeUsers(for project: String?, audience: Audience = .all,
                     calendar: Calendar = .current) -> ActiveUsers {
        memoized(\.activeUsers, ScopeKey(project: project, audience: audience)) {
            let days = self.days(for: project, audience: audience)

            /// `offset`일 전에 끝나는 `length`일 창 안의 서로 다른 설치 수.
            func distinct(length: Int, endingDaysAgo offset: Int) -> Int {
                var installs: Set<String> = []
                for key in UsageRollups.windowKeys(days: length, endingDaysAgo: offset,
                                                   calendar: calendar) {
                    guard let bucket = days[key] else { continue }
                    installs.formUnion(bucket.installs)
                }
                return installs.count
            }

            func window(_ span: ActiveUsers.Span) -> ActiveUsers.Window {
                ActiveUsers.Window(span: span,
                                   current: distinct(length: span.days, endingDaysAgo: 0),
                                   previous: distinct(length: span.days, endingDaysAgo: span.days))
            }

            // 추이는 같은 계산을 하루씩 물러나며 되풀이한 것이다. 30일치라도 한 점당
            // 최대 30개 버킷의 합집합이고, 그 버킷은 이벤트가 도착할 때 이미 접혀
            // 있으므로 원본은 한 건도 훑지 않는다.
            let series = UsageRollups.recentDayKeys(ActiveUsers.trendDays, calendar: calendar)
                .enumerated()
                .map { index, entry -> ActiveUsers.Point in
                    let ago = ActiveUsers.trendDays - 1 - index
                    return ActiveUsers.Point(
                        date: entry.date,
                        day: distinct(length: ActiveUsers.Span.day.days, endingDaysAgo: ago),
                        week: distinct(length: ActiveUsers.Span.week.days, endingDaysAgo: ago),
                        month: distinct(length: ActiveUsers.Span.month.days, endingDaysAgo: ago))
                }

            return ActiveUsers(day: window(.day), week: window(.week), month: window(.month),
                               series: series)
        }
    }

    // MARK: - 열림 · 안 열림, 그리고 열린 이유

    /// 앱이 스냅샷 `metrics`에 실어 보내는 권한 플래그의 **규약**.
    ///
    /// 두 층이다. 위층은 **접근** 하나 — 지금 유료 기능을 쓸 수 있는가. 아래층은
    /// 그게 **왜** 열렸는가(결제·체험·무상)다.
    ///
    /// 층을 나눈 이유: 두 질문은 답을 아는 주체가 다르다. "쓸 수 있는가"는 거의
    /// 모든 앱이 이미 보내고 있다 — `flag.isPro` 같은 옛 이름이 실제로 재고 있던
    /// 값이 바로 이것이다. "돈을 냈는가"는 그렇지 않다. 한때 이 화면은 옛 이름을
    /// **결제**로 읽었고, 그래서 신규 설치의 99%가 유료로 기록됐다. 값이 틀렸던
    /// 게 아니라 축이 틀렸던 것이다 — 같은 0/1을 접근으로 읽으면 참이다.
    enum EntitlementFlag {
        /// 지금 유료 기능이 열려 있는가. 이유는 묻지 않는다.
        static let access = "flag.hasAccess"
        /// 지금 유효한 결제가 있는가. 이것만이 매출과 이어진다.
        static let paid = "flag.isPaid"
        /// 체험 기간 중인가 — 아직 안 냈고, 곧 결정할 사람.
        static let trial = "flag.isTrial"
        /// 돈을 안 내고 열린 접근인가 — 그랜드파더·가족 공유·내부 테스터.
        static let comped = "flag.isComped"
    }

    /// 규약이 생기기 전에 쓰이던 이름들. **접근** 후보다.
    ///
    /// 이 이름들은 실무에서 대개 결제가 아니라 "기능이 열려 있는가"를 뜻한다.
    /// 그래서 결제 자리에 놓으면 유료가 부풀지만, 접근 자리에 놓으면 그냥 맞다.
    /// 실측이 그렇게 말한다: ClipKeyboard에서 무료 한도(단축어 10개)를 넘긴 65대는
    /// **전부** `flag.isPro`가 켜져 있었고(앞뒤가 맞는다), 한도 안에서 쓰는 5,690대
    /// 중에서도 5,654대가 켜져 있었다. 결제라면 설명이 안 되지만, 접근이라면
    /// 설명이 된다 — 5.0.0부터 모두에게 열어 둔 것이다.
    static let accessFlagCandidates = [
        "flag.hasAccess", "flag.hasFullAccess", "flag.fullAccess", "flag.unlocked",
        "flag.isPro", "flag.pro", "flag.isPremium", "flag.premium", "flag.isPlus",
        "flag.isPaid", "flag.paid", "flag.purchased", "flag.subscribed", "flag.isSubscriber"
    ]

    /// 한 앱에서 권한을 어떻게 읽어 낼지 — 어느 키를 어떤 근거로 골랐는가.
    struct Entitlement {
        struct Flag: Hashable {
            let key: String
            /// 스펙이 직접 지정한 키인가, 규약·이름으로 찾아낸 것인가.
            let isDeclared: Bool
        }

        /// 권한을 뜻하는 키. 아래 셋도 권한의 근거가 되므로 이게 없어도 된다.
        let access: Flag?
        /// 규약대로 나눠 보내는 앱의 키들. 여기서는 셋 다 "열렸다"의 근거로만 쓴다 —
        /// 어느 쪽으로 열렸는지는 이 화면이 묻지 않는다(`FeedbackStore+Audience.swift`).
        let paid: Flag?
        let trial: Flag?
        let comped: Flag?

        /// 이 설치에서 유료 기능이 열려 있는가.
        ///
        /// `nil`은 **모름** — 접근을 말해 주는 키를 이 설치가 하나도 안 보냈다는
        /// 뜻이다. 그 자리를 0으로 읽어 "안 열림"으로 세면 안 된다.
        ///
        /// 켜진 것 **하나라도** 있으면 열림이다(합집합). 접근은 본래 합집합이고
        /// — 결제든 체험이든 무상이든 열리면 열린 것이다 — 그래서 한 앱 안에
        /// 옛 키를 보내는 구버전과 새 키를 보내는 신버전이 섞여 있어도 설치마다
        /// 제가 보낸 것으로 판정이 난다. 앱의 배포 상태가 숫자를 흔들지 않는다.
        func isUnlocked(_ snapshot: UsageSnapshot) -> Bool? {
            var sawAny = false
            var unlocked = false
            for flag in [access, paid, trial, comped] {
                guard let flag, let value = snapshot.metrics[flag.key] else { continue }
                sawAny = true
                // 0/1 플래그라 "1 이상이면 켜짐". 앱이 실수로 2를 보내도
                // 한 명이지 두 명이 아니다.
                if value >= 1 { unlocked = true }
            }
            return sawAny ? unlocked : nil
        }

    }

    /// 이 프로젝트에서 권한을 읽어 낼 방법. 접근도 이유도 못 읽으면 nil —
    /// 그 앱의 설치는 어느 쪽에도 넣지 않는다.
    ///
    /// 스냅샷이 **실제로 보낸 적 있는** 키만 고른다. 스펙에 적혀 있어도 앱이
    /// 아직 안 보내면 전부 "안 열림"으로 세어 버리기 때문이다.
    func entitlement(for project: String) -> Entitlement? {
        let snaps = snapshots(for: project)
        guard !snaps.isEmpty else { return nil }
        let present = Set(snaps.flatMap { $0.metrics.keys })
        let spec = ProjectStatsSpecCatalog.spec(for: project)

        /// 스펙이 적어 둔 이름이 1순위, 규약 이름이 2순위.
        func resolve(_ declared: String?, convention: String) -> Entitlement.Flag? {
            if let declared, present.contains(declared) {
                return .init(key: declared, isDeclared: true)
            }
            if present.contains(convention) {
                return .init(key: convention, isDeclared: false)
            }
            return nil
        }

        let paid = resolve(spec?.paidFlag, convention: EntitlementFlag.paid)
        let trial = resolve(spec?.trialFlag, convention: EntitlementFlag.trial)
        let comped = resolve(spec?.compedFlag, convention: EntitlementFlag.comped)

        var access = resolve(spec?.accessFlag, convention: EntitlementFlag.access)
        if access == nil, let guessed = Self.accessFlagCandidates.first(where: present.contains) {
            access = .init(key: guessed, isDeclared: false)
        }

        guard access != nil || paid != nil || trial != nil || comped != nil else { return nil }
        return Entitlement(access: access, paid: paid, trial: trial, comped: comped)
    }
    /// 유료 기능을 쓸 수 있는 설치와 무료 기능만 쓰는 설치. 권한을 읽을 수 있는
    /// 앱이 하나도 없으면 nil.
    ///
    /// 전체 프로젝트에서는 앱마다 키가 다르므로 앱별로 갈라서 더한다. 권한을 아예
    /// 못 읽는 앱의 설치는 **모름으로 센다** — 빼 버리면 카드의 산수가 안 닫히고,
    /// 맞지 않는 숫자를 본 사람은 각주를 읽는 게 아니라 화면 전체를 의심한다.
    func accessSplit(for project: String?) -> AccessSplit? {
        memoized(\.accessSplit, project) {
            let now = Date()
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let monthAgo = now.addingTimeInterval(-30 * 86_400)

            let scope = project.map { [$0] } ?? allProjectKeys
            var sources: [AccessSplit.Source] = []
            typealias Tally = (paidFeatures: Int, freeFeatures: Int, unknown: Int)
            var all: Tally = (0, 0, 0)
            var week = all
            var month = all

            /// 이 스냅샷이 드는 창에 한 번씩 세어 준다.
            func tally(_ snapshot: UsageSnapshot, _ add: (inout Tally) -> Void) {
                let active = snapshot.lastActiveAt ?? .distantPast
                add(&all)
                if active >= weekAgo { add(&week) }
                if active >= monthAgo { add(&month) }
            }

            for key in scope {
                guard let entitlement = entitlement(for: key) else {
                    for snapshot in snapshots(for: key) {
                        tally(snapshot) { $0.unknown += 1 }
                    }
                    continue
                }

                for snapshot in snapshots(for: key) {
                    tally(snapshot) {
                        switch entitlement.isUnlocked(snapshot) {
                        case true?:  $0.paidFeatures += 1
                        case false?: $0.freeFeatures += 1
                        case nil:    $0.unknown += 1
                        }
                    }
                }

                let named = entitlement.access ?? entitlement.paid
                sources.append(AccessSplit.Source(
                    project: key,
                    displayName: displayName(for: key),
                    key: named?.key ?? "—",
                    label: named.flatMap { ProjectStatsSpecCatalog.spec(for: key)?.label(forMetric: $0.key) },
                    isDeclared: named?.isDeclared ?? false))
            }

            guard !sources.isEmpty else { return nil }
            func slice(_ t: Tally) -> AccessSplit.Slice {
                .init(paidFeatures: t.paidFeatures, freeFeatures: t.freeFeatures, unknown: t.unknown)
            }
            return AccessSplit(sources: sources.sorted { $0.displayName < $1.displayName },
                               all: slice(all),
                               active7: slice(week),
                               active30: slice(month))
        }
    }

    // MARK: - Diagnostics

    /// Diagnostics for one project, rolled up the way the apps' 안정성 screen
    /// shows them (per version, plus the recent list with call stacks).
    ///
    /// Timing is the record's creation date: MetricKit hands diagnostics over
    /// about once a day, so "최근 7일" means "arrived in the last 7 days", not
    /// "crashed in the last 7 days".
    func crashSummary(for project: String?) -> CrashSummary {
        memoized(\.crashSummary, project) {
        let items = crashes(for: project)
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)

        var kindCounts: [String: Int] = [:]
        var versionCounts: [String: Int] = [:]
        for item in items {
            kindCounts[item.kind, default: 0] += 1
            versionCounts[item.appVersion, default: 0] += 1
        }

        let byKind = kindCounts
            .map { (kind: $0.key, label: CrashReport.label(for: $0.key), count: $0.value) }
            .sorted { $0.count > $1.count }

        let value = CrashSummary(
            total: items.count,
            last7Days: items.filter { ($0.receivedAt ?? .distantPast) >= weekAgo }.count,
            previous7Days: items.filter {
                guard let at = $0.receivedAt else { return false }
                return at >= twoWeeksAgo && at < weekAgo
            }.count,
            byKind: byKind,
            byVersion: versionCounts
                .map { DistributionBucket(key: $0.key, count: $0.value) }
                .sorted { $0.count == $1.count ? $0.key.localizedStandardCompare($1.key) == .orderedDescending : $0.count > $1.count },
            recent: Array(items.prefix(30)),
            lastAt: items.first?.receivedAt
        )
        return value
        }
    }

    /// Diagnostics for one project (nil == 전체), newest first, optionally
    /// narrowed to one `kind`. Backs the "진단 모아보기" screen.
    func crashReports(for project: String?, kind: String? = nil) -> [CrashReport] {
        crashes(for: project)
            .filter { kind == nil || $0.kind == kind }
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }

    /// 같은 사고끼리 묶은 이슈, **아픈 것부터**. 진단 화면의 기본 시야다.
    ///
    /// 한 건씩 늘어놓은 목록은 "많이 나는 것부터"를 못 고른다. 묶어야 고칠 순서가
    /// 정해진다. 묶는 규칙과 그 한계는 `CrashAnalysis.swift` 머리말에 있다.
    func crashIssues(for project: String?) -> [CrashIssue] {
        memoized(\.crashIssues, project) { CrashIssue.group(crashes(for: project)) }
    }

    /// Projects that reported diagnostics, worst first — the list behind the
    /// red ⚠︎ marks.
    var crashingProjects: [(key: String, displayName: String, total: Int, last7Days: Int)] {
        memoized(\.crashingProjects) {
            allProjectKeys.compactMap { key in
                let summary = crashSummary(for: key)
                guard summary.total > 0 else { return nil }
                return (key: key, displayName: displayName(for: key),
                        total: summary.total, last7Days: summary.last7Days)
            }
            .sorted { lhs, rhs in
                lhs.last7Days == rhs.last7Days ? lhs.total > rhs.total : lhs.last7Days > rhs.last7Days
            }
        }
    }

    // MARK: - Events

    /// Event names for one project, most frequent first. All-time, from the
    /// running totals kept alongside the day buckets — so a name that stopped
    /// firing months ago still shows the count it earned.
    func eventStats(for project: String?, audience: Audience = .all) -> [EventStat] {
        memoized(\.eventStats, ScopeKey(project: project, audience: audience)) {
            // 무리를 고른 동안은 건수가 없으므로 사람 수로 줄을 세운다. 건수로
            // 정렬해 둔 채 건수를 감추면 순서를 설명할 수 없는 목록이 된다.
            eventTotals(for: project, audience: audience)
                .filter { !audience.isFiltered || !$0.value.installs.isEmpty }
                .map { EventStat(name: $0.key,
                                 count: audience.isFiltered ? nil : $0.value.count,
                                 installs: $0.value.installs.count, lastAt: $0.value.lastAt) }
                .sorted { lhs, rhs in
                    if let l = lhs.count, let r = rhs.count { return l > r }
                    return lhs.installs > rhs.installs
                }
        }
    }

    /// Event names with the install sets behind them, all-time. `eventStats`
    /// only carries counts, and a funnel cannot be built from counts: a step
    /// written as `paywall_cta_tapped` has to union the install sets of every
    /// slice (`:buy`, `:memo`), and summing them would count someone who tapped
    /// both as two people.
    func eventTallies(for project: String?, audience: Audience = .all) -> [String: UsageNameTotal] {
        memoized(\.eventTallies, ScopeKey(project: project, audience: audience)) {
            eventTotals(for: project, audience: audience)
        }
    }

    /// The events themselves, newest first — what the 사용 내역 card lists. The
    /// one place raw records are still needed, and the reason a window of them
    /// is retained (`FeedbackStore.rawEventRetentionDays`); everything older is
    /// present as counts, not as individual lines.
    ///
    /// Sorted here rather than in the view, which re-ran the whole sort every
    /// time the card redrew (including on every "더 보기" tap).
    func eventLog(for project: String?, audience: Audience = .all) -> [UsageEvent] {
        memoized(\.eventLog, ScopeKey(project: project, audience: audience)) {
            // 원본 한 건에는 `installID`가 붙어 있으므로, 목록만은 무리별로 정확히
            // 갈린다 — 접힌 건수와 달리 여기서는 한 줄이 곧 한 설치의 행동이다.
            let ids = installIDs(for: project, audience: audience)
            return events(for: project)
                .filter { event in
                    guard let ids else { return true }
                    guard let install = event.installID else { return false }
                    return ids.contains(install)
                }
                .sorted { $0.occurredAt > $1.occurredAt }
        }
    }

    // MARK: - Metrics reported by the app

    private static func isFlag(_ key: String) -> Bool {
        key.hasPrefix("flag.") || key.hasPrefix("persona.")
    }

    /// Numeric metrics, averaged over the installs that reported them — the
    /// same "설치당 평균" the apps show.
    func metricAverages(for project: String?, audience: Audience = .all) -> [MetricAverage] {
        memoized(\.metricAverages, ScopeKey(project: project, audience: audience)) {
            var sums: [String: (total: Double, count: Int)] = [:]
            for snapshot in snapshots(for: project, audience: audience) {
                for (key, value) in snapshot.metrics where !Self.isFlag(key) {
                    let current = sums[key] ?? (0, 0)
                    sums[key] = (current.total + value, current.count + 1)
                }
            }
            return sums
                .map { MetricAverage(key: $0.key,
                                     average: $0.value.count > 0 ? $0.value.total / Double($0.value.count) : 0,
                                     total: $0.value.total,
                                     samples: $0.value.count) }
                .sorted { $0.key < $1.key }
        }
    }

    /// 0/1 flags as a share of this project's installs.
    func flagShares(for project: String?, audience: Audience = .all) -> [FlagShare] {
        memoized(\.flagShares, ScopeKey(project: project, audience: audience)) {
            let snaps = snapshots(for: project, audience: audience)
            guard !snaps.isEmpty else { return [] }
            var counts: [String: Int] = [:]
            for snapshot in snaps {
                for (key, value) in snapshot.metrics where Self.isFlag(key) && value >= 1 {
                    counts[key, default: 0] += 1
                }
            }
            return counts
                .map { FlagShare(key: $0.key, count: $0.value, ratio: Double($0.value) / Double(snaps.count)) }
                .sorted { $0.count > $1.count }
        }
    }

    /// Install counts by one snapshot field (version, platform, OS, locale).
    func distribution(for project: String?, audience: Audience = .all,
                      by field: KeyPath<UsageSnapshot, String>) -> [DistributionBucket] {
        memoized(\.distribution, DistributionKey(project: project, audience: audience, field: field)) {
            var counts: [String: Int] = [:]
            for snapshot in snapshots(for: project, audience: audience) {
                counts[snapshot[keyPath: field], default: 0] += 1
            }
            return counts
                .map { DistributionBucket(key: $0.key, count: $0.value) }
                .sorted { $0.count == $1.count ? $0.key.localizedStandardCompare($1.key) == .orderedDescending : $0.count > $1.count }
        }
    }

    // MARK: - Trend

    /// A continuous series with empty buckets filled in, so the chart has no
    /// gaps. Built from `occurredAt`, never the record's creation date:
    /// backfilled days would otherwise all land on the day they were uploaded.
    func trend(for project: String?, unit: TrendUnit, audience: Audience = .all,
               calendar: Calendar = .current) -> [TrendPoint] {
        memoized(\.trend, TrendKey(project: project, audience: audience,
                                   unit: unit, calendar: calendar)) {
        func bucketStart(_ date: Date) -> Date? {
            calendar.dateInterval(of: unit.component, for: date)?.start
        }

        // Weeks, months and years were added up once, when the events that
        // moved them arrived (`UsageRollups.rebuildDirtyPeriods`), so this
        // reads one bucket per point on the chart instead of re-summing every
        // day the hub has ever held. 활동 사용자 is the *union* of the install
        // sets inside a period, never the sum — one install active on Monday
        // and Tuesday is one user — which is why the ladder stores the sets.
        var eventCounts: [Date: Int] = [:]
        var activeInstalls: [Date: Int] = [:]
        for (key, bucket) in periodBuckets(unit.granularity, for: project, audience: audience) {
            guard let start = UsageRollups.date(fromKey: key, granularity: unit.granularity,
                                                calendar: calendar) else { continue }
            eventCounts[start] = bucket.events
            activeInstalls[start] = bucket.installs.count
        }

        var newInstalls: [Date: Int] = [:]
        for snapshot in snapshots(for: project, audience: audience) {
            guard let installed = snapshot.installDate, let start = bucketStart(installed) else { continue }
            newInstalls[start, default: 0] += 1
        }

        let starts = Set(eventCounts.keys).union(activeInstalls.keys).union(newInstalls.keys)
        guard let first = starts.min(), let today = bucketStart(Date()) else { return [] }
        let last = max(starts.max() ?? today, today)

        var points: [TrendPoint] = []
        var cursor = first
        // 400 buckets is the same safety stop the apps use.
        while cursor <= last && points.count < 400 {
            points.append(TrendPoint(date: cursor,
                                     events: eventCounts[cursor] ?? 0,
                                     activeInstalls: activeInstalls[cursor] ?? 0,
                                     newInstalls: newInstalls[cursor] ?? 0))
            guard let next = calendar.date(byAdding: unit.component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
        }
    }


    // MARK: - Carrying capacity

    /// 이 프로젝트의 성장 상한 — 지금의 유입과 이탈이 이어질 때 활동 사용자가
    /// 멈추는 자리(`CarryingCapacity`). 활동이 한 번도 없었으면 nil.
    ///
    /// 추이와 같은 일 버킷에서 나오므로 이벤트 원본 보관 기간과 무관하게 허브가
    /// 아는 모든 과거를 본다.
    func carryingCapacity(for project: String?,
                          period: CarryingCapacity.Period,
                          audience: Audience = .all) -> CarryingCapacity? {
        memoized(\.carryingCapacity, CapacityKey(project: project, audience: audience,
                                                 period: period)) {
            CarryingCapacity.measure(days: days(for: project, audience: audience),
                                     period: period)
        }
    }
}

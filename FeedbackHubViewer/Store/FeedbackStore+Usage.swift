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
        var activeInstallsDelta: Int { activeInstalls7 - previousActiveInstalls7 }
        var eventsDelta: Int { events7 - previousEvents7 }
        var newDelta: Int { new7 - previousNew7 }
    }

    /// One event name, aggregated. Mirrors `UsageReportingService.EventStat`.
    struct EventStat: Identifiable {
        var id: String { name }
        /// The name as the app sent it, slice included ("paywall_view:memo").
        let name: String
        let count: Int
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

    /// 유료 사용자와 무료 사용자, 그리고 그중 지금 살아 있는 사람.
    ///
    /// 허브는 결제 영수증을 받지 않는다. 아는 것은 앱이 스냅샷에 실어 보낸 0/1
    /// 플래그 하나뿐이다 — ClipKeyboard의 `flag.isPro` 같은 것. 그래서 이 숫자는
    /// "매출"이 아니라 **앱이 유료라고 표시해 보낸 설치 수**이고, 화면에도 어떤
    /// 키로 갈랐는지 그대로 적는다.
    ///
    /// 활성의 정의는 바로 위 타일(`최근 7일 활성`)과 **같은 것**을 쓴다. 스냅샷의
    /// `lastActiveAt`이다. 이벤트 기반(DAU·WAU·MAU)이 아니라 이쪽인 이유: 유료
    /// 여부가 스냅샷에 있으므로 같은 레코드에서 두 값을 함께 읽으면 짝이 안 맞는
    /// 설치가 없다. 덕분에 `유료 + 무료`는 언제나 그 타일의 숫자와 정확히 같고,
    /// 두 숫자가 어긋나 보이는 일이 생기지 않는다.
    struct PaidSplit {
        /// 한 창(전체 / 최근 7일 / 최근 30일)에서 갈린 수.
        struct Slice {
            let paid: Int
            let free: Int

            var total: Int { paid + free }
            /// 유료 비중. 아무도 없으면 비율이랄 게 없다.
            var ratio: Double? {
                guard total > 0 else { return nil }
                return Double(paid) / Double(total)
            }
        }

        /// 이 값을 만든 앱과 그 앱에서 유료를 뜻한 키. 전체 프로젝트에서는
        /// 앱마다 키가 다르므로 여럿이 된다.
        struct Source {
            let project: String
            let displayName: String
            let key: String
            /// 스펙이 그 키에 붙인 이름("Pro 사용자"). 없으면 키 원문을 쓴다.
            let label: String?
            /// 스펙이 직접 지정한 키인가, 흔한 이름으로 추측한 것인가.
            let isDeclared: Bool
        }

        let sources: [Source]
        let all: Slice
        let active7: Slice
        let active30: Slice

        /// 유료 여부를 보내는 앱이 하나도 없으면 보여 줄 것이 없다.
        var isEmpty: Bool { sources.isEmpty || all.total == 0 }
        /// 추측한 키가 하나라도 섞여 있으면 화면에서 그렇다고 말해야 한다.
        var hasGuessedKey: Bool { sources.contains { !$0.isDeclared } }
    }

    // MARK: - Cache keys

    /// What `distribution(for:by:)` was asked for. The keypath identifies the
    /// snapshot field, so the four distributions on the stats screen each get
    /// their own entry.
    struct DistributionKey: Hashable {
        let project: String?
        let field: KeyPath<UsageSnapshot, String>
    }

    /// What `trend(for:unit:calendar:)` was asked for.
    struct TrendKey: Hashable {
        let project: String?
        let unit: TrendUnit
        let calendar: Calendar
    }

    /// What `carryingCapacity(for:period:)` was asked for.
    struct CapacityKey: Hashable {
        let project: String?
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

    func usage(for project: String?) -> ProjectUsage {
        memoized(\.usage, project) {
        let snaps = snapshots(for: project)
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)

        // The event side of this comes from the day buckets, so it stays
        // correct however far back the hub goes and costs nothing to read.
        let days = rollups.days(for: project, excluding: hiddenProjects)
        let thisWeek = UsageRollups.window(days, keys: UsageRollups.windowKeys(days: 7))
        let lastWeek = UsageRollups.window(days, keys: UsageRollups.windowKeys(days: 7, endingDaysAgo: 7))
        let totalEvents = days.values.reduce(0) { $0 + $1.events }

        let value = ProjectUsage(
            project: project ?? "",
            displayName: project.map { displayName(for: $0) } ?? "전체 프로젝트",
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
    func activeUsers(for project: String?, calendar: Calendar = .current) -> ActiveUsers {
        memoized(\.activeUsers, project) {
            let days = rollups.days(for: project, excluding: hiddenProjects)

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

    // MARK: - 유료 · 무료

    /// 앱이 "유료"라고 표시해 보내는 플래그 이름 후보.
    ///
    /// 스펙(`paidFlag`)이 1순위이고 이건 그 다음이다. 앱 리포가 아직 스펙에
    /// 한 줄을 안 적었어도 오늘 화면에 뭔가는 나와야 하기 때문인데, 추측이므로
    /// 고른 키를 각주에 드러내고 "스펙에 적으라"고 말한다.
    static let paidFlagCandidates = [
        "flag.isPro", "flag.pro", "flag.isPaid", "flag.paid",
        "flag.isPremium", "flag.premium", "flag.subscribed", "flag.isSubscriber",
        "flag.purchased", "flag.isPlus"
    ]

    /// 이 프로젝트에서 유료를 뜻하는 키와, 그것을 어떻게 알았는지.
    /// 스냅샷이 실제로 보낸 적 있는 키만 고른다 — 스펙에 적혀 있어도 앱이
    /// 아직 안 보내면 전부 무료로 세어 버리기 때문이다.
    func paidFlagKey(for project: String) -> (key: String, isDeclared: Bool)? {
        let snaps = snapshots(for: project)
        guard !snaps.isEmpty else { return nil }
        let present = Set(snaps.flatMap { $0.metrics.keys })
        if let declared = ProjectStatsSpecCatalog.spec(for: project)?.paidFlag,
           present.contains(declared) {
            return (declared, true)
        }
        if let guessed = Self.paidFlagCandidates.first(where: present.contains) {
            return (guessed, false)
        }
        return nil
    }

    /// 유료·무료로 나눈 설치 수. 유료 여부를 보내는 앱이 없으면 nil.
    ///
    /// 전체 프로젝트에서는 앱마다 키가 다르므로 앱별로 갈라서 더한다. 유료 여부를
    /// 아예 안 보내는 앱은 빠진다 — 그 앱의 설치를 무료로 세면 없는 사실을
    /// 지어내는 것이고, 유료로 세면 말할 것도 없다. 그래서 이 카드의 합계는 위
    /// 타일의 설치 수보다 작을 수 있고, 화면에 어느 앱을 셌는지 적는다.
    func paidSplit(for project: String?) -> PaidSplit? {
        memoized(\.paidSplit, project) {
            let now = Date()
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let monthAgo = now.addingTimeInterval(-30 * 86_400)

            let scope = project.map { [$0] } ?? allProjectKeys
            var sources: [PaidSplit.Source] = []
            var all = (paid: 0, free: 0)
            var week = (paid: 0, free: 0)
            var month = (paid: 0, free: 0)

            for key in scope {
                guard let flag = paidFlagKey(for: key) else { continue }
                sources.append(PaidSplit.Source(
                    project: key,
                    displayName: displayName(for: key),
                    key: flag.key,
                    label: ProjectStatsSpecCatalog.spec(for: key)?.label(forMetric: flag.key),
                    isDeclared: flag.isDeclared))

                for snapshot in snapshots(for: key) {
                    // 0/1 플래그라 "1 이상이면 유료". 앱이 실수로 2를 보내도
                    // 유료 한 명이지 두 명이 아니다.
                    let isPaid = (snapshot.metrics[flag.key] ?? 0) >= 1
                    let active = snapshot.lastActiveAt ?? .distantPast
                    if isPaid { all.paid += 1 } else { all.free += 1 }
                    if active >= weekAgo {
                        if isPaid { week.paid += 1 } else { week.free += 1 }
                    }
                    if active >= monthAgo {
                        if isPaid { month.paid += 1 } else { month.free += 1 }
                    }
                }
            }

            guard !sources.isEmpty else { return nil }
            return PaidSplit(sources: sources.sorted { $0.displayName < $1.displayName },
                             all: .init(paid: all.paid, free: all.free),
                             active7: .init(paid: week.paid, free: week.free),
                             active30: .init(paid: month.paid, free: month.free))
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
    func eventStats(for project: String?) -> [EventStat] {
        memoized(\.eventStats, project) {
            rollups.totals(for: project, excluding: hiddenProjects)
                .map { EventStat(name: $0.key, count: $0.value.count,
                                 installs: $0.value.installs.count, lastAt: $0.value.lastAt) }
                .sorted { $0.count > $1.count }
        }
    }

    /// Event names with the install sets behind them, all-time. `eventStats`
    /// only carries counts, and a funnel cannot be built from counts: a step
    /// written as `paywall_cta_tapped` has to union the install sets of every
    /// slice (`:buy`, `:memo`), and summing them would count someone who tapped
    /// both as two people.
    func eventTallies(for project: String?) -> [String: UsageNameTotal] {
        memoized(\.eventTallies, project) {
            rollups.totals(for: project, excluding: hiddenProjects)
        }
    }

    /// The events themselves, newest first — what the 사용 내역 card lists. The
    /// one place raw records are still needed, and the reason a window of them
    /// is retained (`FeedbackStore.rawEventRetentionDays`); everything older is
    /// present as counts, not as individual lines.
    ///
    /// Sorted here rather than in the view, which re-ran the whole sort every
    /// time the card redrew (including on every "더 보기" tap).
    func eventLog(for project: String?) -> [UsageEvent] {
        memoized(\.eventLog, project) {
            events(for: project).sorted { $0.occurredAt > $1.occurredAt }
        }
    }

    // MARK: - Metrics reported by the app

    private static func isFlag(_ key: String) -> Bool {
        key.hasPrefix("flag.") || key.hasPrefix("persona.")
    }

    /// Numeric metrics, averaged over the installs that reported them — the
    /// same "설치당 평균" the apps show.
    func metricAverages(for project: String?) -> [MetricAverage] {
        memoized(\.metricAverages, project) {
            var sums: [String: (total: Double, count: Int)] = [:]
            for snapshot in snapshots(for: project) {
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
    func flagShares(for project: String?) -> [FlagShare] {
        memoized(\.flagShares, project) {
            let snaps = snapshots(for: project)
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
    func distribution(for project: String?, by field: KeyPath<UsageSnapshot, String>) -> [DistributionBucket] {
        memoized(\.distribution, DistributionKey(project: project, field: field)) {
            var counts: [String: Int] = [:]
            for snapshot in snapshots(for: project) {
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
    func trend(for project: String?, unit: TrendUnit, calendar: Calendar = .current) -> [TrendPoint] {
        memoized(\.trend, TrendKey(project: project, unit: unit, calendar: calendar)) {
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
        for (key, bucket) in rollups.buckets(unit.granularity, for: project, excluding: hiddenProjects) {
            guard let start = UsageRollups.date(fromKey: key, granularity: unit.granularity,
                                                calendar: calendar) else { continue }
            eventCounts[start] = bucket.events
            activeInstalls[start] = bucket.installs.count
        }

        var newInstalls: [Date: Int] = [:]
        for snapshot in snapshots(for: project) {
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
                          period: CarryingCapacity.Period) -> CarryingCapacity? {
        memoized(\.carryingCapacity, CapacityKey(project: project, period: period)) {
            CarryingCapacity.measure(days: rollups.days(for: project, excluding: hiddenProjects),
                                     period: period)
        }
    }
}

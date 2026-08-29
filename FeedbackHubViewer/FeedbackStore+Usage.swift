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

    /// Visible snapshots grouped by project, built in one pass — the three
    /// `…(for:)` accessors below are called from inside list rows, where a
    /// filter over the whole array turns into O(프로젝트 수 × 레코드 수).
    var snapshotsByProject: [String: [UsageSnapshot]] {
        if let cached = derived.snapshotsByProject { return cached }
        let value = Dictionary(grouping: allSnapshots, by: \.projectKey)
        derived.snapshotsByProject = value
        return value
    }

    var eventsByProject: [String: [UsageEvent]] {
        if let cached = derived.eventsByProject { return cached }
        let value = Dictionary(grouping: allEvents, by: \.projectKey)
        derived.eventsByProject = value
        return value
    }

    var crashesByProject: [String: [CrashReport]] {
        if let cached = derived.crashesByProject { return cached }
        let value = Dictionary(grouping: allCrashes, by: \.projectKey)
        derived.crashesByProject = value
        return value
    }

    /// Usage records for one project, or all of them when `project` is nil.
    func snapshots(for project: String?) -> [UsageSnapshot] {
        guard let project else { return allSnapshots }
        return snapshotsByProject[project] ?? []
    }

    /// The individual events this device still holds — the last
    /// `FeedbackStore.rawEventRetentionDays` days, not the whole history. Only
    /// `eventLog(for:)` should want these; every *number* comes from `rollups`,
    /// which goes all the way back.
    func events(for project: String?) -> [UsageEvent] {
        guard let project else { return allEvents }
        return eventsByProject[project] ?? []
    }

    func crashes(for project: String?) -> [CrashReport] {
        guard let project else { return allCrashes }
        return crashesByProject[project] ?? []
    }

    /// Every project key that appears anywhere — feedback, usage, or a crash.
    /// An app can report under an id that never shows up in feedback.
    var allProjectKeys: [String] {
        if let cached = derived.projectKeys { return cached }
        var keys = Set(allFeedback.map(\.projectKey))
        keys.formUnion(allSnapshots.map(\.projectKey))
        // From the rollups, not the raw events: an app whose events have all
        // aged out of the retained window is still an app of yours, and its
        // history is still on file.
        keys.formUnion(rollups.projectKeys.subtracting(hiddenProjects))
        keys.formUnion(allCrashes.map(\.projectKey))
        let installs = snapshotsByProject.mapValues(\.count)
        let value = keys.sorted { lhs, rhs in
            if lhs == Feedback.unclassifiedProject { return false }
            if rhs == Feedback.unclassifiedProject { return true }
            let l = installs[lhs] ?? 0, r = installs[rhs] ?? 0
            if l != r { return l > r }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
        derived.projectKeys = value
        return value
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
        if let cached = derived.usage[project] { return cached }
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
        derived.usage[project] = value
        return value
    }

    // MARK: - Diagnostics

    /// Diagnostics for one project, rolled up the way the apps' 안정성 screen
    /// shows them (per version, plus the recent list with call stacks).
    ///
    /// Timing is the record's creation date: MetricKit hands diagnostics over
    /// about once a day, so "최근 7일" means "arrived in the last 7 days", not
    /// "crashed in the last 7 days".
    func crashSummary(for project: String?) -> CrashSummary {
        if let cached = derived.crashSummary[project] { return cached }
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
        derived.crashSummary[project] = value
        return value
    }

    /// Diagnostics for one project (nil == 전체), newest first, optionally
    /// narrowed to one `kind`. Backs the "진단 모아보기" screen.
    func crashReports(for project: String?, kind: String? = nil) -> [CrashReport] {
        crashes(for: project)
            .filter { kind == nil || $0.kind == kind }
            .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }

    /// Projects that reported diagnostics, worst first — the list behind the
    /// red ⚠︎ marks.
    var crashingProjects: [(key: String, displayName: String, total: Int, last7Days: Int)] {
        if let cached = derived.crashingProjects { return cached }
        let value: [(key: String, displayName: String, total: Int, last7Days: Int)] = allProjectKeys.compactMap { key in
            let summary = crashSummary(for: key)
            guard summary.total > 0 else { return nil }
            return (key: key, displayName: displayName(for: key),
                    total: summary.total, last7Days: summary.last7Days)
        }
        .sorted { lhs, rhs in
            lhs.last7Days == rhs.last7Days ? lhs.total > rhs.total : lhs.last7Days > rhs.last7Days
        }
        derived.crashingProjects = value
        return value
    }

    // MARK: - Events

    /// Event names for one project, most frequent first. All-time, from the
    /// running totals kept alongside the day buckets — so a name that stopped
    /// firing months ago still shows the count it earned.
    func eventStats(for project: String?) -> [EventStat] {
        if let cached = derived.eventStats[project] { return cached }
        let value: [EventStat] = rollups.totals(for: project, excluding: hiddenProjects)
            .map { EventStat(name: $0.key, count: $0.value.count,
                             installs: $0.value.installs.count, lastAt: $0.value.lastAt) }
            .sorted { $0.count > $1.count }
        derived.eventStats[project] = value
        return value
    }

    /// Event names with the install sets behind them, all-time. `eventStats`
    /// only carries counts, and a funnel cannot be built from counts: a step
    /// written as `paywall_cta_tapped` has to union the install sets of every
    /// slice (`:buy`, `:memo`), and summing them would count someone who tapped
    /// both as two people.
    func eventTallies(for project: String?) -> [String: UsageNameTotal] {
        if let cached = derived.eventTallies[project] { return cached }
        let value = rollups.totals(for: project, excluding: hiddenProjects)
        derived.eventTallies[project] = value
        return value
    }

    /// The events themselves, newest first — what the 사용 내역 card lists. The
    /// one place raw records are still needed, and the reason a window of them
    /// is retained (`FeedbackStore.rawEventRetentionDays`); everything older is
    /// present as counts, not as individual lines.
    ///
    /// Sorted here rather than in the view, which re-ran the whole sort every
    /// time the card redrew (including on every "더 보기" tap).
    func eventLog(for project: String?) -> [UsageEvent] {
        if let cached = derived.eventLog[project] { return cached }
        let value = events(for: project).sorted { $0.occurredAt > $1.occurredAt }
        derived.eventLog[project] = value
        return value
    }

    // MARK: - Metrics reported by the app

    private static func isFlag(_ key: String) -> Bool {
        key.hasPrefix("flag.") || key.hasPrefix("persona.")
    }

    /// Numeric metrics, averaged over the installs that reported them — the
    /// same "설치당 평균" the apps show.
    func metricAverages(for project: String?) -> [MetricAverage] {
        if let cached = derived.metricAverages[project] { return cached }
        var sums: [String: (total: Double, count: Int)] = [:]
        for snapshot in snapshots(for: project) {
            for (key, value) in snapshot.metrics where !Self.isFlag(key) {
                let current = sums[key] ?? (0, 0)
                sums[key] = (current.total + value, current.count + 1)
            }
        }
        let value: [MetricAverage] = sums
            .map { MetricAverage(key: $0.key,
                                 average: $0.value.count > 0 ? $0.value.total / Double($0.value.count) : 0,
                                 total: $0.value.total,
                                 samples: $0.value.count) }
            .sorted { $0.key < $1.key }
        derived.metricAverages[project] = value
        return value
    }

    /// 0/1 flags as a share of this project's installs.
    func flagShares(for project: String?) -> [FlagShare] {
        if let cached = derived.flagShares[project] { return cached }
        let snaps = snapshots(for: project)
        guard !snaps.isEmpty else {
            derived.flagShares[project] = []
            return []
        }
        var counts: [String: Int] = [:]
        for snapshot in snaps {
            for (key, value) in snapshot.metrics where Self.isFlag(key) && value >= 1 {
                counts[key, default: 0] += 1
            }
        }
        let value: [FlagShare] = counts
            .map { FlagShare(key: $0.key, count: $0.value, ratio: Double($0.value) / Double(snaps.count)) }
            .sorted { $0.count > $1.count }
        derived.flagShares[project] = value
        return value
    }

    /// Install counts by one snapshot field (version, platform, OS, locale).
    func distribution(for project: String?, by field: KeyPath<UsageSnapshot, String>) -> [DistributionBucket] {
        let cacheKey = DistributionKey(project: project, field: field)
        if let cached = derived.distribution[cacheKey] { return cached }
        var counts: [String: Int] = [:]
        for snapshot in snapshots(for: project) {
            counts[snapshot[keyPath: field], default: 0] += 1
        }
        let value: [DistributionBucket] = counts
            .map { DistributionBucket(key: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.key.localizedStandardCompare($1.key) == .orderedDescending : $0.count > $1.count }
        derived.distribution[cacheKey] = value
        return value
    }

    // MARK: - Trend

    /// A continuous series with empty buckets filled in, so the chart has no
    /// gaps. Built from `occurredAt`, never the record's creation date:
    /// backfilled days would otherwise all land on the day they were uploaded.
    func trend(for project: String?, unit: TrendUnit, calendar: Calendar = .current) -> [TrendPoint] {
        let cacheKey = TrendKey(project: project, unit: unit, calendar: calendar)
        if let cached = derived.trend[cacheKey] { return cached }

        func bucketStart(_ date: Date) -> Date? {
            calendar.dateInterval(of: unit.component, for: date)?.start
        }

        // Weeks, months and years are day buckets added up — and 활동 사용자 is
        // the *union* of their install sets, never the sum, because one install
        // active on Monday and Tuesday is one user.
        var eventCounts: [Date: Int] = [:]
        var installsByBucket: [Date: Set<String>] = [:]
        for (day, bucket) in rollups.days(for: project, excluding: hiddenProjects) {
            guard let date = UsageRollups.date(fromDayKey: day, calendar: calendar),
                  let start = bucketStart(date) else { continue }
            eventCounts[start, default: 0] += bucket.events
            installsByBucket[start, default: []].formUnion(bucket.installs)
        }

        var newInstalls: [Date: Int] = [:]
        for snapshot in snapshots(for: project) {
            guard let installed = snapshot.installDate, let start = bucketStart(installed) else { continue }
            newInstalls[start, default: 0] += 1
        }

        let starts = Set(eventCounts.keys).union(installsByBucket.keys).union(newInstalls.keys)
        guard let first = starts.min(), let today = bucketStart(Date()) else {
            derived.trend[cacheKey] = []
            return []
        }
        let last = max(starts.max() ?? today, today)

        var points: [TrendPoint] = []
        var cursor = first
        // 400 buckets is the same safety stop the apps use.
        while cursor <= last && points.count < 400 {
            points.append(TrendPoint(date: cursor,
                                     events: eventCounts[cursor] ?? 0,
                                     activeInstalls: installsByBucket[cursor]?.count ?? 0,
                                     newInstalls: newInstalls[cursor] ?? 0))
            guard let next = calendar.date(byAdding: unit.component, value: 1, to: cursor) else { break }
            cursor = next
        }
        derived.trend[cacheKey] = points
        return points
    }


    // MARK: - Carrying capacity

    /// 이 프로젝트의 성장 상한 — 지금의 유입과 이탈이 이어질 때 활동 사용자가
    /// 멈추는 자리(`CarryingCapacity`). 활동이 한 번도 없었으면 nil.
    ///
    /// 추이와 같은 일 버킷에서 나오므로 이벤트 원본 보관 기간과 무관하게 허브가
    /// 아는 모든 과거를 본다.
    func carryingCapacity(for project: String?,
                          period: CarryingCapacity.Period) -> CarryingCapacity? {
        let key = CapacityKey(project: project, period: period)
        if let cached = derived.carryingCapacity[key] { return cached }
        let value = CarryingCapacity.measure(
            days: rollups.days(for: project, excluding: hiddenProjects),
            period: period)
        derived.carryingCapacity[key] = value
        return value
    }
}

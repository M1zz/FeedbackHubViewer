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

    // MARK: - Scoping

    /// Usage records for one project, or all of them when `project` is nil.
    func snapshots(for project: String?) -> [UsageSnapshot] {
        guard let project else { return allSnapshots }
        return allSnapshots.filter { $0.projectKey == project }
    }

    func events(for project: String?) -> [UsageEvent] {
        guard let project else { return allEvents }
        return allEvents.filter { $0.projectKey == project }
    }

    func crashes(for project: String?) -> [CrashReport] {
        guard let project else { return allCrashes }
        return allCrashes.filter { $0.projectKey == project }
    }

    /// Every project key that appears anywhere — feedback, usage, or a crash.
    /// An app can report under an id that never shows up in feedback.
    var allProjectKeys: [String] {
        var keys = Set(allFeedback.map(\.projectKey))
        keys.formUnion(allSnapshots.map(\.projectKey))
        keys.formUnion(allEvents.map(\.projectKey))
        keys.formUnion(allCrashes.map(\.projectKey))
        return keys.sorted { lhs, rhs in
            if lhs == Feedback.unclassifiedProject { return false }
            if rhs == Feedback.unclassifiedProject { return true }
            let l = snapshots(for: lhs).count, r = snapshots(for: rhs).count
            if l != r { return l > r }
            return displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    var hasUsageData: Bool { !allSnapshots.isEmpty || !allEvents.isEmpty }

    // MARK: - Per-project rollup

    /// Usage for every project that reported any, most installs first.
    var projectUsages: [ProjectUsage] {
        allProjectKeys
            .map { usage(for: $0) }
            .filter(\.hasUsageData)
    }

    var overallUsage: ProjectUsage { usage(for: nil) }

    func usage(for project: String?) -> ProjectUsage {
        let snaps = snapshots(for: project)
        let evts = events(for: project)
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)
        let monthAgo = now.addingTimeInterval(-30 * 86_400)

        let recentEvents = evts.filter { $0.occurredAt >= weekAgo }
        let previousEvents = evts.filter { $0.occurredAt >= twoWeeksAgo && $0.occurredAt < weekAgo }

        func distinctInstalls(_ items: [UsageEvent]) -> Int {
            Set(items.compactMap(\.installID)).count
        }

        return ProjectUsage(
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
            activeInstalls7: distinctInstalls(recentEvents),
            previousActiveInstalls7: distinctInstalls(previousEvents),
            events7: recentEvents.count,
            previousEvents7: previousEvents.count,
            totalEvents: evts.count,
            lastActiveAt: snaps.compactMap(\.lastActiveAt).max(),
            sparkline: Self.dailyEventCounts(evts, days: 14)
        )
    }

    private static func dailyEventCounts(_ events: [UsageEvent], days: Int) -> [DayCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        var buckets: [Date: Int] = [:]
        for event in events {
            let day = cal.startOfDay(for: event.occurredAt)
            if day >= start { buckets[day, default: 0] += 1 }
        }
        return (0..<days).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DayCount(date: day, count: buckets[day] ?? 0)
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

        return CrashSummary(
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
    }

    // MARK: - Events

    /// Event names for one project, most frequent first.
    func eventStats(for project: String?) -> [EventStat] {
        var buckets: [String: (count: Int, installs: Set<String>, lastAt: Date?)] = [:]
        for event in events(for: project) {
            var entry = buckets[event.name] ?? (0, [], nil)
            entry.count += 1
            if let install = event.installID { entry.installs.insert(install) }
            if (entry.lastAt ?? .distantPast) < event.occurredAt { entry.lastAt = event.occurredAt }
            buckets[event.name] = entry
        }
        return buckets
            .map { EventStat(name: $0.key, count: $0.value.count,
                             installs: $0.value.installs.count, lastAt: $0.value.lastAt) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Metrics reported by the app

    private static func isFlag(_ key: String) -> Bool {
        key.hasPrefix("flag.") || key.hasPrefix("persona.")
    }

    /// Numeric metrics, averaged over the installs that reported them — the
    /// same "설치당 평균" the apps show.
    func metricAverages(for project: String?) -> [MetricAverage] {
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

    /// 0/1 flags as a share of this project's installs.
    func flagShares(for project: String?) -> [FlagShare] {
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

    /// Install counts by one snapshot field (version, platform, OS, locale).
    func distribution(for project: String?, by field: KeyPath<UsageSnapshot, String>) -> [DistributionBucket] {
        var counts: [String: Int] = [:]
        for snapshot in snapshots(for: project) {
            counts[snapshot[keyPath: field], default: 0] += 1
        }
        return counts
            .map { DistributionBucket(key: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.key.localizedStandardCompare($1.key) == .orderedDescending : $0.count > $1.count }
    }

    // MARK: - Trend

    /// A continuous series with empty buckets filled in, so the chart has no
    /// gaps. Built from `occurredAt`, never the record's creation date:
    /// backfilled days would otherwise all land on the day they were uploaded.
    func trend(for project: String?, unit: TrendUnit, calendar: Calendar = .current) -> [TrendPoint] {
        func bucketStart(_ date: Date) -> Date? {
            calendar.dateInterval(of: unit.component, for: date)?.start
        }

        var eventCounts: [Date: Int] = [:]
        var installsByBucket: [Date: Set<String>] = [:]
        for event in events(for: project) {
            guard let start = bucketStart(event.occurredAt) else { continue }
            eventCounts[start, default: 0] += 1
            if let install = event.installID {
                installsByBucket[start, default: []].insert(install)
            }
        }

        var newInstalls: [Date: Int] = [:]
        for snapshot in snapshots(for: project) {
            guard let installed = snapshot.installDate, let start = bucketStart(installed) else { continue }
            newInstalls[start, default: 0] += 1
        }

        let starts = Set(eventCounts.keys).union(installsByBucket.keys).union(newInstalls.keys)
        guard let first = starts.min(), let today = bucketStart(Date()) else { return [] }
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
        return points
    }
}

//
//  FeedbackStore+Projects.swift
//  FeedbackHubViewer
//
//  The numbers the project list and the 통계 screen read: which projects exist,
//  how busy each one is, and the feedback statistics for one of them.
//
//  Every one of these is a pure function of the fetched records, so each goes
//  through `memoized` and is computed once per refresh rather than once per
//  row per frame — see `FeedbackStore+Derived.swift` for why that matters.
//

import Foundation

extension FeedbackStore {

    // MARK: - Which projects, in what order

    /// Distinct project keys present in the data, ordered by feedback count
    /// (descending). Records without a project field collapse into the single
    /// `Feedback.unclassifiedProject` bucket.
    var availableProjects: [String] {
        projectCounts.map(\.key)
    }

    /// (key, count) pairs, most feedback first, for the sidebar list. `key` is
    /// the grouping identity (appId); resolve its label with `displayName(for:)`.
    var projectCounts: [(key: String, count: Int)] {
        memoized(\.projectCounts) {
            var buckets: [String: Int] = [:]
            // Every project the hub knows about, not just the ones that have sent
            // feedback: an app that only reports usage or only crashed is still an
            // app of yours, and leaving it out of the list makes its data
            // unreachable. Those come in with a feedback count of zero.
            for key in allProjectKeys { buckets[key] = 0 }
            for fb in allFeedback { buckets[fb.projectKey, default: 0] += 1 }
            let traffic = trafficByProject
            return buckets
                .map { (key: $0.key, count: $0.value) }
                .sorted { lhs, rhs in ordered(lhs.key, lhs.count, rhs.key, rhs.count, traffic: traffic) }
        }
    }

    /// Per-project rolled-up numbers for the overview grid, ordered the same
    /// way as `projectCounts` (most feedback first, "미분류" last).
    var projectSummaries: [ProjectSummary] {
        memoized(\.projectSummaries) {
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            // Seeded with every known project (see `projectCounts`) so an app that
            // has usage or diagnostics but no feedback yet still gets a card.
            var grouped: [String: [Feedback]] = [:]
            for key in allProjectKeys { grouped[key] = [] }
            for fb in allFeedback { grouped[fb.projectKey, default: []].append(fb) }
            let traffic = trafficByProject

            return grouped.map { key, items in
                let ratings = items.compactMap(\.rating)
                let average = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
                let last7 = items.filter { ($0.createdAt ?? .distantPast) >= weekAgo }.count
                let latest = items.compactMap(\.createdAt).max()
                return ProjectSummary(project: key, displayName: displayName(for: key),
                                      count: items.count, averageRating: average,
                                      last7Days: last7, latest: latest,
                                      unreadCount: countUnread(in: items))
            }
            .sorted { ordered($0.project, $0.count, $1.project, $1.count, traffic: traffic) }
        }
    }

    /// How busy a project is right now. "트래픽" here is the apps' own
    /// vocabulary: 사용 건수 = events in the last 7 days, 활동 사용자 = distinct
    /// installs behind them, 설치 = UsageSnapshot records.
    struct Traffic {
        let events7: Int
        let activeInstalls7: Int
        let installs: Int
        let totalEvents: Int
        /// Daily event counts for the last 14 days (oldest first) — the shape
        /// behind the number, drawn as a sparkline on every project row.
        let sparkline: [DayCount]

        var hasUsageData: Bool { installs > 0 || totalEvents > 0 }

        static let none = Traffic(events7: 0, activeInstalls7: 0, installs: 0,
                                  totalEvents: 0, sparkline: [])
    }

    /// Traffic per project in one pass. The lists sort against this map rather
    /// than calling `usage(for:)` inside a comparison, which would re-aggregate
    /// every record for every comparison.
    var trafficByProject: [String: Traffic] {
        memoized(\.trafficByProject) {
        let calendar = Calendar.current
        // Day buckets, not raw events: this used to be a pass over the whole
        // event stream per refresh, and the stream is the one thing that grows
        // without bound. Reading the sums instead makes the cost depend on how
        // many *days* the hub has seen, not how many events.
        let axis = UsageRollups.recentDayKeys(14, calendar: calendar)
        let weekKeys = Set(UsageRollups.windowKeys(days: 7, calendar: calendar))

        var installs: [String: Int] = [:]
        for snapshot in allSnapshots {
            installs[snapshot.projectKey, default: 0] += 1
        }

        var result: [String: Traffic] = [:]
        for key in rollups.projectKeys.subtracting(hiddenProjects).union(installs.keys) {
            let days = rollups.days(for: key)
            var total = 0
            var events7 = 0
            var active: Set<String> = []
            for (day, bucket) in days {
                total += bucket.events
                guard weekKeys.contains(day) else { continue }
                events7 += bucket.events
                active.formUnion(bucket.installs)
            }
            result[key] = Traffic(events7: events7,
                                  activeInstalls7: active.count,
                                  installs: installs[key] ?? 0,
                                  totalEvents: total,
                                  sparkline: axis.map { DayCount(date: $0.date, count: days[$0.key]?.events ?? 0) })
        }
        return result
        }
    }

    func traffic(for project: String) -> Traffic {
        trafficByProject[project] ?? .none
    }

    /// Every project's traffic added together — the 전체 프로젝트 row's shape.
    var overallTraffic: Traffic {
        memoized(\.overallTraffic) {
        let all = Array(trafficByProject.values)
        guard let axis = all.first?.sparkline else { return .none }
        var summed = axis.map { DayCount(date: $0.date, count: 0) }
        for traffic in all {
            for (index, point) in traffic.sparkline.enumerated() where index < summed.count {
                summed[index] = DayCount(date: summed[index].date,
                                         count: summed[index].count + point.count)
            }
        }
        let value = Traffic(events7: all.reduce(0) { $0 + $1.events7 },
                            // Installs are anonymous per app, so "활동 사용자"
                            // only adds up as a sum of each app's own count.
                            activeInstalls7: all.reduce(0) { $0 + $1.activeInstalls7 },
                            installs: all.reduce(0) { $0 + $1.installs },
                            totalEvents: all.reduce(0) { $0 + $1.totalEvents },
                            sparkline: summed)
        return value
        }
    }

    /// Busiest app first. Which app is being *used* the most is what decides
    /// where to look first, so traffic leads and the feedback count only
    /// breaks ties. 미분류 always sits at the bottom.
    private func ordered(_ k1: String, _ c1: Int, _ k2: String, _ c2: Int,
                         traffic: [String: Traffic]) -> Bool {
        if k1 == Feedback.unclassifiedProject { return false }
        if k2 == Feedback.unclassifiedProject { return true }

        let t1 = traffic[k1] ?? .none
        let t2 = traffic[k2] ?? .none
        if t1.events7 != t2.events7 { return t1.events7 > t2.events7 }
        if t1.activeInstalls7 != t2.activeInstalls7 { return t1.activeInstalls7 > t2.activeInstalls7 }
        if t1.installs != t2.installs { return t1.installs > t2.installs }
        if c1 != c2 { return c1 > c2 }
        return displayName(for: k1).localizedStandardCompare(displayName(for: k2)) == .orderedAscending
    }

    var availableVersions: [String] {
        memoized(\.availableVersions) {
            let versions = Set(allFeedback.compactMap { $0.appVersion?.trimmed }.filter { !$0.isEmpty })
            return versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        }
    }

    /// All feedback narrowed to the selected project only (ignoring search /
    /// version / rating). This is the base set for statistics so the whole
    /// dashboard can focus on one project. `nil` selection == every project.
    var scopedFeedback: [Feedback] { feedback(for: selectedProject) }

    var filteredFeedback: [Feedback] {
        var items = scopedFeedback

        // 확인한 피드백은 기본적으로 목록에서 빠진다. 통계는 `scopedFeedback`을
        // 그대로 쓰므로 숫자에서는 사라지지 않는다.
        if !showHandled {
            items = items.filter { !handledIDs.contains($0.id) }
        }

        if let version = selectedVersion {
            items = items.filter { $0.appVersion == version }
        }

        if minimumRating > 0 {
            items = items.filter { ($0.rating ?? 0) >= minimumRating }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter { fb in
                fb.text.lowercased().contains(query)
                || (fb.appVersion?.lowercased().contains(query) ?? false)
                || (fb.deviceModel?.lowercased().contains(query) ?? false)
                || (fb.contactEmail?.lowercased().contains(query) ?? false)
                || fb.allFields.contains { $0.value.lowercased().contains(query) }
            }
        }

        switch sortOption {
        case .newest:
            items.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .oldest:
            items.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .ratingHigh:
            items.sort { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .ratingLow:
            items.sort { ($0.rating ?? Int.max) < ($1.rating ?? Int.max) }
        }

        return items
    }

    // MARK: - Feedback statistics

    struct Stats {
        var total: Int
        var averageRating: Double?
        var ratingCounts: [(rating: Int, count: Int)]   // 5..1
        var versionCounts: [(version: String, count: Int)]
        var last7Days: Int
    }

    /// Stats for the current scope; `stats(for:)` computes any scope.
    var stats: Stats { stats(for: selectedProject) }
    /// Stats across every visible project, whatever the current scope is —
    /// what the 전체 프로젝트 card shows.
    var overallStats: Stats { stats(for: nil) }

    func stats(for project: String?) -> Stats {
        memoized(\.stats, project) {
        let source = feedback(for: project)
        let total = source.count

        let ratings = source.compactMap { $0.rating }
        let average = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)

        var ratingBuckets: [Int: Int] = [:]
        for r in ratings { ratingBuckets[r, default: 0] += 1 }
        let ratingCounts = (1...5).reversed().map { (rating: $0, count: ratingBuckets[$0] ?? 0) }

        var versionBuckets: [String: Int] = [:]
        for fb in source {
            guard let v = fb.appVersion?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { continue }
            versionBuckets[v, default: 0] += 1
        }
        let versionCounts = versionBuckets
            .map { (version: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let last7 = source.filter { ($0.createdAt ?? .distantPast) >= weekAgo }.count

        let value = Stats(total: total,
                          averageRating: average,
                          ratingCounts: ratingCounts,
                          versionCounts: versionCounts,
                          last7Days: last7)
        return value
        }
    }

    /// (category, count) pairs from the LeeoKit `type` field, most common first.
    /// Records without a type collapse into a "기타" bucket.
    var typeCounts: [(type: String, count: Int)] {
        var buckets: [String: Int] = [:]
        for fb in scopedFeedback {
            let key = fb.feedbackType?.trimmingCharacters(in: .whitespaces)
            buckets[(key?.isEmpty == false ? key! : "기타"), default: 0] += 1
        }
        return buckets
            .map { (type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// The newest feedback in the current project scope. Used by the compact
    /// overview, which shows the latest items instead of leaving space empty.
    func recentFeedback(limit: Int) -> [Feedback] {
        let source = showHandled ? scopedFeedback : scopedFeedback.filter { !handledIDs.contains($0.id) }
        return Array(source
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(limit))
    }

    /// Daily feedback counts for the last `days` days, oldest first. Days with
    /// no feedback are included as zero so the trend chart has no gaps.
    func dailyCounts(days: Int = 30) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        var buckets: [Date: Int] = [:]
        for fb in scopedFeedback {
            guard let created = fb.createdAt else { continue }
            let day = cal.startOfDay(for: created)
            if day >= start { buckets[day, default: 0] += 1 }
        }

        return (0..<days).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (date: day, count: buckets[day] ?? 0)
        }
    }
}

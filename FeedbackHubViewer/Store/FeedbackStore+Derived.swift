//
//  FeedbackStore+Derived.swift
//  FeedbackHubViewer
//
//  The rollup cache, and the scoping every screen reads through.
//
//  Everything on screen is derived from the four record arrays, and SwiftUI
//  asks for it again on every `body` — for every row, on every frame.
//  Aggregating there costs a pass over every record *per row*: the project list
//  was O(프로젝트 수 × 레코드 수) per frame for numbers that only change when a
//  refresh lands. So each rollup is computed once and kept here until one of
//  its inputs moves.
//
//  The trade to keep in mind: a "최근 7일" window is frozen at the moment it was
//  computed instead of following the clock. It moves on the next refresh — at
//  worst `autoRefreshInterval` away, and always at least once per launch —
//  which is far finer than the day-sized buckets it feeds.
//

import Foundation

extension FeedbackStore {

    // MARK: - The cache

    struct Derived {
        // The visible records: hidden projects taken out.
        var feedback: [Feedback]?
        var snapshots: [UsageSnapshot]?
        var events: [UsageEvent]?
        var crashes: [CrashReport]?

        // The same records grouped by project, so every `…(for:)` accessor is
        // a dictionary lookup instead of a filter over the whole array.
        var feedbackByProject: [String: [Feedback]]?
        var snapshotsByProject: [String: [UsageSnapshot]]?
        var eventsByProject: [String: [UsageEvent]]?
        var crashesByProject: [String: [CrashReport]]?

        var projectKeys: [String]?
        var projectCounts: [(key: String, count: Int)]?
        var projectSummaries: [ProjectSummary]?
        var hiddenProjectEntries: [(key: String, displayName: String, records: Int)]?
        var availableVersions: [String]?

        var trafficByProject: [String: Traffic]?
        var overallTraffic: Traffic?
        var crashingProjects: [(key: String, displayName: String, total: Int, last7Days: Int)]?

        // Per scope — the key is the project, `nil` meaning 전체 프로젝트.
        var stats: [String?: Stats] = [:]
        var usage: [String?: ProjectUsage] = [:]
        var crashSummary: [String?: CrashSummary] = [:]
        var crashIssues: [String?: [CrashIssue]] = [:]
        var eventStats: [String?: [EventStat]] = [:]
        var eventTallies: [String?: [String: UsageNameTotal]] = [:]
        var eventLog: [String?: [UsageEvent]] = [:]
        var metricAverages: [String?: [MetricAverage]] = [:]
        var flagShares: [String?: [FlagShare]] = [:]
        var distribution: [DistributionKey: [DistributionBucket]] = [:]
        var trend: [TrendKey: [TrendPoint]] = [:]
        // The value is itself optional — "잴 활동이 없다"는 계산 결과이지 미계산이
        // 아니므로, 그것도 캐시해야 매 프레임 다시 훑지 않는다.
        var carryingCapacity: [CapacityKey: CarryingCapacity?] = [:]
    }

    // MARK: - Reading through the cache

    /// Compute `body` once and keep it in `slot` until something invalidates it.
    ///
    /// Every rollup in the store is read this way. Written out by hand it is
    /// three lines of bookkeeping around one line of work, thirty times over —
    /// and the failure mode of getting it wrong is silent: a slot that is
    /// filled but never read just makes the app slow again.
    func memoized<Value>(_ slot: WritableKeyPath<Derived, Value?>,
                         _ body: () -> Value) -> Value {
        if let cached = derived[keyPath: slot] { return cached }
        let value = body()
        derived[keyPath: slot] = value
        return value
    }

    /// The same, for the rollups that are computed per scope — one entry per
    /// project, plus `nil` for 전체 프로젝트.
    func memoized<Key: Hashable, Value>(_ slot: WritableKeyPath<Derived, [Key: Value]>,
                                        _ key: Key,
                                        _ body: () -> Value) -> Value {
        if let cached = derived[keyPath: slot][key] { return cached }
        let value = body()
        derived[keyPath: slot][key] = value
        return value
    }

    // MARK: - Invalidation

    /// Throw every rollup away. Only for changes that move the records
    /// themselves — a fetch, or hiding a project, which changes what the
    /// records *are* for every screen.
    func invalidateDerived() { derived = Derived() }

    /// Drop only what the read / 확인 sets feed. Marking one feedback read used
    /// to invalidate everything, so the next frame re-aggregated every event in
    /// the hub to redraw a dot — with a few thousand records that is the pause
    /// you feel on a tap. Nothing but the per-project unread count depends on
    /// these sets.
    func invalidateReadState() {
        derived.projectSummaries = nil
    }

    /// Drop only what an app's display name feeds: the lists that show it and
    /// the orderings that compare on it. Trends, distributions and event
    /// statistics do not know a project's label exists.
    func invalidateLabels() {
        derived.projectKeys = nil
        derived.projectCounts = nil
        derived.projectSummaries = nil
        derived.hiddenProjectEntries = nil
        derived.crashingProjects = nil
        derived.usage = [:]
    }

    /// Drop what reads the day buckets. Folding new events changes the usage
    /// numbers and nothing else — not feedback, not diagnostics.
    func invalidateUsageRollups() {
        derived.projectKeys = nil
        derived.projectCounts = nil
        derived.projectSummaries = nil
        derived.trafficByProject = nil
        derived.overallTraffic = nil
        derived.usage = [:]
        derived.eventStats = [:]
        derived.eventTallies = [:]
        derived.trend = [:]
        derived.carryingCapacity = [:]
    }

    // MARK: - The visible records

    /// The four record arrays with hidden projects taken out. Every screen
    /// reads these rather than the `fetched…` arrays, which are what came off
    /// the network and are only for merging and for counting what a hidden
    /// project still holds.
    var allFeedback: [Feedback] {
        memoized(\.feedback) { visible(fetchedFeedback) }
    }
    var allSnapshots: [UsageSnapshot] {
        memoized(\.snapshots) { visible(fetchedSnapshots) }
    }
    var allEvents: [UsageEvent] {
        memoized(\.events) { visible(fetchedEvents) }
    }
    var allCrashes: [CrashReport] {
        memoized(\.crashes) { visible(fetchedCrashes) }
    }

    private func visible<Record: HubRecord>(_ records: [Record]) -> [Record] {
        hiddenProjects.isEmpty
            ? records
            : records.filter { !hiddenProjects.contains($0.projectKey) }
    }

    // MARK: - Grouped by project

    /// The visible records grouped by project key, built in one pass.
    /// Everything that used to write `allFeedback.filter { $0.projectKey == key }`
    /// reads these instead — that filter inside a per-row call is the O(N²)
    /// shape that made the project list stutter.
    var feedbackByProject: [String: [Feedback]] {
        memoized(\.feedbackByProject) { Dictionary(grouping: allFeedback, by: \.projectKey) }
    }
    var snapshotsByProject: [String: [UsageSnapshot]] {
        memoized(\.snapshotsByProject) { Dictionary(grouping: allSnapshots, by: \.projectKey) }
    }
    var eventsByProject: [String: [UsageEvent]] {
        memoized(\.eventsByProject) { Dictionary(grouping: allEvents, by: \.projectKey) }
    }
    var crashesByProject: [String: [CrashReport]] {
        memoized(\.crashesByProject) { Dictionary(grouping: allCrashes, by: \.projectKey) }
    }

    /// Feedback for one project, or all of it when `project` is nil.
    func feedback(for project: String?) -> [Feedback] {
        scoped(feedbackByProject, allFeedback, project)
    }

    /// Usage snapshots for one project, or all of them when `project` is nil.
    func snapshots(for project: String?) -> [UsageSnapshot] {
        scoped(snapshotsByProject, allSnapshots, project)
    }

    /// The individual events this device still holds — the last
    /// `FeedbackStore.rawEventRetentionDays` days, not the whole history. Only
    /// `eventLog(for:)` should want these; every *number* comes from `rollups`,
    /// which goes all the way back.
    func events(for project: String?) -> [UsageEvent] {
        scoped(eventsByProject, allEvents, project)
    }

    func crashes(for project: String?) -> [CrashReport] {
        scoped(crashesByProject, allCrashes, project)
    }

    private func scoped<Record>(_ grouped: [String: [Record]],
                                _ all: [Record],
                                _ project: String?) -> [Record] {
        guard let project else { return all }
        return grouped[project] ?? []
    }
}

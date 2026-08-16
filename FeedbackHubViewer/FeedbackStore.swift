//
//  FeedbackStore.swift
//  FeedbackHubViewer
//
//  Observable state for the app: holds the fetched feedback, exposes the
//  filtered/sorted view, computes summary statistics, and drives optional
//  auto-refresh.
//

import Foundation
import SwiftUI
import CloudKit

@MainActor
final class FeedbackStore: ObservableObject {

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "최신순"
        case oldest = "오래된순"
        case ratingHigh = "별점 높은순"
        case ratingLow = "별점 낮은순"
        var id: String { rawValue }
    }

    /// Which pane the middle column shows: a per-project overview grid or the
    /// statistics dashboard. The feedback list is not a peer of these — it is
    /// pushed on top of the overview (see `listPath`).
    enum ViewMode: String, CaseIterable, Identifiable {
        case overview = "개요"
        case stats = "통계"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .stats: return "chart.bar"
            }
        }
    }

    /// The feedback list pushed on top of the overview. `project` is the scope
    /// the list was opened with (nil == 전체 프로젝트); the list reads the live
    /// filters itself, so the value only identifies the pushed screen.
    struct ListRoute: Hashable {
        let project: String?
    }

    /// The statistics dashboard pushed on top of the per-project trend list.
    struct StatsRoute: Hashable {
        let project: String?
    }

    /// Every diagnostic in one list — what the red ⚠︎ on a project row is
    /// about. `project` nil == 전체 프로젝트.
    struct CrashRoute: Hashable {
        let project: String?
    }

    /// One day's feedback count, for the trend charts.
    struct DayCount: Identifiable, Hashable {
        var id: Date { date }
        let date: Date
        let count: Int
    }

    /// One project's headline metrics *plus* how they moved: the last 7 days
    /// against the 7 days before that. Drives the statistics list.
    struct ProjectTrend: Identifiable {
        var id: String { project }
        /// Grouping key (appId or appName); nil-project rows use the key.
        let project: String
        let displayName: String
        let total: Int
        let unreadCount: Int
        let last7Days: Int
        let previous7Days: Int
        /// Average rating over the last 7 days, and over the 7 before that.
        let recentAverageRating: Double?
        let previousAverageRating: Double?
        /// Average over every record, shown as the standing number.
        let averageRating: Double?
        let latest: Date?
        /// Daily counts for the sparkline (oldest first).
        let sparkline: [DayCount]

        var isUnclassified: Bool { project == Feedback.unclassifiedProject }
        /// Change in weekly volume. Positive == more feedback than last week.
        var countDelta: Int { last7Days - previous7Days }
        /// Change in average rating, only when both weeks have ratings.
        var ratingDelta: Double? {
            guard let recent = recentAverageRating, let previous = previousAverageRating else { return nil }
            return recent - previous
        }
    }

    /// One project's rolled-up numbers, for the overview cards.
    struct ProjectSummary: Identifiable {
        var id: String { project }
        /// Grouping key (appId or appName).
        let project: String
        /// Human-readable label resolved from the key.
        let displayName: String
        let count: Int
        let averageRating: Double?
        let last7Days: Int
        let latest: Date?
        /// Feedback in this project the user has never opened.
        let unreadCount: Int
        /// True for the bucket holding records with no project field.
        var isUnclassified: Bool { project == Feedback.unclassifiedProject }
    }

    // Raw data, exactly as fetched. The `all…` properties below are what the UI
    // reads: the same records with hidden projects taken out.
    @Published private(set) var fetchedFeedback: [Feedback] = []
    @Published private(set) var resolvedRecordType: String?
    /// Usage statistics exactly as the apps reported them (see `Usage.swift`).
    @Published private(set) var fetchedSnapshots: [UsageSnapshot] = []
    @Published private(set) var fetchedEvents: [UsageEvent] = []
    /// MetricKit diagnostics (`CrashReport`).
    @Published private(set) var fetchedCrashes: [CrashReport] = []

    var allFeedback: [Feedback] {
        hiddenProjects.isEmpty ? fetchedFeedback : fetchedFeedback.filter { !hiddenProjects.contains($0.projectKey) }
    }
    var allSnapshots: [UsageSnapshot] {
        hiddenProjects.isEmpty ? fetchedSnapshots : fetchedSnapshots.filter { !hiddenProjects.contains($0.projectKey) }
    }
    var allEvents: [UsageEvent] {
        hiddenProjects.isEmpty ? fetchedEvents : fetchedEvents.filter { !hiddenProjects.contains($0.projectKey) }
    }
    var allCrashes: [CrashReport] {
        hiddenProjects.isEmpty ? fetchedCrashes : fetchedCrashes.filter { !hiddenProjects.contains($0.projectKey) }
    }
    /// Why usage data is missing, when it is. Usage has its own schema and read
    /// permission, so it can fail on its own while feedback loads.
    @Published var usageNotice: String?

    // UI state
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var lastUpdated: Date?
    /// This account's CloudKit user record name — the value to register in an
    /// admin Security Role so it can read feedback. Shown in the toolbar.
    @Published var userRecordName: String?

    // Filters / sorting
    @Published var viewMode: ViewMode = .overview {
        // Switching pane pops whatever was pushed on top of the overview, so
        // coming back to 개요 always lands on the project grid.
        didSet {
            guard viewMode != oldValue else { return }
            listPath = NavigationPath()
            statsPath = NavigationPath()
        }
    }
    /// What is pushed on top of the overview: the feedback list, and on iOS a
    /// single feedback's detail after that.
    @Published var listPath = NavigationPath()
    /// What is pushed on top of the statistics list: one project's dashboard.
    @Published var statsPath = NavigationPath()
    @Published var searchText = ""
    @Published var sortOption: SortOption = .newest
    @Published var selectedProject: String? = nil     // nil == all projects
    @Published var selectedVersion: String? = nil     // nil == all versions
    @Published var minimumRating: Int = 0             // 0 == any rating

    // Auto refresh
    @Published var autoRefresh = false {
        didSet { autoRefresh ? startAutoRefresh() : stopAutoRefresh() }
    }

    /// Post a notification when a refresh finds new feedback or diagnostics,
    /// and keep the app icon badge on the unread count. Persisted per device.
    @Published var notificationsEnabled = false {
        didSet {
            guard notificationsEnabled != oldValue else { return }
            defaults.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
            if notificationsEnabled {
                Task {
                    notificationsAuthorized = await NotificationService.requestAuthorization()
                    refreshBadge()
                }
            } else {
                NotificationService.setBadge(0)
            }
        }
    }
    /// False when the system denied notifications — the toggle stays on but the
    /// UI can explain why nothing shows up.
    @Published private(set) var notificationsAuthorized = true
    /// Seconds between automatic refreshes.
    let autoRefreshInterval: TimeInterval = 60

    private let service = CloudKitService()
    private var autoRefreshTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        readIDs = Set(defaults.stringArray(forKey: Self.readIDsKey) ?? [])
        hiddenProjects = Set(defaults.stringArray(forKey: Self.hiddenProjectsKey) ?? [])
        notificationsEnabled = defaults.bool(forKey: Self.notificationsEnabledKey)
        seenFeedbackIDs = defaults.stringArray(forKey: Self.seenFeedbackIDsKey).map(Set.init)
        seenCrashIDs = defaults.stringArray(forKey: Self.seenCrashIDsKey).map(Set.init)
        if notificationsEnabled {
            Task { notificationsAuthorized = await NotificationService.isAuthorized() }
        }
    }

    /// Which half of the container this build reads. Fixed at build time by the
    /// iCloud entitlement — pick the scheme to change it (see README §2-1).
    var environment: CloudKitEnvironment { CloudKitService.environment }
    var environmentDescription: String { environment.displayName }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        noticeMessage = await service.accountStatusMessage()
        userRecordName = await service.currentUserRecordName()

        // Usage statistics live in their own record types with their own read
        // permission, so they are loaded separately and never fail the feedback
        // load — the dashboard shows whatever came back.
        let usage = (try? await service.fetchUsage()) ?? CloudKitService.UsageOutcome()
        fetchedSnapshots = usage.snapshots
        fetchedEvents = usage.events
        fetchedCrashes = usage.crashes
        usageNotice = usage.notice

        do {
            let outcome = try await service.fetchFeedback()
            fetchedFeedback = outcome.feedback
            resolvedRecordType = outcome.resolvedRecordType
            learnAppNames(from: outcome.feedback)
            lastUpdated = Date()
            if outcome.feedback.isEmpty && errorMessage == nil {
                noticeMessage = noticeMessage ?? "표시할 피드백이 없습니다. 레코드 타입 이름이 다르거나(코드의 candidateRecordTypes 확인), CloudKit 대시보드에서 필드가 Queryable로 설정되지 않았을 수 있습니다."
            }
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            // A permission failure here almost always means this iCloud account
            // isn't registered in an admin Security Role with read access. Show
            // the user record name so it can be copied into the CloudKit Console.
            if Self.isPermissionError(error), let name = await service.currentUserRecordName() {
                errorMessage = (errorMessage ?? "")
                    + "\n\n등록할 내 CloudKit User Record Name:\n\(name)\n\n"
                    + "CloudKit Console → 컨테이너 → Security Roles에서 admin 역할에 이 값을 추가하고 피드백 레코드 타입에 read 권한을 준 뒤, Production으로 배포하세요."
            }
        }

        // Only after both fetches: a notification should reflect the whole
        // refresh, and the badge the unread count it leaves behind.
        announceNewRecords()
        refreshBadge()
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let ck = error as NSError
        return ck.domain == CKErrorDomain && ck.code == CKError.permissionFailure.rawValue
    }

    // MARK: - Notifications

    private static let notificationsEnabledKey = "notificationsEnabled"
    private static let seenFeedbackIDsKey = "seenFeedbackIDs"
    private static let seenCrashIDsKey = "seenCrashIDs"

    /// Record names seen by a previous refresh. `nil` means "never loaded on
    /// this device": the first load seeds the set silently instead of
    /// announcing every record that was already in the hub.
    private var seenFeedbackIDs: Set<String>?
    private var seenCrashIDs: Set<String>?

    /// Compare what just arrived against what this device had already seen and
    /// announce the difference. Hidden projects are excluded — a project you
    /// hid should not interrupt you.
    private func announceNewRecords() {
        let feedbackIDs = Set(allFeedback.map(\.id))
        let crashIDs = Set(allCrashes.map(\.id))

        if let previous = seenFeedbackIDs {
            let fresh = allFeedback.filter { !previous.contains($0.id) }
            if notificationsEnabled, !fresh.isEmpty {
                let projects = Array(Set(fresh.map { displayName(for: $0.projectKey) })).sorted()
                NotificationService.notifyNewFeedback(count: fresh.count, projects: projects)
            }
        }
        if let previous = seenCrashIDs {
            let fresh = allCrashes.filter { !previous.contains($0.id) }
            if notificationsEnabled, !fresh.isEmpty {
                let projects = Array(Set(fresh.map { displayName(for: $0.projectKey) })).sorted()
                NotificationService.notifyNewCrashes(count: fresh.count, projects: projects)
            }
        }

        seenFeedbackIDs = feedbackIDs
        seenCrashIDs = crashIDs
        defaults.set(Array(feedbackIDs), forKey: Self.seenFeedbackIDsKey)
        defaults.set(Array(crashIDs), forKey: Self.seenCrashIDsKey)
    }

    /// The app icon badge follows the unread feedback count.
    func refreshBadge() {
        NotificationService.setBadge(notificationsEnabled ? unreadCount : 0)
    }

    // MARK: - Read / unread

    /// Record names the user has already opened. Persisted, so a relaunch
    /// doesn't resurface feedback that was already dealt with.
    @Published private(set) var readIDs: Set<String> = []
    private static let readIDsKey = "readFeedbackIDs"

    func isUnread(_ feedback: Feedback) -> Bool { !readIDs.contains(feedback.id) }

    /// Unread across every project — the number the tab badge shows.
    var unreadCount: Int { countUnread(in: allFeedback) }

    /// Unread inside the current project scope.
    var scopedUnreadCount: Int { countUnread(in: scopedFeedback) }

    private func countUnread(in items: [Feedback]) -> Int {
        items.reduce(0) { $0 + (readIDs.contains($1.id) ? 0 : 1) }
    }

    /// Called when a feedback's detail is shown.
    func markRead(_ feedback: Feedback) {
        guard !readIDs.contains(feedback.id) else { return }
        readIDs.insert(feedback.id)
        persistReadIDs()
        refreshBadge()
    }

    /// Clear the badges for one project, or for everything when `project` is nil.
    func markAllRead(project: String? = nil) {
        let targets = project.map { key in allFeedback.filter { $0.projectKey == key } } ?? allFeedback
        let ids = Set(targets.map(\.id))
        guard !ids.isSubset(of: readIDs) else { return }
        readIDs.formUnion(ids)
        persistReadIDs()
        refreshBadge()
    }

    /// Mark everything currently loaded as read *without* touching the stored
    /// set's older entries — used by the "모두 읽음" affordances.
    private func persistReadIDs() {
        defaults.set(Array(readIDs), forKey: Self.readIDsKey)
    }

    // MARK: - Hidden projects

    /// Projects taken out of this viewer. Nothing is deleted from CloudKit —
    /// the records stay in the hub and come back the moment the project is
    /// shown again. Persisted per device.
    @Published private(set) var hiddenProjects: Set<String> = []
    private static let hiddenProjectsKey = "hiddenProjects"

    func isHidden(_ project: String) -> Bool { hiddenProjects.contains(project) }

    /// Hide one project's feedback, usage, events and diagnostics at once.
    func hideProject(_ project: String) {
        guard !hiddenProjects.contains(project) else { return }
        hiddenProjects.insert(project)
        persistHiddenProjects()
        refreshBadge()

        // A hidden project must not stay as the active scope, or every screen
        // ends up filtered to something that is no longer listed anywhere.
        if selectedProject == project {
            selectedProject = nil
            listPath = NavigationPath()
            statsPath = NavigationPath()
        }
    }

    func showProject(_ project: String) {
        guard hiddenProjects.remove(project) != nil else { return }
        persistHiddenProjects()
        refreshBadge()
    }

    func showAllProjects() {
        guard !hiddenProjects.isEmpty else { return }
        hiddenProjects.removeAll()
        persistHiddenProjects()
        refreshBadge()
    }

    /// Hidden projects that actually have records, newest data first, for the
    /// "숨긴 프로젝트" list. A key with nothing behind it any more is dropped.
    var hiddenProjectEntries: [(key: String, displayName: String, records: Int)] {
        hiddenProjects.map { key in
            let records = fetchedFeedback.filter { $0.projectKey == key }.count
                + fetchedSnapshots.filter { $0.projectKey == key }.count
                + fetchedEvents.filter { $0.projectKey == key }.count
                + fetchedCrashes.filter { $0.projectKey == key }.count
            return (key: key, displayName: displayName(for: key), records: records)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func persistHiddenProjects() {
        defaults.set(Array(hiddenProjects), forKey: Self.hiddenProjectsKey)
    }

    // MARK: - Project name resolution

    /// Learned `appId → appName` from records that carry both. Lets records
    /// that only have an `appId` (older LeeoKit submissions) still show a
    /// human-readable name.
    @Published private(set) var learnedAppNames: [String: String] = [:]

    /// Manual `appId → 앱 이름` overrides for apps whose records never include an
    /// `appName` at all. Edit this to name legacy-only projects.
    /// 예: ["com.Ysoup.OldApp": "옛날앱"]
    var appNameOverrides: [String: String] = [:]

    private func learnAppNames(from feedback: [Feedback]) {
        var map: [String: String] = [:]
        for fb in feedback {
            guard let id = fb.appId?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
                  let name = fb.recordAppName else { continue }
            map[id] = name   // latest wins; records are fetched newest-first
        }
        // Usage records carry the pair too, and an app may report usage under an
        // appId that never appears in feedback (ClipKeyboard sends
        // "com.Ysoup.TokenMemo"). Without this those rows would be bare ids.
        for snapshot in fetchedSnapshots {
            guard let id = snapshot.appId?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
                  let name = snapshot.appName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  map[id] == nil else { continue }
            map[id] = name
        }
        for event in fetchedEvents {
            guard let id = event.appId?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
                  let name = event.appName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  map[id] == nil else { continue }
            map[id] = name
        }
        learnedAppNames = map
    }

    /// Human-readable name for a project key (an `appId`, an `appName`, or the
    /// unclassified bucket). Manual overrides win, then learned names, then the
    /// key itself (so a bare appId is still shown rather than hidden).
    func displayName(for key: String) -> String {
        if key == Feedback.unclassifiedProject { return key }
        if let override = appNameOverrides[key], !override.isEmpty { return override }
        if let learned = learnedAppNames[key], !learned.isEmpty { return learned }
        return key
    }

    // MARK: - Derived view

    /// Distinct project keys present in the data, ordered by feedback count
    /// (descending). Records without a project field collapse into the single
    /// `Feedback.unclassifiedProject` bucket.
    var availableProjects: [String] {
        projectCounts.map(\.key)
    }

    /// (key, count) pairs, most feedback first, for the sidebar list. `key` is
    /// the grouping identity (appId); resolve its label with `displayName(for:)`.
    var projectCounts: [(key: String, count: Int)] {
        var buckets: [String: Int] = [:]
        for fb in allFeedback { buckets[fb.projectKey, default: 0] += 1 }
        // Apps that report usage but have no feedback yet are still projects
        // this hub knows about — list them with a count of zero rather than
        // hiding them from the filter.
        for snapshot in allSnapshots { buckets[snapshot.projectKey] = buckets[snapshot.projectKey] ?? 0 }
        return buckets
            .map { (key: $0.key, count: $0.value) }
            .sorted { lhs, rhs in ordered(lhs.key, lhs.count, rhs.key, rhs.count) }
    }

    /// Per-project rolled-up numbers for the overview grid, ordered the same
    /// way as `projectCounts` (most feedback first, "미분류" last).
    var projectSummaries: [ProjectSummary] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        var grouped: [String: [Feedback]] = [:]
        for fb in allFeedback { grouped[fb.projectKey, default: []].append(fb) }

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
        .sorted { ordered($0.project, $0.count, $1.project, $1.count) }
    }

    /// Per-project metrics with week-over-week movement, ordered like
    /// `projectSummaries`. Drives the statistics list.
    var projectTrends: [ProjectTrend] {
        var grouped: [String: [Feedback]] = [:]
        for fb in allFeedback { grouped[fb.projectKey, default: []].append(fb) }
        return grouped
            .map { key, items in trend(key: key, displayName: displayName(for: key), items: items) }
            .sorted { ordered($0.project, $0.total, $1.project, $1.total) }
    }

    /// The same metrics across every project, for the "전체 프로젝트" row.
    var overallTrend: ProjectTrend {
        trend(key: "", displayName: "전체 프로젝트", items: allFeedback)
    }

    private func trend(key: String, displayName: String, items: [Feedback]) -> ProjectTrend {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)

        let recent = items.filter { ($0.createdAt ?? .distantPast) >= weekAgo }
        let previous = items.filter {
            guard let created = $0.createdAt else { return false }
            return created >= twoWeeksAgo && created < weekAgo
        }

        return ProjectTrend(
            project: key,
            displayName: displayName,
            total: items.count,
            unreadCount: countUnread(in: items),
            last7Days: recent.count,
            previous7Days: previous.count,
            recentAverageRating: Self.average(of: recent),
            previousAverageRating: Self.average(of: previous),
            averageRating: Self.average(of: items),
            latest: items.compactMap(\.createdAt).max(),
            sparkline: Self.dailyCounts(of: items, days: 14)
        )
    }

    private static func average(of items: [Feedback]) -> Double? {
        let ratings = items.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    /// Daily counts for `items` over the last `days` days, oldest first, with
    /// empty days included so a chart has no gaps.
    private static func dailyCounts(of items: [Feedback], days: Int) -> [DayCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        var buckets: [Date: Int] = [:]
        for fb in items {
            guard let created = fb.createdAt else { continue }
            let day = cal.startOfDay(for: created)
            if day >= start { buckets[day, default: 0] += 1 }
        }

        return (0..<days).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DayCount(date: day, count: buckets[day] ?? 0)
        }
    }

    /// Shared ordering: unclassified last, then by count desc, then by name.
    private func ordered(_ k1: String, _ c1: Int, _ k2: String, _ c2: Int) -> Bool {
        if k1 == Feedback.unclassifiedProject { return false }
        if k2 == Feedback.unclassifiedProject { return true }
        if c1 != c2 { return c1 > c2 }
        return displayName(for: k1).localizedStandardCompare(displayName(for: k2)) == .orderedAscending
    }

    var availableVersions: [String] {
        let versions = Set(allFeedback.compactMap { $0.appVersion?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        return versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    /// All feedback narrowed to the selected project only (ignoring search /
    /// version / rating). This is the base set for statistics so the whole
    /// dashboard can focus on one project. `nil` selection == every project.
    var scopedFeedback: [Feedback] {
        guard let key = selectedProject else { return allFeedback }
        return allFeedback.filter { $0.projectKey == key }
    }

    var filteredFeedback: [Feedback] {
        var items = scopedFeedback

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

    // MARK: - Statistics

    struct Stats {
        var total: Int
        var averageRating: Double?
        var ratingCounts: [(rating: Int, count: Int)]   // 5..1
        var versionCounts: [(version: String, count: Int)]
        var last7Days: Int
    }

    var stats: Stats {
        let source = scopedFeedback
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

        return Stats(total: total,
                     averageRating: average,
                     ratingCounts: ratingCounts,
                     versionCounts: versionCounts,
                     last7Days: last7)
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
        Array(scopedFeedback
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

    // MARK: - Auto refresh

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.autoRefreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.load()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Errors

    private static func friendlyMessage(for error: Error) -> String {
        let ck = error as NSError
        if ck.domain == CKErrorDomain {
            switch ck.code {
            case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
                return "네트워크에 연결할 수 없습니다. 인터넷 연결을 확인하세요."
            case CKError.notAuthenticated.rawValue:
                return "iCloud 인증이 필요합니다. 시스템 설정에서 iCloud에 로그인하세요."
            case CKError.permissionFailure.rawValue:
                return "이 데이터에 접근할 권한이 없습니다. CloudKit 대시보드의 공개 DB 보안 역할(Security Roles)을 확인하세요."
            case CKError.invalidArguments.rawValue:
                return "쿼리 인자가 올바르지 않습니다. CloudKit 대시보드에서 해당 필드가 Queryable/Sortable로 설정됐는지 확인하세요. (\(ck.localizedDescription))"
            default:
                return "CloudKit 오류: \(ck.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

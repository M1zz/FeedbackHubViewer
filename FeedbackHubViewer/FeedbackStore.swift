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

    /// What one project's screen shows. The project is the outer level of the
    /// app — these are the three things you can look at *inside* it, and they
    /// are peers of each other, never of the project.
    enum ProjectSection: String, CaseIterable, Identifiable {
        case feedback = "피드백"
        case stats = "통계"
        case crashes = "진단"
        /// App Store search — the only section that reads something other than
        /// the CloudKit hub (see `KeywordStore`). It sits here because it is
        /// still one thing you look at *inside* a project, which is what this
        /// enum means.
        case keywords = "키워드"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .feedback: return "text.bubble"
            case .stats: return "chart.bar"
            case .crashes: return "exclamationmark.triangle"
            case .keywords: return "magnifyingglass"
            }
        }
    }

    /// One project's screen, pushed on top of the project list. `project` nil
    /// == 전체 프로젝트. `section` is the tab to land on; nil keeps whichever
    /// section was open last.
    struct ProjectRoute: Hashable {
        let project: String?
        let section: ProjectSection?

        init(project: String?, section: ProjectSection? = nil) {
            self.project = project
            self.section = section
        }
    }

    /// One day's feedback count, for the trend charts.
    struct DayCount: Identifiable, Hashable {
        var id: Date { date }
        let date: Date
        let count: Int
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
    // reads: the same records with hidden projects taken out. Each of these
    // drops the derived-value cache, because every number on screen is rolled
    // up from them (see `Derived`).
    @Published private(set) var fetchedFeedback: [Feedback] = [] { didSet { invalidateDerived() } }
    @Published private(set) var resolvedRecordType: String?
    /// Usage statistics exactly as the apps reported them (see `Usage.swift`).
    @Published private(set) var fetchedSnapshots: [UsageSnapshot] = [] { didSet { invalidateDerived() } }
    @Published private(set) var fetchedEvents: [UsageEvent] = [] { didSet { invalidateDerived() } }
    /// MetricKit diagnostics (`CrashReport`).
    @Published private(set) var fetchedCrashes: [CrashReport] = [] { didSet { invalidateDerived() } }

    /// Usage events summed by day, once, when they arrived — see
    /// `UsageRollups`. This, not `fetchedEvents`, is what every usage number on
    /// screen is computed from: `fetchedEvents` only holds the recent window
    /// the 사용 내역 list shows individually.
    private(set) var rollups = UsageRollups() { didSet { invalidateUsageRollups() } }

    // MARK: - Derived-value cache

    /// Everything on screen is derived from the four arrays above, and SwiftUI
    /// asks for it again on every `body` — for every row, on every frame.
    /// Aggregating there costs a pass over every record *per row*: the project
    /// list was O(프로젝트 수 × 레코드 수) per frame for numbers that only
    /// change when a refresh lands. So each rollup is computed once and kept
    /// here until one of its inputs moves.
    ///
    /// The trade to keep in mind: a "최근 7일" window is frozen at the moment it
    /// was computed instead of following the clock. It moves on the next
    /// refresh — at worst `autoRefreshInterval` away, and always at least once
    /// per launch — which is far finer than the day-sized buckets it feeds.
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

    /// Not `private` only because the aggregation that fills it lives in
    /// `FeedbackStore+Usage.swift`.
    var derived = Derived()

    /// Throw every rollup away. Only for changes that move the records
    /// themselves — a fetch, or hiding a project, which changes what the
    /// records *are* for every screen.
    func invalidateDerived() { derived = Derived() }

    /// Drop only what the read / 확인 sets feed. Marking one feedback read used
    /// to invalidate everything, so the next frame re-aggregated every event in
    /// the hub to redraw a dot — with a few thousand records that is the pause
    /// you feel on a tap. Nothing but the per-project unread count depends on
    /// these sets.
    private func invalidateReadState() {
        derived.projectSummaries = nil
    }

    /// Drop only what an app's display name feeds: the lists that show it and
    /// the orderings that compare on it. Trends, distributions and event
    /// statistics do not know a project's label exists.
    private func invalidateLabels() {
        derived.projectKeys = nil
        derived.projectCounts = nil
        derived.projectSummaries = nil
        derived.hiddenProjectEntries = nil
        derived.crashingProjects = nil
        derived.usage = [:]
    }

    /// Drop what reads the day buckets. Folding new events changes the usage
    /// numbers and nothing else — not feedback, not diagnostics.
    private func invalidateUsageRollups() {
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

    var allFeedback: [Feedback] {
        if let cached = derived.feedback { return cached }
        let value = hiddenProjects.isEmpty
            ? fetchedFeedback
            : fetchedFeedback.filter { !hiddenProjects.contains($0.projectKey) }
        derived.feedback = value
        return value
    }
    var allSnapshots: [UsageSnapshot] {
        if let cached = derived.snapshots { return cached }
        let value = hiddenProjects.isEmpty
            ? fetchedSnapshots
            : fetchedSnapshots.filter { !hiddenProjects.contains($0.projectKey) }
        derived.snapshots = value
        return value
    }
    var allEvents: [UsageEvent] {
        if let cached = derived.events { return cached }
        let value = hiddenProjects.isEmpty
            ? fetchedEvents
            : fetchedEvents.filter { !hiddenProjects.contains($0.projectKey) }
        derived.events = value
        return value
    }
    var allCrashes: [CrashReport] {
        if let cached = derived.crashes { return cached }
        let value = hiddenProjects.isEmpty
            ? fetchedCrashes
            : fetchedCrashes.filter { !hiddenProjects.contains($0.projectKey) }
        derived.crashes = value
        return value
    }

    // MARK: - Grouped by project

    /// Visible feedback grouped by project key, built in one pass. Everything
    /// that used to write `allFeedback.filter { $0.projectKey == key }` reads
    /// this instead — that filter inside a per-row call is the O(N²) shape.
    var feedbackByProject: [String: [Feedback]] {
        if let cached = derived.feedbackByProject { return cached }
        let value = Dictionary(grouping: allFeedback, by: \.projectKey)
        derived.feedbackByProject = value
        return value
    }

    /// Feedback for one project, or all of it when `project` is nil.
    func feedback(for project: String?) -> [Feedback] {
        guard let project else { return allFeedback }
        return feedbackByProject[project] ?? []
    }

    /// Why usage data is missing, when it is. Usage has its own schema and read
    /// permission, so it can fail on its own while feedback loads.
    @Published var usageNotice: String?

    // UI state

    /// A network refresh is in flight. The screen keeps showing whatever the
    /// cache painted while this is true — only the small toolbar indicator and
    /// the refresh button react to it.
    @Published private(set) var isRefreshing = false
    /// What the in-flight refresh is doing, or `nil` when nothing is running.
    /// See `RefreshProgress` for why this is a step and a count rather than a
    /// percentage.
    @Published private(set) var refreshProgress: RefreshProgress?
    /// True only while a refresh is running with nothing to show yet: the
    /// condition the full-screen "불러오는 중…" spinners key off. With a cache on
    /// disk this is false from the first frame.
    var isLoading: Bool { isRefreshing && !hasContent }
    /// Whether there is anything on screen at all, from cache or from the
    /// network. Errors and empty states defer to it.
    var hasContent: Bool {
        // A hub whose raw events have all aged out of the retained window still
        // has every number on its statistics screen.
        hasFetchedRecords || !rollups.isEmpty
    }
    /// Whether any *record* is held, rollups aside. What the cache restore asks
    /// before painting: it must not overwrite a refresh that already landed.
    private var hasFetchedRecords: Bool {
        !fetchedFeedback.isEmpty || !fetchedSnapshots.isEmpty
            || !fetchedEvents.isEmpty || !fetchedCrashes.isEmpty
    }
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var lastUpdated: Date?
    /// This account's CloudKit user record name — the value to register in an
    /// admin Security Role so it can read feedback. Shown in the toolbar.
    @Published var userRecordName: String?

    // Navigation

    /// Which of the selected project's three sections is on screen.
    @Published var projectSection: ProjectSection = .feedback
    /// What is pushed on top of the project list: a project's screen, and on
    /// iOS a single feedback's detail after that.
    @Published var path = NavigationPath()
    /// True on the layout where the project screen is *pushed* (iPhone) rather
    /// than shown beside the project list (Mac, iPad). Set by the root view;
    /// `open(project:section:)` needs it to know whether to push or to swap
    /// what the content column is scoped to.
    var usesStackNavigation = false

    /// Go to one project's screen — the single way every cross-screen link
    /// moves, so pushing (iPhone) and re-scoping the column (Mac/iPad) don't
    /// have to be spelled out at each call site.
    func open(project: String?, section: ProjectSection? = nil) {
        selectedProject = project
        if let section { projectSection = section }
        if usesStackNavigation {
            path.append(ProjectRoute(project: project, section: section))
        }
    }

    // Filters / sorting
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
        // Both sides are @MainActor, so a page landing publishes straight to
        // the status line — no hop, no throttling needed at one call per page.
        service.onProgress = { [weak self] recordType, count in
            guard let self, self.isRefreshing else { return }
            var progress = Self.progressStep(for: recordType)
            progress.records = count
            self.refreshProgress = progress
        }
        readIDs = Set(defaults.stringArray(forKey: Self.readIDsKey) ?? [])
        handledIDs = Set(defaults.stringArray(forKey: Self.handledIDsKey) ?? [])
        showHandled = defaults.bool(forKey: Self.showHandledKey)
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

    /// How much of the hub a refresh reads.
    enum RefreshMode {
        /// Read everything and replace what is held. What the refresh button
        /// does, and what the first launch of the day does — an incremental
        /// read never notices records that were *deleted* in the console.
        case full
        /// Read only what changed since the last successful read of each record
        /// type and merge it in. What a launch on top of a warm cache does.
        case incremental
    }

    /// How far along a refresh is.
    ///
    /// There is no percentage to show: CloudKit answers a query by handing back
    /// one page and a cursor, never a total, so the denominator a percentage
    /// needs does not exist until the read is already over. What *is* known is
    /// that a refresh walks four record types in a fixed order, and how many
    /// records of the current one it has read — so the status line says
    /// "이벤트 확인 중… 1,240건 (2/4)" instead of inventing a number.
    struct RefreshProgress: Equatable {
        /// 1...`stepCount`, in the order `load(mode:)` reads the types.
        var step: Int
        /// The record type in human terms: 사용 현황 · 이벤트 · 진단 · 피드백.
        var label: String
        /// Records walked in this step so far. Resets when the step does.
        var records: Int = 0

        static let stepCount = 4

        /// For a determinate `ProgressView`. Steps, not records — the records
        /// have no total to divide by.
        var fraction: Double { Double(step) / Double(Self.stepCount) }

        /// "이벤트 확인 중… 1,240건 (2/4)"
        var text: String {
            let counted = records > 0 ? " \(AppFormat.count(records))건" : ""
            return "\(label) 확인 중…\(counted) (\(step)/\(Self.stepCount))"
        }

        /// The same thing where there is only room for a few characters.
        var shortText: String {
            records > 0 ? "\(label) \(AppFormat.count(records))건" : "\(label) 확인 중…"
        }
    }

    /// Which step of a refresh a record type belongs to. Feedback's real type
    /// name is discovered at runtime and several candidates may be probed, so
    /// anything unrecognised is the feedback step.
    private static func progressStep(for recordType: String) -> RefreshProgress {
        switch recordType {
        case CloudKitService.snapshotRecordType: return RefreshProgress(step: 1, label: "사용 현황")
        case CloudKitService.eventRecordType:    return RefreshProgress(step: 2, label: "이벤트")
        case CloudKitService.crashRecordType:    return RefreshProgress(step: 3, label: "진단")
        default:                                 return RefreshProgress(step: 4, label: "피드백")
        }
    }

    /// Record type key for the feedback watermark. Feedback's real type name is
    /// discovered at runtime, so the watermark is filed under a fixed key.
    private static let feedbackSyncKey = "feedback"
    /// Clocks on this device and in CloudKit are not exactly in step, so an
    /// incremental read looks slightly further back than the last one ran.
    /// Re-reading a handful of records is free — they merge by record name.
    private static let syncOverlap: TimeInterval = 5 * 60

    /// How much of the raw event stream is kept as individual records. Older
    /// events are not lost: they were folded into `rollups` the moment they
    /// arrived, and every number on screen comes from there. This window is
    /// only what the 사용 내역 list needs to show events one by one.
    static let rawEventRetentionDays = 90
    /// Backstop on the retained window, for an app that reports thousands of
    /// events a day. The rollups are unaffected either way.
    ///
    /// A retention cap, never a read cap. The two used to share a number and
    /// the number leaked into `CloudKitService.fetchUsage`, which stopped the
    /// event read at 5,000 records and then recorded the type as read to the
    /// end — so an unordered read handed back an arbitrary slice of the stream
    /// and the rest was never asked for again. Reads are uncapped now; what is
    /// bounded is what this device *keeps*.
    private static let eventLimit = 5000
    /// Diagnostics are read whole and are small; this is the only cap they get
    /// — again on what is kept, applied after the merge.
    private static let crashLimit = 1000

    /// When each record type was last read successfully. Persisted with the
    /// cache; drives the incremental queries.
    private var watermarks: [String: Date] = [:]
    private var startupTask: Task<Void, Never>?
    /// Just the cache read, kept separately from the refresh behind it — see
    /// `awaitRestore()`.
    private var restoreTask: Task<Bool, Never>?

    /// Called once when the app's window appears. Paints the cache first, then
    /// checks CloudKit for what changed — on its own task, so the check outlives
    /// the view that kicked it off and never holds up the first frame.
    func start() {
        guard startupTask == nil else { return }
        let restore = Task { [weak self] in
            await self?.restoreFromCache() ?? false
        }
        restoreTask = restore
        startupTask = Task { [weak self] in
            guard let self else { return }
            let restored = await restore.value
            await self.load(mode: restored ? .incremental : .full)
        }
    }

    /// Wait for the cache to be painted — and only that, not the network
    /// refresh behind it, which runs for minutes.
    ///
    /// For anything at launch that needs the project list before it can do its
    /// own work. `KeywordStore` is the case in point: a rank check started
    /// before this returns has no apps to look for, so it records competitors
    /// and not one rank.
    func awaitRestore() async {
        _ = await restoreTask?.value
    }

    /// Read everything again — the refresh button, ⌘R, and pull-to-refresh.
    func load() async {
        await load(mode: .full)
    }

    func load(mode: RefreshMode) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        // The first step is named before its first page comes back, so the
        // status line says something during the account-status round trip too.
        refreshProgress = Self.progressStep(for: CloudKitService.snapshotRecordType)
        defer {
            isRefreshing = false
            refreshProgress = nil
        }

        // An incremental read is only meaningful on top of data we already
        // have, and only until the cache is old enough that a deletion in the
        // console would have gone unnoticed for too long.
        let isIncremental = mode == .incremental && hasContent
            && (lastUpdated.map { Date().timeIntervalSince($0) < FeedbackCache.fullRefreshInterval } ?? false)
        if !isIncremental { service.forgetIncrementalFilterFields() }
        let since: (String) -> Date? = { [watermarks] key in
            guard isIncremental else { return nil }
            return watermarks[key]?.addingTimeInterval(-Self.syncOverlap)
        }

        noticeMessage = await service.accountStatusMessage()
        userRecordName = await service.currentUserRecordName()

        // Usage statistics live in their own record types with their own read
        // permission, so they are loaded separately and never fail the feedback
        // load — the dashboard shows whatever came back.
        var usageSince: [String: Date] = [:]
        for type in [CloudKitService.snapshotRecordType,
                     CloudKitService.eventRecordType,
                     CloudKitService.crashRecordType] {
            usageSince[type] = since(type)
        }
        // Events and diagnostics are only ever added to, so telling the service
        // what is already stored lets it stop reading as soon as it reaches it.
        // Snapshots are left out on purpose: each install rewrites its own
        // record, so a name we already have is exactly what we need to re-read.
        //
        // Events get their boundary even on a *full* refresh, which the other
        // types don't. A full refresh exists to notice records deleted in the
        // console, and a deleted event cannot be un-counted from a day that was
        // already summed — so re-reading the whole stream would cost the most
        // and buy nothing. "캐시 비우고 전체 다시 불러오기" is the way to rebuild
        // the rollups from scratch.
        //
        // Either way the boundary is only sound once that type has been read to
        // the end at least once. A read that was interrupted left the newest
        // records on disk and nothing older, and a boundary would stop the next
        // read right there — leaving the gap behind it unread for good. Having
        // finished is exactly what a watermark records.
        var usageKnown: [String: Set<String>] = [:]
        if watermarks[CloudKitService.eventRecordType] != nil {
            usageKnown[CloudKitService.eventRecordType] = rollups.knownEventIDs()
        }
        if isIncremental, watermarks[CloudKitService.crashRecordType] != nil {
            usageKnown[CloudKitService.crashRecordType] = Set(fetchedCrashes.map(\.id))
        }
        let usage = await service.fetchUsage(modifiedSince: usageSince, known: usageKnown) { [weak self] partial in
            // What has arrived so far, while the read is still running. Merged
            // and written out as it comes: a first launch reads thousands of
            // records over a minute or more, and quitting the app — or, on a
            // phone, just switching away from it — used to throw every one of
            // them away because the file was written only at the very end.
            //
            // Always merged, never replacing: a partial is the newest slice of
            // one record type, so `incremental` is true here regardless of what
            // the refresh as a whole is doing.
            guard let self else { return }
            let completedType = !partial.syncedTypes.isEmpty
            if self.apply(partial, incremental: true) {
                self.checkpoint(force: completedType)
            }
        }
        var changed = apply(usage, incremental: isIncremental)
        usageNotice = usage.notice

        refreshProgress = Self.progressStep(for: Self.feedbackSyncKey)

        do {
            let startedAt = Date()
            let outcome = try await service.fetchFeedback(modifiedSince: since(Self.feedbackSyncKey),
                                                          knownRecordType: resolvedRecordType,
                                                          known: isIncremental && watermarks[Self.feedbackSyncKey] != nil
                                                              ? Set(fetchedFeedback.map(\.id)) : nil)
            fetchedFeedback = isIncremental
                ? Self.merged(outcome.feedback, into: fetchedFeedback, newestFirst: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) })
                : outcome.feedback
            resolvedRecordType = outcome.resolvedRecordType
            watermarks[Self.feedbackSyncKey] = startedAt
            changed = changed || !isIncremental || !outcome.feedback.isEmpty
            learnAppNames(from: fetchedFeedback)
            lastUpdated = Date()
            if fetchedFeedback.isEmpty && errorMessage == nil {
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
        // An incremental check that found nothing has nothing to write, and the
        // auto-refresh runs every minute — no point rewriting megabytes of JSON
        // to say the same thing. `hasUnsavedChanges` covers the other end: the
        // partials above may have brought something in that the throttle has
        // not written yet.
        if changed {
            checkpoint(force: true)
        } else if hasUnsavedChanges {
            persistCache()
        }
    }

    /// Fold a usage read into what is held. A record type the read could not
    /// touch (`nil`) keeps whatever the cache had — a permission blip must not
    /// blank out yesterday's numbers.
    /// Returns whether anything actually moved, so an empty check can skip the
    /// disk write that would otherwise follow it.
    @discardableResult
    private func apply(_ usage: CloudKitService.UsageOutcome, incremental: Bool) -> Bool {
        var changed = !incremental
        var rollupsChanged = false
        if let snapshots = usage.snapshots {
            // Snapshots are the one type read in full every time, so "came
            // back non-empty" says nothing. Compare contents instead, or the
            // cache would be re-encoded once a minute for no reason.
            let next = incremental
                ? Self.merged(snapshots, into: fetchedSnapshots,
                              newestFirst: { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) })
                : snapshots
            // Compared *before* assigning, not after: the assignment itself is
            // what drops the derived cache, so an unchanged read has to stop
            // short of it or the refresh loop re-aggregates for nothing.
            if Self.fingerprint(next) != Self.fingerprint(fetchedSnapshots) {
                fetchedSnapshots = next
                changed = true
            }
        }
        if let events = usage.events {
            // Summed first, kept second. Folding is what makes the number on
            // screen permanent; the raw records below are only the recent
            // window the 사용 내역 list reads, and are merged (never replaced)
            // because a read that stopped early returns only the new tail.
            let folded = rollups.fold(events)
            if folded > 0 {
                rollups.pruneIdentifiers()
                // Only the weeks, months and years the fold above actually
                // touched — usually today's three — are added up again.
                rollups.rebuildDirtyPeriods()
                rollupsChanged = true
                changed = true
            }
            let all = Self.merged(events, into: fetchedEvents, newestFirst: { $0.occurredAt > $1.occurredAt })
            let window = Self.withinRetention(all)
            // Assigning an identical array would still fire `didSet` and throw
            // away every rollup — the once-a-minute refresh that found nothing
            // must not cost a full re-aggregation.
            if folded > 0 || window.count != fetchedEvents.count {
                fetchedEvents = window
            }
        }
        if let crashes = usage.crashes {
            let all = incremental
                ? Self.merged(crashes, into: fetchedCrashes,
                              newestFirst: { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) })
                : crashes
            // Diagnostics stop reading at what this device already has, so a
            // non-empty incremental result is genuinely new. Comparing counts
            // would miss one once the cap is reached and the count stops moving.
            if !crashes.isEmpty || !incremental {
                fetchedCrashes = Array(all.prefix(Self.crashLimit))
            }
        }
        watermarks.merge(usage.syncedTypes) { _, new in new }
        // Diagnostics stop reading at what this device already has, so anything
        // that came back is genuinely new. Events answer for themselves: only a
        // fold that counted something is news.
        changed = changed || !(usage.crashes?.isEmpty ?? true)
        if rollupsChanged { persistRollups() }
        return changed
    }

    /// The slice of the event stream kept as individual records, newest first.
    private static func withinRetention(_ events: [UsageEvent],
                                        calendar: Calendar = .current,
                                        now: Date = Date()) -> [UsageEvent] {
        guard let cutoff = calendar.date(byAdding: .day, value: -rawEventRetentionDays,
                                         to: calendar.startOfDay(for: now)) else {
            return Array(events.prefix(eventLimit))
        }
        return Array(events.filter { $0.occurredAt >= cutoff }.prefix(eventLimit))
    }

    /// A cheap stand-in for "did any install's numbers move". Coarse on
    /// purpose: a miss only means the cache file is a beat behind, and the next
    /// launch re-reads every snapshot anyway.
    private static func fingerprint(_ snapshots: [UsageSnapshot]) -> Int {
        var hasher = Hasher()
        for snapshot in snapshots.sorted(by: { $0.id < $1.id }) {
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.launchCount)
            hasher.combine(snapshot.eventCount)
            hasher.combine(snapshot.daysSinceInstall)
            hasher.combine(snapshot.lastActiveAt)
            hasher.combine(snapshot.appVersion)
            hasher.combine(snapshot.metrics.count)
        }
        return hasher.finalize()
    }

    /// Merge freshly-read records into the ones already held, newest first. A
    /// record that came back again replaces the copy we had (usage snapshots
    /// are upserted in place), and everything else is kept.
    private static func merged<T: Identifiable>(_ incoming: [T],
                                                into existing: [T],
                                                newestFirst: (T, T) -> Bool) -> [T] where T.ID == String {
        guard !incoming.isEmpty else { return existing }
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for item in incoming { byID[item.id] = item }
        return byID.values.sorted(by: newestFirst)
    }

    // MARK: - Disk cache

    /// Paint what the last session saw. Returns whether anything was restored,
    /// which decides if the refresh that follows can be incremental.
    @discardableResult
    private func restoreFromCache() async -> Bool {
        let cached = await FeedbackCache.shared.load()

        // The day buckets live in their own file and are restored on their own:
        // they are what every usage number reads, and they reach back much
        // further than the records below. Skipped if a refresh has already
        // folded its own — that read is the newer of the two.
        if rollups.isEmpty {
            var restored = await RollupCache.shared.load() ?? UsageRollups()
            // Idempotent, so this only does work on the first launch after a
            // device upgrades into rollups and has to seed them from the
            // records it already had on disk.
            if restored.fold(cached?.events ?? []) > 0 {
                restored.pruneIdentifiers()
                restored.rebuildDirtyPeriods()
                persistRollups(restored)
            }
            if !restored.isEmpty { rollups = restored }
        }

        guard let cached, !cached.isEmpty else { return false }
        // A refresh that already finished is newer than the file by definition.
        guard !hasFetchedRecords else { return false }

        fetchedFeedback = cached.feedback
        fetchedSnapshots = cached.snapshots
        fetchedEvents = Self.withinRetention(cached.events)
        fetchedCrashes = cached.crashes
        resolvedRecordType = cached.resolvedRecordType
        watermarks = cached.watermarks
        service.restoreIncrementalFilterFields(cached.filterFields)
        lastUpdated = cached.savedAt
        learnAppNames(from: cached.feedback)
        refreshBadge()
        return true
    }

    /// How often a refresh that is still running writes what it has. Encoding
    /// the whole hub is not free, and a long read hands over a batch every few
    /// seconds; this bounds the cost while keeping what can be lost to a few
    /// seconds of reading.
    private static let checkpointInterval: TimeInterval = 5
    private var lastPersist = Date.distantPast
    /// Whether anything held is newer than what is on disk. Drives both the
    /// throttle and the flush the app runs on its way out.
    private var hasUnsavedChanges = false

    /// Note that what is held has moved, and write it unless a write has just
    /// happened. `force` skips the throttle — what the end of a record type
    /// and the end of a refresh use.
    private func checkpoint(force: Bool = false) {
        hasUnsavedChanges = true
        guard force || Date().timeIntervalSince(lastPersist) >= Self.checkpointInterval else { return }
        persistCache()
    }

    /// The snapshot to write, as of right now.
    private var currentHub: CachedHub {
        CachedHub(savedAt: lastUpdated ?? Date(),
                  watermarks: watermarks,
                  resolvedRecordType: resolvedRecordType,
                  filterFields: service.incrementalFilterFields,
                  unsortableTypes: service.unsortableRecordTypes.sorted(),
                  feedback: fetchedFeedback,
                  snapshots: fetchedSnapshots,
                  events: fetchedEvents,
                  crashes: fetchedCrashes)
    }

    /// Write what is held back to disk. Fire-and-forget: the encode happens on
    /// the cache actor, off the main thread.
    private func persistCache() {
        let hub = currentHub
        lastPersist = Date()
        hasUnsavedChanges = false
        Task { await FeedbackCache.shared.save(hub) }
    }

    /// Write anything not yet saved, right here, before returning.
    ///
    /// Called when the app is about to stop being frontmost. `persistCache()`
    /// won't do: it hands the work to an actor, and a hop scheduled as the
    /// process is suspended (iOS) or torn down (⌘Q) may simply never run. This
    /// pays for the encode on the spot instead — a few hundred milliseconds at
    /// a moment where the system allows them.
    func flushCache() {
        guard hasUnsavedChanges else { return }
        FeedbackCache.saveNow(currentHub)
        RollupCache.saveNow(rollups)
        lastPersist = Date()
        hasUnsavedChanges = false
    }

    /// Write the day buckets back, in their own file. Kept apart from
    /// `persistCache()` so a refresh that only added a handful of events
    /// rewrites a few kilobytes of sums instead of every record the hub holds.
    private func persistRollups(_ value: UsageRollups? = nil) {
        let rollups = value ?? self.rollups
        Task { await RollupCache.shared.save(rollups) }
    }

    /// Throw the cache away and read everything again from CloudKit.
    func resetCacheAndReload() async {
        await FeedbackCache.shared.clear()
        await RollupCache.shared.clear()
        // The one path that rebuilds the sums from scratch: without this the
        // day buckets would survive the reset and keep counting events the
        // fresh read is about to hand back.
        rollups = UsageRollups()
        watermarks = [:]
        await load(mode: .full)
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

        // Written back only when they actually moved. This runs after every
        // refresh — once a minute with auto-refresh on — and with a few
        // thousand records these are two sizeable arrays to re-encode into
        // user defaults for nothing.
        if seenFeedbackIDs != feedbackIDs {
            seenFeedbackIDs = feedbackIDs
            defaults.set(Array(feedbackIDs), forKey: Self.seenFeedbackIDsKey)
        }
        if seenCrashIDs != crashIDs {
            seenCrashIDs = crashIDs
            defaults.set(Array(crashIDs), forKey: Self.seenCrashIDsKey)
        }
    }

    /// The app icon badge follows the unread feedback count.
    func refreshBadge() {
        NotificationService.setBadge(notificationsEnabled ? unreadCount : 0)
    }

    // MARK: - Read / unread

    /// Record names the user has already opened. Persisted, so a relaunch
    /// doesn't resurface feedback that was already dealt with.
    @Published private(set) var readIDs: Set<String> = [] { didSet { invalidateReadState() } }
    private static let readIDsKey = "readFeedbackIDs"

    func isUnread(_ feedback: Feedback) -> Bool { !readIDs.contains(feedback.id) }

    /// Unread across every project — the number the tab badge shows.
    var unreadCount: Int { countUnread(in: allFeedback) }

    /// Unread inside the current project scope.
    var scopedUnreadCount: Int { countUnread(in: scopedFeedback) }

    /// Unread inside one project (nil == 전체) — what the project rows show.
    func unreadCount(for project: String?) -> Int {
        countUnread(in: feedback(for: project))
    }

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
        let targets = feedback(for: project)
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

    // MARK: - 확인함

    /// Record names the user explicitly marked as dealt with. Deliberately not
    /// the same set as `readIDs`: reading is something the detail view does on
    /// its own the moment a record is opened, so hiding by it would make rows
    /// vanish just for being looked at. This one only ever moves when the user
    /// says so, which is what makes it safe to hide by. Persisted per device;
    /// nothing is written back to CloudKit.
    @Published private(set) var handledIDs: Set<String> = [] { didSet { invalidateReadState() } }
    private static let handledIDsKey = "handledFeedbackIDs"

    /// Show the 확인한 rows in the list anyway. Off by default — the point of
    /// marking is to get them out of the way. Persisted per device.
    @Published var showHandled = false {
        didSet {
            guard showHandled != oldValue else { return }
            defaults.set(showHandled, forKey: Self.showHandledKey)
        }
    }
    private static let showHandledKey = "showHandledFeedback"

    func isHandled(_ feedback: Feedback) -> Bool { handledIDs.contains(feedback.id) }

    /// 확인한 건수 — 전체, 그리고 현재 프로젝트 범위.
    var handledCount: Int { countHandled(in: allFeedback) }
    var scopedHandledCount: Int { countHandled(in: scopedFeedback) }

    /// 확인한 건수, 프로젝트 단위 (nil == 전체).
    func handledCount(for project: String?) -> Int {
        countHandled(in: feedback(for: project))
    }

    private func countHandled(in items: [Feedback]) -> Int {
        items.reduce(0) { $0 + (handledIDs.contains($1.id) ? 1 : 0) }
    }

    func toggleHandled(_ feedback: Feedback) {
        setHandled(feedback, !handledIDs.contains(feedback.id))
    }

    func setHandled(_ feedback: Feedback, _ handled: Bool) {
        if handled {
            guard handledIDs.insert(feedback.id).inserted else { return }
            // 확인한 것은 당연히 읽은 것이기도 하다: 안 읽음 배지와 아이콘 배지가
            // 확인 표시만으로 정리되도록 함께 넘긴다.
            readIDs.insert(feedback.id)
            persistReadIDs()
        } else {
            guard handledIDs.remove(feedback.id) != nil else { return }
        }
        persistHandledIDs()
        refreshBadge()
    }

    /// Mark every feedback in one project — or everything when `project` is nil
    /// — as 확인함.
    func markAllHandled(project: String? = nil) {
        let targets = feedback(for: project)
        let ids = Set(targets.map(\.id))
        guard !ids.isSubset(of: handledIDs) else { return }
        handledIDs.formUnion(ids)
        readIDs.formUnion(ids)
        persistReadIDs()
        persistHandledIDs()
        refreshBadge()
    }

    /// Undo the marking for one project's currently loaded feedback, or for all
    /// of it. Older entries for records no longer held are left alone.
    func clearHandled(project: String? = nil) {
        let targets = feedback(for: project)
        let ids = Set(targets.map(\.id))
        guard !handledIDs.isDisjoint(with: ids) else { return }
        handledIDs.subtract(ids)
        persistHandledIDs()
    }

    private func persistHandledIDs() {
        defaults.set(Array(handledIDs), forKey: Self.handledIDsKey)
    }

    // MARK: - Hidden projects

    /// Projects taken out of this viewer. Nothing is deleted from CloudKit —
    /// the records stay in the hub and come back the moment the project is
    /// shown again. Persisted per device.
    @Published private(set) var hiddenProjects: Set<String> = [] { didSet { invalidateDerived() } }
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
            path = NavigationPath()
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
        if let cached = derived.hiddenProjectEntries { return cached }
        guard !hiddenProjects.isEmpty else {
            derived.hiddenProjectEntries = []
            return []
        }
        // One pass over the raw records rather than four filters per hidden
        // project: this is read three times while the section draws.
        var records: [String: Int] = [:]
        for key in fetchedFeedback.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
        for key in fetchedSnapshots.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
        for key in fetchedEvents.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
        for key in fetchedCrashes.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }

        let value: [(key: String, displayName: String, records: Int)] = hiddenProjects
            .map { (key: $0, displayName: displayName(for: $0), records: records[$0] ?? 0) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        derived.hiddenProjectEntries = value
        return value
    }

    private func persistHiddenProjects() {
        defaults.set(Array(hiddenProjects), forKey: Self.hiddenProjectsKey)
    }

    // MARK: - Project name resolution

    /// Learned `appId → appName` from records that carry both. Lets records
    /// that only have an `appId` (older LeeoKit submissions) still show a
    /// human-readable name.
    @Published private(set) var learnedAppNames: [String: String] = [:] { didSet { invalidateLabels() } }

    /// Manual `appId → 앱 이름` overrides for apps whose records never include an
    /// `appName` at all. Edit this to name legacy-only projects.
    /// 예: ["com.Ysoup.OldApp": "옛날앱"]
    var appNameOverrides: [String: String] = [:] { didSet { invalidateLabels() } }

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
        if let cached = derived.projectCounts { return cached }
        var buckets: [String: Int] = [:]
        // Every project the hub knows about, not just the ones that have sent
        // feedback: an app that only reports usage or only crashed is still an
        // app of yours, and leaving it out of the list makes its data
        // unreachable. Those come in with a feedback count of zero.
        for key in allProjectKeys { buckets[key] = 0 }
        for fb in allFeedback { buckets[fb.projectKey, default: 0] += 1 }
        let traffic = trafficByProject
        let value: [(key: String, count: Int)] = buckets
            .map { (key: $0.key, count: $0.value) }
            .sorted { lhs, rhs in ordered(lhs.key, lhs.count, rhs.key, rhs.count, traffic: traffic) }
        derived.projectCounts = value
        return value
    }

    /// Per-project rolled-up numbers for the overview grid, ordered the same
    /// way as `projectCounts` (most feedback first, "미분류" last).
    var projectSummaries: [ProjectSummary] {
        if let cached = derived.projectSummaries { return cached }
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        // Seeded with every known project (see `projectCounts`) so an app that
        // has usage or diagnostics but no feedback yet still gets a card.
        var grouped: [String: [Feedback]] = [:]
        for key in allProjectKeys { grouped[key] = [] }
        for fb in allFeedback { grouped[fb.projectKey, default: []].append(fb) }
        let traffic = trafficByProject

        let value: [ProjectSummary] = grouped.map { key, items in
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
        derived.projectSummaries = value
        return value
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
        if let cached = derived.trafficByProject { return cached }
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
        derived.trafficByProject = result
        return result
    }

    func traffic(for project: String) -> Traffic {
        trafficByProject[project] ?? .none
    }

    /// Every project's traffic added together — the 전체 프로젝트 row's shape.
    var overallTraffic: Traffic {
        if let cached = derived.overallTraffic { return cached }
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
        derived.overallTraffic = value
        return value
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
        if let cached = derived.availableVersions { return cached }
        let versions = Set(allFeedback.compactMap { $0.appVersion?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let value: [String] = versions.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        derived.availableVersions = value
        return value
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

    // MARK: - Statistics

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
        if let cached = derived.stats[project] { return cached }
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
        derived.stats[project] = value
        return value
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

    // MARK: - Auto refresh

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.autoRefreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.load(mode: .incremental)
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

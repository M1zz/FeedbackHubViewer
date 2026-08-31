//
//  FeedbackStore.swift
//  FeedbackHubViewer
//
//  Observable state for the app: what has been fetched, what the user has done
//  with it, and the refresh that keeps both current.
//
//  This file holds the state itself and everything that *moves* it — loading,
//  the disk cache, notifications, read/확인함/숨김, auto-refresh. Everything
//  derived *from* it lives in an extension, because none of it needs to write:
//
//    FeedbackStore+Derived.swift   the rollup cache and the per-project scoping
//    FeedbackStore+Projects.swift  the project list's numbers and feedback stats
//    FeedbackStore+Usage.swift     usage, diagnostics, trends, carrying capacity
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
        /// Feedback in this project still waiting on a 반영/반영 안 함 decision.
        let pendingCount: Int
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

    /// The rollup cache. Not `private` only because the aggregation that fills
    /// it lives in `FeedbackStore+Derived.swift` and `+Usage.swift`.
    var derived = Derived()

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
    /// When CloudKit was last checked — which is not the same as when the data
    /// last changed, and the two coming apart is what made every launch re-read
    /// the whole hub.
    ///
    /// `CachedHub.savedAt` is written with the records, and the records are
    /// only written when something in them moved. So a refresh that correctly
    /// found nothing new left the timestamp where it was; the next launch saw a
    /// cache that looked hours old, checked again, found nothing again, and
    /// left it again — forever, once per launch, with `UsageSnapshot` read
    /// whole every time. Rewriting eight megabytes of records to say "we
    /// looked" is no answer either. The answer is that "we looked" was never
    /// part of the records: it is one date, and it lives on its own.
    @Published var lastUpdated: Date? {
        didSet {
            guard let lastUpdated else { return }
            UserDefaults.standard.set(lastUpdated, forKey: Self.lastCheckedKey)
        }
    }

    /// Per bundle id, so a Development build's clock never speaks for a
    /// Production one — the same split the cache files make.
    private static let lastCheckedKey = "lastCheckedAt"
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
    /// Which triage decisions the list shows (see `FeedbackTriage.swift`).
    /// Defaults to 확인 필요: deciding a feedback takes it out of the list, and
    /// the "처리한 피드백 보기" switch at the bottom of the list brings it back.
    @Published var statusFilter: FeedbackStatusFilter = .pending {
        didSet {
            guard statusFilter != oldValue else { return }
            defaults.set(statusFilter.rawValue, forKey: Self.statusFilterKey)
        }
    }

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
        triage = Self.decodeTriage(defaults.data(forKey: Self.triageKey))
        statusFilter = defaults.string(forKey: Self.statusFilterKey)
            .flatMap(FeedbackStatusFilter.init(rawValue:)) ?? .pending
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
    ///
    /// Feedback is read first and 사용 현황 last, which is the reverse of the
    /// order they were written in. Feedback is why anyone opens this app, and
    /// it is also the cheapest read — a handful of records that stops at the
    /// first one this device already holds. 사용 현황 is the opposite on both
    /// counts: it is the slowest read in the app and its numbers move by the
    /// day. Reading it first meant a new piece of feedback waited behind a
    /// full scan of every install record before it could appear.
    private static func progressStep(for recordType: String) -> RefreshProgress {
        switch recordType {
        case CloudKitService.snapshotRecordType: return RefreshProgress(step: 4, label: "사용 현황")
        case CloudKitService.eventRecordType:    return RefreshProgress(step: 2, label: "이벤트")
        case CloudKitService.crashRecordType:    return RefreshProgress(step: 3, label: "진단")
        default:                                 return RefreshProgress(step: 1, label: "피드백")
        }
    }

    /// Record type key for the feedback watermark. Feedback's real type name is
    /// discovered at runtime, so the watermark is filed under a fixed key.
    private static let feedbackSyncKey = "feedback"
    /// How fresh the cache has to be for a launch to leave CloudKit alone.
    ///
    /// Every number this app shows is day-grained or nearly so — 최근 7일,
    /// 일별 추이, 설치 수 — so a cache a few minutes old differs from a fresh
    /// read in nothing anyone can see. Meanwhile a launch refresh is the most
    /// expensive thing the app does: `UsageSnapshot` can be neither filtered
    /// nor sorted in this container, so it is read whole, every time, and the
    /// status line sits on "사용 현황 확인 중" while it happens. Doing that
    /// again because a window was closed and reopened is pure waste.
    ///
    /// Five minutes, not longer: this hub is often open next to the app whose
    /// feedback it shows, and a test message sent a moment ago should not have
    /// to wait. Anything more urgent than that is what ⌘R is for, and the
    /// toolbar always says when the data is from.
    static let launchRefreshInterval: TimeInterval = 5 * 60

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
            // A cache written minutes ago has nothing to add. See
            // `launchRefreshInterval` — this is the difference between opening
            // the hub and waiting for it.
            if restored, let updated = self.lastUpdated,
               Date().timeIntervalSince(updated) < Self.launchRefreshInterval {
                return
            }
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
        refreshProgress = Self.progressStep(for: Self.feedbackSyncKey)
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

        // Whether this refresh moved anything, so an empty check can skip the
        // disk write that would otherwise follow it.
        var changed = false

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
            changed = !isIncremental || !outcome.feedback.isEmpty
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


        refreshProgress = Self.progressStep(for: CloudKitService.eventRecordType)

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
        changed = apply(usage, incremental: isIncremental) || changed
        usageNotice = usage.notice

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
        // The recorded check time outranks the file's own, because it is
        // written whether or not the refresh had anything to save.
        let checked = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
        lastUpdated = max(cached.savedAt, checked ?? .distantPast)
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

    /// Not `private`: the project summaries in `FeedbackStore+Projects.swift`
    /// count unread per project as they build each card.
    func countUnread(in items: [Feedback]) -> Int {
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

    // MARK: - 처리 상태 (triage)

    /// Record name → what was decided about it. Persisted per device: the hub's
    /// records are read-only to this viewer, so the decision is ours to keep
    /// (see `FeedbackTriage.swift`).
    @Published private(set) var triage: [String: FeedbackTriageEntry] = [:] { didSet { invalidateReadState() } }
    private static let triageKey = "feedbackTriage"
    private static let statusFilterKey = "feedbackStatusFilter"

    func status(of feedback: Feedback) -> FeedbackStatus {
        triage[feedback.id]?.status ?? .pending
    }

    func note(for feedback: Feedback) -> String {
        triage[feedback.id]?.note ?? ""
    }

    func decidedAt(for feedback: Feedback) -> Date? {
        guard let entry = triage[feedback.id], entry.status.isHandled else { return nil }
        return entry.decidedAt
    }

    func isHandled(_ feedback: Feedback) -> Bool { status(of: feedback).isHandled }

    /// Record the decision. Deciding also counts as having read the feedback —
    /// leaving it bold in the list after acting on it would be nonsense.
    /// `note` nil keeps whatever memo is already stored.
    func setStatus(_ status: FeedbackStatus, note: String? = nil, for feedback: Feedback) {
        apply(status: status, note: note, to: feedback.id)
        persistTriage()
        markRead(feedback)
    }

    /// Change several records at once — the list's multi-selection actions.
    func setStatus(_ status: FeedbackStatus, forIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for id in ids { apply(status: status, note: nil, to: id) }
        persistTriage()
        let targets = allFeedback.filter { ids.contains($0.id) }
        readIDs.formUnion(targets.map(\.id))
        persistReadIDs()
        refreshBadge()
    }

    /// Store or update the memo without changing the decision.
    func setNote(_ note: String, for feedback: Feedback) {
        apply(status: status(of: feedback), note: note, to: feedback.id)
        persistTriage()
    }

    /// Decide every feedback currently listed — "표시된 항목 모두 처리".
    func setStatusForFiltered(_ status: FeedbackStatus) {
        setStatus(status, forIDs: Set(filteredFeedback.map(\.id)))
    }

    private func apply(status: FeedbackStatus, note: String?, to id: String) {
        let existing = triage[id]
        let entry = FeedbackTriageEntry(status: status,
                                        note: note ?? existing?.note ?? "",
                                        decidedAt: Date())
        // A record back at 확인 필요 with no memo left is simply not tracked, so
        // the stored set stays as small as the decisions actually made.
        triage[id] = entry.isEmpty ? nil : entry
    }

    /// Still waiting on a decision, across every project.
    var pendingCount: Int { countPending(in: allFeedback) }
    /// Still waiting on a decision inside the current project scope.
    var scopedPendingCount: Int { countPending(in: scopedFeedback) }
    /// Already decided inside the current project scope.
    var scopedHandledCount: Int { scopedFeedback.count - scopedPendingCount }

    func countPending(in items: [Feedback]) -> Int {
        items.reduce(0) { $0 + (triage[$1.id]?.status.isHandled == true ? 0 : 1) }
    }

    private func persistTriage() {
        guard let data = try? JSONEncoder().encode(triage) else { return }
        defaults.set(data, forKey: Self.triageKey)
    }

    private static func decodeTriage(_ data: Data?) -> [String: FeedbackTriageEntry] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: FeedbackTriageEntry].self, from: data)
        else { return [:] }
        return decoded
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
        memoized(\.hiddenProjectEntries) {
            guard !hiddenProjects.isEmpty else { return [] }
            // One pass over the raw records rather than four filters per hidden
            // project: this is read three times while the section draws.
            var records: [String: Int] = [:]
            for key in fetchedFeedback.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
            for key in fetchedSnapshots.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
            for key in fetchedEvents.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }
            for key in fetchedCrashes.map(\.projectKey) where hiddenProjects.contains(key) { records[key, default: 0] += 1 }

            return hiddenProjects
                .map { (key: $0, displayName: displayName(for: $0), records: records[$0] ?? 0) }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
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

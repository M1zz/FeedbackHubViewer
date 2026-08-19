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
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .feedback: return "text.bubble"
            case .stats: return "chart.bar"
            case .crashes: return "exclamationmark.triangle"
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

    /// A network refresh is in flight. The screen keeps showing whatever the
    /// cache painted while this is true — only the small toolbar indicator and
    /// the refresh button react to it.
    @Published private(set) var isRefreshing = false
    /// True only while a refresh is running with nothing to show yet: the
    /// condition the full-screen "불러오는 중…" spinners key off. With a cache on
    /// disk this is false from the first frame.
    var isLoading: Bool { isRefreshing && !hasContent }
    /// Whether there is anything on screen at all, from cache or from the
    /// network. Errors and empty states defer to it.
    var hasContent: Bool {
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

    /// Record type key for the feedback watermark. Feedback's real type name is
    /// discovered at runtime, so the watermark is filed under a fixed key.
    private static let feedbackSyncKey = "feedback"
    /// Clocks on this device and in CloudKit are not exactly in step, so an
    /// incremental read looks slightly further back than the last one ran.
    /// Re-reading a handful of records is free — they merge by record name.
    private static let syncOverlap: TimeInterval = 5 * 60

    /// Hard caps on the two record types that grow without bound. Applied after
    /// merging, so an incremental read can't grow the cache forever.
    private static let eventLimit = 5000
    private static let crashLimit = 1000

    /// When each record type was last read successfully. Persisted with the
    /// cache; drives the incremental queries.
    private var watermarks: [String: Date] = [:]
    private var startupTask: Task<Void, Never>?

    /// Called once when the app's window appears. Paints the cache first, then
    /// checks CloudKit for what changed — on its own task, so the check outlives
    /// the view that kicked it off and never holds up the first frame.
    func start() {
        guard startupTask == nil else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            let restored = await self.restoreFromCache()
            await self.load(mode: restored ? .incremental : .full)
        }
    }

    /// Read everything again — the refresh button, ⌘R, and pull-to-refresh.
    func load() async {
        await load(mode: .full)
    }

    func load(mode: RefreshMode) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

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
        var usageKnown: [String: Set<String>] = [:]
        if isIncremental {
            usageKnown[CloudKitService.eventRecordType] = Set(fetchedEvents.map(\.id))
            usageKnown[CloudKitService.crashRecordType] = Set(fetchedCrashes.map(\.id))
        }
        let usage = await service.fetchUsage(modifiedSince: usageSince, known: usageKnown)
        var changed = apply(usage, incremental: isIncremental)

        do {
            let startedAt = Date()
            let outcome = try await service.fetchFeedback(modifiedSince: since(Self.feedbackSyncKey),
                                                          knownRecordType: resolvedRecordType,
                                                          known: isIncremental ? Set(fetchedFeedback.map(\.id)) : nil)
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
        // to say the same thing.
        if changed { persistCache() }
    }

    /// Fold a usage read into what is held. A record type the read could not
    /// touch (`nil`) keeps whatever the cache had — a permission blip must not
    /// blank out yesterday's numbers.
    /// Returns whether anything actually moved, so an empty check can skip the
    /// disk write that would otherwise follow it.
    @discardableResult
    private func apply(_ usage: CloudKitService.UsageOutcome, incremental: Bool) -> Bool {
        var changed = !incremental
        if let snapshots = usage.snapshots {
            // Snapshots are the one type read in full every time, so "came
            // back non-empty" says nothing. Compare contents instead, or the
            // cache would be re-encoded once a minute for no reason.
            let before = Self.fingerprint(fetchedSnapshots)
            fetchedSnapshots = incremental
                ? Self.merged(snapshots, into: fetchedSnapshots,
                              newestFirst: { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) })
                : snapshots
            changed = changed || Self.fingerprint(fetchedSnapshots) != before
        }
        if let events = usage.events {
            let all = incremental
                ? Self.merged(events, into: fetchedEvents, newestFirst: { $0.occurredAt > $1.occurredAt })
                : events
            fetchedEvents = Array(all.prefix(Self.eventLimit))
        }
        if let crashes = usage.crashes {
            let all = incremental
                ? Self.merged(crashes, into: fetchedCrashes,
                              newestFirst: { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) })
                : crashes
            fetchedCrashes = Array(all.prefix(Self.crashLimit))
        }
        usageNotice = usage.notice
        watermarks.merge(usage.syncedTypes) { _, new in new }
        // Events and diagnostics stop reading at what this device already has,
        // so anything that came back is genuinely new.
        changed = changed
            || !(usage.events?.isEmpty ?? true)
            || !(usage.crashes?.isEmpty ?? true)
        return changed
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
        guard let cached = await FeedbackCache.shared.load(), !cached.isEmpty else { return false }
        // A refresh that already finished is newer than the file by definition.
        guard !hasContent else { return false }

        fetchedFeedback = cached.feedback
        fetchedSnapshots = cached.snapshots
        fetchedEvents = cached.events
        fetchedCrashes = cached.crashes
        resolvedRecordType = cached.resolvedRecordType
        watermarks = cached.watermarks
        service.restoreIncrementalFilterFields(cached.filterFields)
        lastUpdated = cached.savedAt
        learnAppNames(from: cached.feedback)
        refreshBadge()
        return true
    }

    /// Write what is held back to disk. Fire-and-forget: the encode happens on
    /// the cache actor, off the main thread.
    private func persistCache() {
        let hub = CachedHub(savedAt: lastUpdated ?? Date(),
                            watermarks: watermarks,
                            resolvedRecordType: resolvedRecordType,
                            filterFields: service.incrementalFilterFields,
                            feedback: fetchedFeedback,
                            snapshots: fetchedSnapshots,
                            events: fetchedEvents,
                            crashes: fetchedCrashes)
        Task { await FeedbackCache.shared.save(hub) }
    }

    /// Throw the cache away and read everything again from CloudKit.
    func resetCacheAndReload() async {
        await FeedbackCache.shared.clear()
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

    /// Unread inside one project (nil == 전체) — what the project rows show.
    func unreadCount(for project: String?) -> Int {
        guard let project else { return unreadCount }
        return countUnread(in: allFeedback.filter { $0.projectKey == project })
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

    // MARK: - 확인함

    /// Record names the user explicitly marked as dealt with. Deliberately not
    /// the same set as `readIDs`: reading is something the detail view does on
    /// its own the moment a record is opened, so hiding by it would make rows
    /// vanish just for being looked at. This one only ever moves when the user
    /// says so, which is what makes it safe to hide by. Persisted per device;
    /// nothing is written back to CloudKit.
    @Published private(set) var handledIDs: Set<String> = []
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
        guard let project else { return handledCount }
        return countHandled(in: allFeedback.filter { $0.projectKey == project })
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
        let targets = project.map { key in allFeedback.filter { $0.projectKey == key } } ?? allFeedback
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
        let targets = project.map { key in allFeedback.filter { $0.projectKey == key } } ?? allFeedback
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

    /// Per-project rolled-up numbers for the overview grid, ordered the same
    /// way as `projectCounts` (most feedback first, "미분류" last).
    var projectSummaries: [ProjectSummary] {
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = 14
        guard let sparklineStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [:] }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)

        var events7: [String: Int] = [:]
        var totals: [String: Int] = [:]
        var actives: [String: Set<String>] = [:]
        var installs: [String: Int] = [:]
        var daily: [String: [Date: Int]] = [:]

        for event in allEvents {
            let key = event.projectKey
            totals[key, default: 0] += 1
            if event.occurredAt >= weekAgo {
                events7[key, default: 0] += 1
                if let id = event.installID { actives[key, default: []].insert(id) }
            }
            if event.occurredAt >= sparklineStart {
                let day = calendar.startOfDay(for: event.occurredAt)
                daily[key, default: [:]][day, default: 0] += 1
            }
        }
        for snapshot in allSnapshots {
            installs[snapshot.projectKey, default: 0] += 1
        }

        let axis: [Date] = (0..<days).compactMap {
            calendar.date(byAdding: .day, value: $0 - (days - 1), to: today)
        }

        var result: [String: Traffic] = [:]
        for key in Set(totals.keys).union(installs.keys) {
            let buckets = daily[key] ?? [:]
            result[key] = Traffic(events7: events7[key] ?? 0,
                                  activeInstalls7: actives[key]?.count ?? 0,
                                  installs: installs[key] ?? 0,
                                  totalEvents: totals[key] ?? 0,
                                  sparkline: axis.map { DayCount(date: $0, count: buckets[$0] ?? 0) })
        }
        return result
    }

    func traffic(for project: String) -> Traffic {
        trafficByProject[project] ?? .none
    }

    /// Every project's traffic added together — the 전체 프로젝트 row's shape.
    var overallTraffic: Traffic {
        let all = Array(trafficByProject.values)
        guard let axis = all.first?.sparkline else { return .none }
        var summed = axis.map { DayCount(date: $0.date, count: 0) }
        for traffic in all {
            for (index, point) in traffic.sparkline.enumerated() where index < summed.count {
                summed[index] = DayCount(date: summed[index].date,
                                         count: summed[index].count + point.count)
            }
        }
        return Traffic(events7: all.reduce(0) { $0 + $1.events7 },
                       // Installs are anonymous per app, so "활동 사용자" only
                       // adds up as a sum of each app's own count.
                       activeInstalls7: all.reduce(0) { $0 + $1.activeInstalls7 },
                       installs: all.reduce(0) { $0 + $1.installs },
                       totalEvents: all.reduce(0) { $0 + $1.totalEvents },
                       sparkline: summed)
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
        let source = project.map { key in allFeedback.filter { $0.projectKey == key } } ?? allFeedback
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

//
//  NewsStore.swift
//  FeedbackHubViewer
//
//  "소식" 칸의 가게 — 다른 가게들이 이미 받아 둔 것에서 소식을 찾고(`NewsDetector`),
//  한 번 본 것을 기억하고, 알린다. 바깥 뉴스(`WebMentions`)만은 여기서 직접 받는다.
//
//  ── 언제 찾나 ──
//
//  찾는 일은 받아 둔 것을 훑기만 해서 가볍다. 그래서 따로 신호를 기다리지 않고 10분마다
//  (`collectInterval`) 그리고 앱이 앞으로 올 때 훑는다. 리뷰 · 차트 · 분석이 새로 들어오면
//  다음 훑기에 잡힌다. 바깥 뉴스는 남의 서버라 앱마다 6시간에 한 번(`webInterval`).
//
//  ── 언제 알리나 ──
//
//  하루 한 번, 아침 9시 브리핑(`Briefing`). 일어난 일을 다 알리지 않고 볼 만한 것만 골라
//  최대 다섯 줄로. 볼 만한 게 없는 날은 울리지 않는다. 그 알림은 미리 예약해 두므로
//  (`scheduleBriefing`) 앱이 꺼져 있어도 울린다. 알림은 설정의 "알림" 이 켜져 있고
//  "내 앱 소식" 이 켜져 있을 때만.
//

import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class NewsStore: ObservableObject {

    /// 새것부터.
    @Published private(set) var items: [NewsItem] = []
    /// 이 시각 뒤에 찾은 소식이 "새 소식" 이다. 소식 칸을 열면 옮긴다.
    @Published private(set) var lastReadAt: Date = .distantPast
    @Published private(set) var isSearchingWeb = false
    /// 앱 → 바깥 뉴스 검색어. 없으면 앱 이름.
    @Published private(set) var searchTerms: [String: [String]] = [:]
    /// 소식 알림을 보낼지. 설정의 알림 스위치 아래에 따로 있다.
    @Published var alertsEnabled = true {
        didSet {
            UserDefaults.standard.set(alertsEnabled, forKey: Self.alertsKey)
            scheduleBriefing()
        }
    }

    static let collectInterval: TimeInterval = 10 * 60
    static let webInterval: TimeInterval = 6 * 3600
    /// 남겨 둘 소식.
    static let keepDays = 120
    static let keepCount = 600
    /// 아침 묶음 알림 시각.
    static let digestHour = 9

    private static let alertsKey = "news-alerts-enabled"
    private static let termsKey = "news-search-terms"
    private static let digestID = "news-digest"

    /// 디스크에 두는 것 전부.
    private struct Memory: Codable {
        var items: [NewsItem] = []
        /// 한 번이라도 낸 소식 id — 지운 소식도 다시 알리지 않으려고 따로 둔다.
        var seen: Set<String> = []
        /// 기준선을 잡은 묶음(`NewsBatch.group`).
        var baselined: Set<String> = []
        /// 앱 → 지금까지 가장 많던 하루 사용자 수.
        var bestDAU: [String: Int] = [:]
        var lastReadAt: Date = .distantPast
        var web: [String: [WebMention]] = [:]
        var webFetchedAt: [String: Date] = [:]
    }

    private var memory = Memory()
    private var loop: Task<Void, Never>?

    private weak var store: FeedbackStore?
    private weak var keywords: KeywordStore?
    private weak var charts: ChartStore?
    private weak var purchases: AppStoreConnectStore?

    private static var file: URL? { CacheFile.url("app-news", CloudKitEnvironment.current) }

    init() {
        let defaults = UserDefaults.standard
        alertsEnabled = defaults.object(forKey: Self.alertsKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.termsKey),
           let terms = try? JSONDecoder().decode([String: [String]].self, from: data) {
            searchTerms = terms
        }
    }

    // MARK: - 시작

    /// 가게들을 잇고, 기억을 읽고, 주기적으로 훑기 시작한다. 여러 번 불러도 한 번만 건다.
    func start(store: FeedbackStore, keywords: KeywordStore, charts: ChartStore, purchases: AppStoreConnectStore) {
        self.store = store
        self.keywords = keywords
        self.charts = charts
        self.purchases = purchases
        guard loop == nil else { return }
        if let saved = CacheFile.read(Memory.self, at: Self.file) {
            memory = saved
            items = saved.items
            lastReadAt = saved.lastReadAt
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshWebIfDue()
                self?.collect()
                try? await Task.sleep(for: .seconds(Self.collectInterval))
            }
        }
    }

    // MARK: - 찾기

    /// 받아 둔 것을 한 번 훑는다.
    func collect(now: Date = Date()) {
        guard let store, let keywords, let charts, let purchases else { return }
        var batches: [NewsBatch] = []
        var extra: [NewsItem] = []

        for project in projects(store) {
            let name = store.displayName(for: project)
            let trackId = keywords.trackId(for: project)
            batches.append(NewsDetector.charts(project: project, name: name, trackId: trackId,
                                               history: charts.history, now: now))
            batches.append(NewsDetector.keywords(project: project, name: name,
                                                 standings: keywords.standings(for: project), now: now))
            batches.append(NewsDetector.keywordRefresh(project: project, name: name,
                                                       states: keywords.refreshStates(for: project, now: now), now: now))

            var insights: StoreInsights?
            if case .ready(let analytics)? = purchases.storeAnalytics[project]?.value { insights = analytics.insights }
            batches.append(NewsDetector.surge(project: project, name: name, insights: insights, now: now))

            var detection: ReferralDetection?
            if case .ready(let found, _)? = purchases.referrals[project]?.value { detection = found }
            batches.append(NewsDetector.referrals(project: project, name: name, detection: detection, now: now))

            let feed = purchases.reviewFeeds[project]
            batches.append(NewsDetector.reviews(project: project, name: name,
                                                reviews: feed?.fetchedAt != nil ? feed?.reviews : nil, now: now))
            batches.append(NewsDetector.version(project: project, name: name,
                                                status: purchases.versions[project], now: now))
            batches.append(NewsDetector.release(project: project, name: name,
                                                report: store.releaseHealth(for: project), now: now))

            let usage = store.usage(for: project)
            if usage.hasUsageData {
                batches.append(NewsDetector.milestones(project: project, name: name, installs: usage.installs,
                                                       daily: store.dailyInstalls(for: project),
                                                       regions: Array(store.audienceInstalls(for: project).regions.keys),
                                                       now: now))
                let dau = store.activeUsers(for: project).day.current
                if let record = NewsDetector.dauRecord(project: project, name: name, yesterdayDAU: dau,
                                                       previousBest: memory.bestDAU[project], now: now) {
                    extra.append(record)
                }
                if dau > 0 { memory.bestDAU[project] = max(memory.bestDAU[project] ?? 0, dau) }
            } else {
                batches.append(NewsBatch(group: "milestones:\(project)", ready: false, items: []))
            }

            batches.append(NewsDetector.web(project: project, name: name, mentions: memory.web[project], now: now))
        }

        var fresh: [NewsItem] = []
        for batch in batches where batch.ready {
            if memory.baselined.insert(batch.group).inserted {
                // 처음 준비된 데이터 — 지난 일은 소식이 아니다.
                memory.seen.formUnion(batch.items.map(\.id))
                continue
            }
            fresh += batch.items.filter { memory.seen.insert($0.id).inserted }
        }
        fresh += extra.filter { memory.seen.insert($0.id).inserted }

        guard !fresh.isEmpty else {
            save()
            return
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: now) ?? .distantPast
        items = Array((fresh + items)
            .filter { $0.foundAt >= cutoff }
            .sorted { $0.foundAt == $1.foundAt ? $0.kind.order < $1.kind.order : $0.foundAt > $1.foundAt }
            .prefix(Self.keepCount))
        save()
        scheduleBriefing(now: now)
    }

    private func projects(_ store: FeedbackStore) -> [String] {
        store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject && !store.hiddenProjects.contains($0) }
    }

    // MARK: - 바깥 뉴스

    /// 6시간이 지난 앱만 다시 찾는다. `force` 면 모두.
    func refreshWebIfDue(force: Bool = false) async {
        guard let store, !isSearchingWeb else { return }
        isSearchingWeb = true
        defer { isSearchingWeb = false }
        let now = Date()
        for project in projects(store) {
            if !force, let last = memory.webFetchedAt[project], now.timeIntervalSince(last) < Self.webInterval { continue }
            let mentions = await WebMentions.search(terms: terms(for: project))
            memory.web[project] = mentions
            memory.webFetchedAt[project] = Date()
        }
        save()
    }

    /// 지금 쓰는 검색어. 정한 게 없으면 앱 이름 하나.
    func terms(for project: String) -> [String] {
        if let terms = searchTerms[project], !terms.isEmpty { return terms }
        return [store?.displayName(for: project) ?? project]
    }

    /// 검색어를 바꾸면 그 앱은 기준선부터 다시 잡는다 — 새 검색어로 찾은 지난 글이 한꺼번에
    /// 소식이 되지 않게.
    func setTerms(_ terms: [String], for project: String) {
        let cleaned = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        searchTerms[project] = cleaned.isEmpty ? nil : cleaned
        if let data = try? JSONEncoder().encode(searchTerms) { UserDefaults.standard.set(data, forKey: Self.termsKey) }
        memory.baselined.remove("web:\(project)")
        memory.web[project] = nil
        memory.webFetchedAt[project] = nil
        Task {
            await refreshWebIfDue()
            collect()
        }
    }

    // MARK: - 읽음

    var unreadCount: Int { items.filter { $0.foundAt > lastReadAt }.count }

    func unreadCount(for project: String?) -> Int {
        items.filter { $0.foundAt > lastReadAt && (project == nil || $0.project == project) }.count
    }

    func markAllRead() {
        lastReadAt = Date()
        memory.lastReadAt = lastReadAt
        save()
    }

    // MARK: - 브리핑

    /// 지금 화면에 보일 브리핑 — 지난 하루 동안 찾은 것에서 고른다.
    func briefing(now: Date = Date()) -> Briefing {
        let since = now.addingTimeInterval(-24 * 3600)
        return Briefing(items: items.filter { $0.foundAt > since }, name: name(of:))
    }

    private func name(of project: String) -> String { store?.displayName(for: project) ?? project }

    /// 다음 아침 9시 브리핑을 다시 건다. 지난 9시 뒤에 찾은 것이 재료다 — 9시 전에 찾은
    /// 것은 오늘 9시에, 뒤에 찾은 것은 내일 9시에 나온다. 고를 게 없으면 예약을 지운다.
    func scheduleBriefing(now: Date = Date()) {
        let calendar = Calendar.current
        guard let todayAt = calendar.date(bySettingHour: Self.digestHour, minute: 0, second: 0, of: now) else { return }
        let lastBoundary = todayAt <= now ? todayAt : calendar.date(byAdding: .day, value: -1, to: todayAt) ?? todayAt
        let next = calendar.date(byAdding: .day, value: 1, to: lastBoundary) ?? todayAt
        let briefing = Briefing(items: items.filter { $0.foundAt > lastBoundary }, name: name(of:))
        let enabled = alertsEnabled && store?.notificationsEnabled == true
        NotificationService.scheduleBriefing(id: Self.digestID, at: next,
                                             lines: enabled ? briefing.lines.map(\.title) : [],
                                             more: briefing.more)
    }

    // MARK: - 디스크

    private func save() {
        memory.items = items
        CacheFile.write(memory, to: Self.file)
    }
}

extension NewsKind {
    /// `allCases` 의 자리 — 같은 때 찾은 소식끼리의 차례.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

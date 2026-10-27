//
//  LeadStore.swift
//  FeedbackHubViewer
//
//  찾은 레딧 질문을 들고, 앱마다 언제 찾았는지 기억하고, 답했다 · 상관없다를 기기 사이에서
//  맞춘다.
//
//  질문 자체는 기기마다 찾는다(검색은 싸고, 글 본문까지 iCloud 에 올릴 까닭이 없다). 사람이
//  내린 판단 — 답함 · 상관없음 — 만 iCloud 키·값 저장소에 짧게 둔다. 그래야 맥에서 답한
//  질문이 아이폰에서 다시 "새 질문" 으로 뜨지 않는다.
//

import Foundation

@MainActor
final class LeadStore: ObservableObject {
    static let shared = LeadStore()

    @Published private var leads: [String: RedditLead] = [:]
    /// 프로젝트 → 마지막으로 찾은 때.
    @Published private(set) var searchedAt: [String: Date] = [:]
    /// 지금 찾고 있는 앱.
    @Published private(set) var searching: Set<String> = []
    /// 마지막 찾기에서 막힌 까닭(레딧이 막음 · 키 오류). 화면이 한 줄로 알린다.
    @Published private(set) var problem: String?
    /// 사용자가 고친 검색어. 없으면 번들 기본값.
    @Published private var custom: [String: LeadQueries] = [:]

    private static let fileName = "reddit-leads"
    private static let customKey = "reddit-lead-queries"
    private static let decisionsKey = "reddit-lead-decisions"
    private static let searchedKey = "reddit-lead-searched"
    /// 앱 하나를 다시 찾을 때까지.
    static let staleAfter: TimeInterval = 12 * 60 * 60

    private let cloud = NSUbiquitousKeyValueStore.default

    private struct Decision: Codable {
        let status: RedditLead.Status
        let at: Date
    }

    private init() {
        let saved = CacheFile.read([RedditLead].self, at: CacheFile.url(Self.fileName)) ?? []
        leads = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let decoded = try? JSONDecoder().decode([String: LeadQueries].self, from: data) {
            custom = decoded
        }
        searchedAt = (UserDefaults.standard.dictionary(forKey: Self.searchedKey) as? [String: Date]) ?? [:]
        applyCloudDecisions()
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud, queue: .main) { _ in
            Task { @MainActor in LeadStore.shared.applyCloudDecisions() }
        }
    }

    // MARK: - 읽기

    func queries(for project: String) -> LeadQueries? {
        custom[project.lowercased()] ?? LeadQueries.defaults[project.lowercased()]
    }

    /// 답할지 정하지 않은 글 — 질문 꼴이 먼저, 그 안에서 새 글부터.
    func open(for project: String?) -> [RedditLead] {
        leads.values.filter { $0.status == .new && (project == nil || $0.project == project) }
            .sorted {
                let a = $0.isQuestion == true, b = $1.isQuestion == true
                return a != b ? a : ($0.date ?? $0.foundAt) > ($1.date ?? $1.foundAt)
            }
    }

    func decided(for project: String?) -> [RedditLead] {
        leads.values.filter { $0.status != .new && (project == nil || $0.project == project) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 아직 안 본 새 질문 — 사이드바 뱃지.
    func unseenCount(for project: String?) -> Int {
        leads.values.filter { $0.status == .new && !$0.viewed && (project == nil || $0.project == project) }.count
    }

    // MARK: - 쓰기

    func setQueries(_ queries: LeadQueries, for project: String) {
        custom[project.lowercased()] = queries
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.customKey)
        }
    }

    /// 아직 안 본 새 질문의 id.
    func unseenIDs(for project: String?) -> Set<String> {
        Set(leads.values.filter { $0.status == .new && !$0.viewed && (project == nil || $0.project == project) }.map(\.id))
    }

    func markViewed(project: String?) {
        var changed = false
        for (id, lead) in leads where !lead.viewed && (project == nil || lead.project == project) {
            leads[id]?.viewed = true
            changed = true
        }
        if changed { persist() }
    }

    func decide(_ id: String, _ status: RedditLead.Status) {
        guard leads[id] != nil else { return }
        leads[id]?.status = status
        leads[id]?.viewed = true
        leads[id]?.updatedAt = Date()
        persist()
        pushDecisions()
    }

    // MARK: - 찾기

    /// 묵었으면 찾는다. 여러 앱이면 하나씩(레딧은 잇달아 부르면 막는다).
    func searchIfStale(_ projects: [String], force: Bool = false) async {
        for project in projects {
            let stale = searchedAt[project].map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true
            guard force || stale else { continue }
            await search(project)
        }
    }

    func search(_ project: String) async {
        guard let queries = queries(for: project), !searching.contains(project) else { return }
        searching.insert(project)
        defer { searching.remove(project) }
        let result = await RedditLeadSearch.search(project: project, queries: queries)
        problem = result.problem
        for lead in result.leads where leads[lead.id] == nil {
            leads[lead.id] = lead
        }
        // 한 달 넘은 것은 정리한다 — 답했든 안 했든 이제 늦었다.
        let cutoff = Date().addingTimeInterval(-RedditLeadSearch.maxAge)
        leads = leads.filter { ($0.value.date ?? $0.value.foundAt) > cutoff }
        searchedAt[project] = Date()
        UserDefaults.standard.set(searchedAt, forKey: Self.searchedKey)
        applyCloudDecisions()
        persist()
    }

    // MARK: - 맞추기

    private func persist() {
        CacheFile.write(Array(leads.values), to: CacheFile.url(Self.fileName))
    }

    private func pushDecisions() {
        var decisions = cloudDecisions()
        for lead in leads.values where lead.status != .new {
            decisions[lead.id] = Decision(status: lead.status, at: lead.updatedAt)
        }
        if let data = try? JSONEncoder().encode(decisions) {
            cloud.set(data, forKey: Self.decisionsKey)
            cloud.synchronize()
        }
    }

    private func cloudDecisions() -> [String: Decision] {
        guard let data = cloud.data(forKey: Self.decisionsKey),
              let decoded = try? JSONDecoder().decode([String: Decision].self, from: data) else { return [:] }
        return decoded
    }

    /// 다른 기기에서 내린 판단을 이 기기의 질문에 입힌다.
    private func applyCloudDecisions() {
        var changed = false
        for (id, decision) in cloudDecisions() {
            guard let lead = leads[id], decision.at > lead.updatedAt || lead.status == .new,
                  lead.status != decision.status else { continue }
            leads[id]?.status = decision.status
            leads[id]?.viewed = true
            leads[id]?.updatedAt = decision.at
            changed = true
        }
        if changed { persist() }
    }
}

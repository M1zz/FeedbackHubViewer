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
    /// flat feedback list.
    enum ViewMode: String, CaseIterable, Identifiable {
        case overview = "개요"
        case stats = "통계"
        case list = "목록"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .stats: return "chart.bar"
            case .list: return "list.bullet"
            }
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
        /// True for the bucket holding records with no project field.
        var isUnclassified: Bool { project == Feedback.unclassifiedProject }
    }

    // Raw data
    @Published private(set) var allFeedback: [Feedback] = []
    @Published private(set) var resolvedRecordType: String?

    // UI state
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var lastUpdated: Date?
    /// This account's CloudKit user record name — the value to register in an
    /// admin Security Role so it can read feedback. Shown in the toolbar.
    @Published var userRecordName: String?

    // Filters / sorting
    @Published var viewMode: ViewMode = .overview
    @Published var searchText = ""
    @Published var sortOption: SortOption = .newest
    @Published var selectedProject: String? = nil     // nil == all projects
    @Published var selectedVersion: String? = nil     // nil == all versions
    @Published var minimumRating: Int = 0             // 0 == any rating

    // Auto refresh
    @Published var autoRefresh = false {
        didSet { autoRefresh ? startAutoRefresh() : stopAutoRefresh() }
    }
    /// Seconds between automatic refreshes.
    let autoRefreshInterval: TimeInterval = 60

    private let service = CloudKitService()
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        noticeMessage = await service.accountStatusMessage()
        userRecordName = await service.currentUserRecordName()

        do {
            let outcome = try await service.fetchFeedback()
            allFeedback = outcome.feedback
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
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let ck = error as NSError
        return ck.domain == CKErrorDomain && ck.code == CKError.permissionFailure.rawValue
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
                                  last7Days: last7, latest: latest)
        }
        .sorted { ordered($0.project, $0.count, $1.project, $1.count) }
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

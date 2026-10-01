//
//  AppStoreConnectStore+Reviews.swift
//  FeedbackHubViewer
//
//  스토어 리뷰의 상태 — 앱마다 읽어 온 리뷰, 응답 달기 · 지우기, 그리고 전체 프로젝트의
//  우선순위 분석.
//
//  리뷰는 디스크에 둔다(ReviewManager 의 로컬 저장소와 같은 까닭). 앱이 스무 개면 전부
//  다시 받는 데 한참 걸리고, 그동안 빈 화면을 보여 줄 이유가 없다. 켜자마자 지난번에
//  받은 것을 보여 주고, 오래됐으면 뒤에서 새로 받는다.
//

import Foundation

/// 한 앱의 리뷰와, 그것을 언제 받았는지.
struct ReviewFeed {
    var reviews: [CustomerReview] = []
    var fetchedAt: Date?
    var isLoading = false
    var error: String?

    var unanswered: Int { reviews.filter { $0.response == nil }.count }
    var average: Double? { PriorityScorer.average(reviews) }
}

extension AppStoreConnectStore {

    /// 이보다 최근에 받았으면 다시 받지 않는다.
    static let reviewFreshness: TimeInterval = 30 * 60
    /// 우선순위 기록을 몇 개까지 남기나.
    static let priorityHistoryLimit = 20

    private struct StoredFeed: Codable {
        let reviews: [CustomerReview]
        let fetchedAt: Date
    }

    private static var reviewsFile: URL? { CacheFile.url("store-reviews") }
    private static var priorityFile: URL? { CacheFile.url("store-review-priority") }
    private static var viewedFile: URL? { CacheFile.url("store-reviews-viewed") }

    // MARK: - 디스크

    func restoreReviews() {
        if let stored = CacheFile.read([String: StoredFeed].self, at: Self.reviewsFile) {
            reviewFeeds = stored.mapValues { ReviewFeed(reviews: $0.reviews, fetchedAt: $0.fetchedAt) }
        }
        if let history = CacheFile.read([PriorityAnalysis].self, at: Self.priorityFile) {
            priorityHistory = history
            priority = history.first
        }
        viewedReviewIDs = CacheFile.read([String: Set<String>].self, at: Self.viewedFile) ?? [:]
        for bundleID in reviewFeeds.keys { seedViewedReviews(bundleID) }
    }

    /// 키를 바꾸거나 지우면 — 다른 계정의 리뷰가 남아 있으면 안 된다.
    func forgetReviews() {
        reviewFeeds = [:]
        versions = [:]
        priority = nil
        priorityHistory = []
        viewedReviewIDs = [:]
        CacheFile.remove(Self.reviewsFile)
        CacheFile.remove(Self.priorityFile)
        CacheFile.remove(Self.viewedFile)
    }

    private func persistReviews() {
        let stored = reviewFeeds.compactMapValues { feed in
            feed.fetchedAt.map { StoredFeed(reviews: feed.reviews, fetchedAt: $0) }
        }
        CacheFile.write(stored, to: Self.reviewsFile)
    }

    // MARK: - 새 리뷰

    /// 아직 안 본 리뷰 수. 한 앱(nil 이면 받아 둔 모든 앱).
    func newReviewCount(for bundleID: String?) -> Int {
        let keys = bundleID.map { [$0] } ?? Array(reviewFeeds.keys)
        return keys.reduce(0) { total, key in
            guard let viewed = viewedReviewIDs[key], let feed = reviewFeeds[key] else { return total }
            return total + feed.reviews.reduce(0) { $0 + (viewed.contains($1.id) ? 0 : 1) }
        }
    }

    /// 리뷰 탭을 열었을 때 — 그 앱(nil 이면 모든 앱)의 리뷰를 확인한 것으로.
    func markReviewsViewed(bundleID: String?) {
        var changed = false
        for key in bundleID.map({ [$0] }) ?? Array(reviewFeeds.keys) {
            guard let feed = reviewFeeds[key] else { continue }
            let ids = Set(feed.reviews.map(\.id))
            guard let viewed = viewedReviewIDs[key], !ids.isSubset(of: viewed) else { continue }
            viewedReviewIDs[key] = viewed.union(ids)
            changed = true
        }
        if changed { CacheFile.write(viewedReviewIDs, to: Self.viewedFile) }
    }

    /// 한 앱의 리뷰를 처음 받았으면 그때 있던 것은 새것으로 치지 않는다 — 처음 켠 날
    /// 리뷰 수백 개가 다 "새 리뷰"가 되면 뱃지가 아무 말도 안 하게 된다.
    private func seedViewedReviews(_ bundleID: String) {
        guard viewedReviewIDs[bundleID] == nil, let feed = reviewFeeds[bundleID] else { return }
        viewedReviewIDs[bundleID] = Set(feed.reviews.map(\.id))
        CacheFile.write(viewedReviewIDs, to: Self.viewedFile)
    }

    // MARK: - 읽기

    func unansweredReviews(for bundleID: String) -> Int {
        reviewFeeds[bundleID]?.unanswered ?? 0
    }

    func loadReviews(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        let feed = reviewFeeds[bundleID] ?? ReviewFeed()
        guard !feed.isLoading else { return }
        if !force, let fetched = feed.fetchedAt, Date().timeIntervalSince(fetched) < Self.reviewFreshness { return }

        reviewFeeds[bundleID, default: ReviewFeed()].isLoading = true
        reviewFeeds[bundleID]?.error = nil
        do {
            let app = try await resolveApp(bundleID)
            let reviews = try await client.reviews(appID: app.id)
            reviewFeeds[bundleID] = ReviewFeed(reviews: reviews, fetchedAt: Date())
            persistReviews()
            seedViewedReviews(bundleID)
            if let version = try? await client.latestVersion(appID: app.id) {
                versions[bundleID] = version
            }
        } catch {
            // 받아 둔 리뷰는 그대로 두고 왜 못 받았는지만 붙인다.
            reviewFeeds[bundleID]?.isLoading = false
            reviewFeeds[bundleID]?.error = error.localizedDescription
        }
    }

    /// 버전 상태만 — 리뷰가 디스크에서 와서 새로 받을 필요가 없을 때.
    func loadVersion(bundleID: String) async {
        guard let client, versions[bundleID] == nil else { return }
        guard let app = try? await resolveApp(bundleID),
              let version = try? await client.latestVersion(appID: app.id) else { return }
        versions[bundleID] = version
    }

    // MARK: - 응답

    /// 달거나 고친다. 스토어가 받아들인 응답을 그 자리에 끼운다 — 전부 다시 받지 않는다.
    func respond(to review: CustomerReview, in bundleID: String, text: String) async throws {
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        let response = try await client.respond(to: review.id, body: text)
        update(review.id, in: bundleID) { $0.response = response }
    }

    func deleteResponse(of review: CustomerReview, in bundleID: String) async throws {
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        guard let response = review.response else { return }
        try await client.deleteResponse(id: response.id)
        update(review.id, in: bundleID) { $0.response = nil }
    }

    private func update(_ reviewID: String, in bundleID: String, _ change: (inout CustomerReview) -> Void) {
        guard let index = reviewFeeds[bundleID]?.reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        change(&reviewFeeds[bundleID]!.reviews[index])
        persistReviews()
    }

    // MARK: - 우선순위

    var isAnalyzingPriority: Bool { priorityProgress != nil }

    /// 모든 앱의 결제 · 다운로드 · 리뷰를 모아 점수를 다시 낸다.
    ///
    /// 앱마다 차례로 읽는다. 한꺼번에 쏘면 App Store Connect 의 시간당 한도를 금방 쓴다.
    /// 한 앱을 못 읽어도 나머지는 선다 — 그 앱은 가진 신호만으로 점수를 받는다.
    func analyzePriority(projects: [(key: String, name: String)]) async {
        guard client != nil, !isAnalyzingPriority else { return }
        priorityProgress = "분석 준비 중…"
        defer { priorityProgress = nil }

        let hasSales = credentials?.hasVendorNumber == true
        if hasSales {
            priorityProgress = "최근 \(Self.salesDays)일 판매 리포트를 받는 중…"
            await loadSales()
        }

        var inputs: [PriorityInput] = []
        for (index, project) in projects.enumerated() {
            priorityProgress = "\(index + 1)/\(projects.count) · \(project.name)"
            if hasSales { await loadCatalog(bundleID: project.key) }
            await loadReviews(bundleID: project.key)

            let reviews = reviewFeeds[project.key]?.reviews ?? []
            var input = PriorityInput(key: project.key, name: project.name, paidPurchases: nil,
                                      proceedsLabel: "—", firstDownloads: nil, dailyDownloads: [],
                                      reviews: reviews)
            if let sales, let app = connectApp(for: project.key), let products = products(for: project.key) {
                let totals = sales.totals(app: app, products: products)
                input = PriorityInput(key: project.key, name: project.name,
                                      paidPurchases: totals.purchases,
                                      proceedsLabel: totals.proceedsLabel,
                                      firstDownloads: totals.firstDownloads,
                                      dailyDownloads: sales.firstDownloadSeries(appleID: app.id),
                                      reviews: reviews)
            }
            // 스토어에 없는 앱(개발 중 · 다른 계정)은 신호가 하나도 없다. 줄에서 뺀다.
            guard !reviews.isEmpty || input.paidPurchases != nil else { continue }
            inputs.append(input)
        }

        let analysis = PriorityAnalysis(date: Date(), rows: PriorityScorer.score(inputs),
                                        usedSales: hasSales && sales != nil)
        priority = analysis
        priorityHistory = Array(([analysis] + priorityHistory).prefix(Self.priorityHistoryLimit))
        CacheFile.write(priorityHistory, to: Self.priorityFile)
    }
}

extension AppStoreConnectStore.SalesWindow {
    /// 날짜순 하루 첫 다운로드. 리포트가 있었는데 이 앱 줄이 없던 날은 0이다.
    func firstDownloadSeries(appleID: String) -> [Int] {
        let byDay = firstDownloadsByDay[appleID] ?? [:]
        return dayKeys.map { byDay[$0] ?? 0 }
    }
}

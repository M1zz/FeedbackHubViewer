//
//  AppStoreConnectStore.swift
//  FeedbackHubViewer
//
//  App Store Connect에서 읽은 것의 상태 — 앱마다 스토어에 걸린 상품과 최근 30일 판매
//  ("앱 내 구입"), 스토어 메타데이터와 노출 · 전환(키워드 화면의 ASO 카드들).
//
//  `KeywordStore`처럼 `FeedbackStore`와 따로 선다. 읽는 곳(App Store Connect)도
//  실패하는 이유(키·권한)도 CloudKit과 겹치지 않는다. 둘이 나누는 것은 번들 ID뿐이다.
//
//  판매 리포트는 계정 전체가 하루 한 파일이라, 날짜별로 한 번 받으면 모든 앱이 그 안에
//  있다. 지난 날의 리포트는 바뀌지 않으므로 디스크에 두고 다시 받지 않는다.
//
//  ── 디스크에 먼저, 네트워크는 뒤에 ──
//
//  상품 · 노출 · 전환 · 링크 감지는 지난번에 받은 것을 디스크에서 먼저 그리고, 이번
//  실행에서 처음 볼 때 한 번 새로 받아 바뀐 것만 덮는다(`refreshed`). 새로 받다 실패하면
//  디스크의 것을 그대로 둔다 — 빈 화면보다 어제 숫자가 낫다.
//

import Foundation
import SwiftUI

@MainActor
final class AppStoreConnectStore: ObservableObject {

    @Published private(set) var credentials: AppStoreConnectCredentials?
    /// 아이폰 · 아이패드의 설정 시트. 맥은 설정 창(`Settings` 장면)이라 안 쓴다.
    @Published var isShowingSettings = false
    /// 번들 ID → 그 앱의 상품 상태.
    @Published private(set) var catalogs: [String: CatalogState] = [:]
    /// 최근 30일 판매(계정 전체). nil이면 아직 안 받았다.
    @Published private(set) var sales: SalesWindow?
    @Published private(set) var isLoadingSales = false
    @Published private(set) var salesError: String?

    /// 번들 ID → 스토어 메타데이터(이름 · 부제 · 키워드 · 프로모션 텍스트).
    @Published private(set) var metadata: [String: LoadState<StoreMetadata>] = [:]
    /// 번들 ID → 최근 30일 노출 · 전환.
    @Published private(set) var funnels: [String: LoadState<FunnelResult>] = [:]
    /// 번들 ID → 누가 링크했나(`AppStoreConnectStore+Referrals.swift`).
    @Published var referrals: [String: LoadState<ReferralResult>] = [:]
    /// 번들 ID → (출처 → 처음 본 날). 디스크에 남는다.
    var referralLedger: ReferralLedger = [:]
    /// 번들 ID → App Store 분석 리포트를 접은 것(`AppStoreConnectStore+StoreAnalytics.swift`).
    @Published var storeAnalytics: [String: LoadState<StoreAnalyticsResult>] = [:]
    /// 번들 ID → 리포트 전부를 훑은 결과. 디스크에 남는다.
    @Published var analyticsScans: [String: LoadState<AnalyticsScan>] = [:]
    /// "번들 ID|리포트 이름" → 그 리포트를 그대로 접은 것.
    @Published var analyticsDigests: [String: LoadState<AnalyticsDigest>] = [:]
    /// 계정의 앱마다 분석 리포트 요청이 있는가. 디스크에서 먼저 채운다.
    @Published var analyticsCoverage: LoadState<AnalyticsCoverage>?

    /// 번들 ID → 스토어 리뷰(`AppStoreConnectStore+Reviews.swift`). 디스크에서 먼저 채운다.
    @Published var reviewFeeds: [String: ReviewFeed] = [:]
    /// 번들 ID → 리뷰 탭에서 확인한 리뷰 id. 디스크에 남는다.
    @Published var viewedReviewIDs: [String: Set<String>] = [:]
    /// 번들 ID → 가장 최근 App Store 버전.
    @Published var versions: [String: AppVersionStatus] = [:]
    /// 전체 프로젝트의 우선순위 분석 — 지금 보이는 것과 지난 기록.
    @Published var priority: PriorityAnalysis?
    @Published var priorityHistory: [PriorityAnalysis] = []
    @Published var priorityProgress: String?

    /// 최근 30일 구독 이벤트(계정 전체, `AppStoreConnectStore+Funnels.swift`). nil 이면 아직.
    @Published var subscriptionEvents: SubscriptionEventWindow?
    @Published var isLoadingSubscriptionEvents = false
    @Published var subscriptionEventsError: String?
    /// 날짜 → 그날 구독 이벤트. 지난 날은 바뀌지 않는다.
    var subscriptionReportCache: [String: [SubscriptionEventLine]] = [:]

    enum LoadState<Value> {
        case loading
        case loaded(Value)
        case failed(String)

        var value: Value? {
            if case .loaded(let value) = self { return value }
            return nil
        }
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// 리포트 요청이 없으면 퍼널 대신 그렇다고 말한다 — 만들면 1~2일 뒤부터 쌓인다.
    enum FunnelResult {
        case noRequest
        case ready(StoreFunnel)
    }

    enum CatalogState {
        case loading
        case loaded(ConnectApp, [StoreProduct])
        case failed(String)
    }

    /// 판매를 몇 일 치 보는가.
    static let salesDays = 30

    private(set) var client: AppStoreConnect?
    /// 날짜 → 그날 판매. 디스크에 남는다.
    private var reportCache: [String: [SalesLine]] = [:]
    /// 이번 실행에서 네트워크로 새로 받았거나 받는 중인 것("funnel:번들 ID" 꼴).
    /// 디스크에서 채운 값은 여기 없어서, 처음 볼 때 한 번 새로 받는다.
    var refreshed: Set<String> = []
    /// 마지막으로 네트워크에서 받아 낸 때("funnel:번들 ID" · "sales" 꼴). 디스크에서 그린
    /// 값이 얼마나 묵었는지를 데이터 상태 칸이 말할 수 있게 디스크에 남는다.
    @Published private(set) var fetchedAt: [String: Date] = [:]

    private static var appsFile: URL? { CacheFile.url("connect-apps") }
    private static var catalogsFile: URL? { CacheFile.url("store-catalogs") }
    private static var salesFile: URL? { CacheFile.url("sales-days") }
    static var subscriptionEventsFile: URL? { CacheFile.url("subscription-event-days") }
    private static var fetchedAtFile: URL? { CacheFile.url("connect-fetched-at") }

    /// 디스크의 상품 목록 한 앱치.
    private struct StoredCatalog: Codable {
        let app: ConnectApp
        let products: [StoreProduct]
    }

    init() {
        credentials = AppStoreConnectKeychain.load()
        client = credentials.map(AppStoreConnect.init)
        restoreReviews()
        restoreReferralLedger()
        if credentials != nil { restoreStoreCaches() }
    }

    private func restoreStoreCaches() {
        apps = CacheFile.read([String: ConnectApp].self, at: Self.appsFile) ?? [:]
        for (bundleID, stored) in CacheFile.read([String: StoredCatalog].self, at: Self.catalogsFile) ?? [:] {
            catalogs[bundleID] = .loaded(stored.app, stored.products)
        }
        reportCache = CacheFile.read([String: [SalesLine]].self, at: Self.salesFile) ?? [:]
        subscriptionReportCache = CacheFile.read([String: [SubscriptionEventLine]].self,
                                                 at: Self.subscriptionEventsFile) ?? [:]
        fetchedAt = CacheFile.read([String: Date].self, at: Self.fetchedAtFile) ?? [:]
    }

    /// 네트워크에서 새로 받아 냈다고 적는다.
    func markFetched(_ key: String) {
        fetchedAt[key] = Date()
        CacheFile.write(fetchedAt, to: Self.fetchedAtFile)
    }

    /// 날짜별 리포트를 디스크에 쓸 때 남길 것 — 창(과 며칠 여유) 안의 날짜만. 빈 날은
    /// 최근 사흘이면 뺀다: 404 는 "그날 없음"과 "아직 안 나옴"을 가르지 않는다.
    static func keepsDay<Line>(_ key: String, _ lines: [Line]) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let day = { (offset: Int) in AppStoreConnect.day.string(from: calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()) }
        guard key >= day(salesDays + 5) else { return false }
        return !lines.isEmpty || key < day(3)
    }

    var isConfigured: Bool { credentials != nil }

    // MARK: - 자격 증명

    func save(_ new: AppStoreConnectCredentials) throws {
        try new.validate()
        try AppStoreConnectKeychain.save(new)
        credentials = new
        client = AppStoreConnect(credentials: new)
        forgetAccount()
    }

    func signOut() {
        AppStoreConnectKeychain.delete()
        credentials = nil
        client = nil
        forgetAccount()
    }

    /// 계정에 딸린 것을 전부 잊는다 — 키를 바꾸거나 지우면 다른 계정의 것이 남으면 안 된다.
    private func forgetAccount() {
        refreshed = []
        fetchedAt = [:]
        CacheFile.remove(Self.fetchedAtFile)
        catalogs = [:]
        CacheFile.remove(Self.appsFile)
        CacheFile.remove(Self.catalogsFile)
        CacheFile.remove(Self.salesFile)
        AnalyticsCache.forget()
        sales = nil
        salesError = nil
        reportCache = [:]
        metadata = [:]
        funnels = [:]
        apps = [:]
        forgetReviews()
        forgetSubscriptionEvents()
        forgetReferrals()
        forgetStoreAnalytics()
    }

    // MARK: - 앱 찾기

    private var apps: [String: ConnectApp] = [:]

    /// 번들 ID → App Store Connect 앱. 한 번 찾으면 이번 실행 동안 다시 안 묻는다.
    func resolveApp(_ bundleID: String) async throws -> ConnectApp {
        if let app = apps[bundleID] ?? connectApp(for: bundleID) { return app }
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        let app = try await client.app(bundleID: bundleID)
        apps[bundleID] = app
        CacheFile.write(apps, to: Self.appsFile)
        return app
    }

    // MARK: - 메타데이터

    func loadMetadata(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        if !force, let state = metadata[bundleID], !(state.value == nil && !state.isLoading) { return }
        metadata[bundleID] = .loading
        do {
            let app = try await resolveApp(bundleID)
            metadata[bundleID] = .loaded(try await client.metadata(appID: app.id))
            markFetched("metadata:\(bundleID)")
        } catch {
            metadata[bundleID] = .failed(error.localizedDescription)
        }
    }

    /// 고치고 나서 다시 읽는다 — 스토어가 받아들인 값이 화면에 남아야 한다.
    func saveMetadata(bundleID: String, edit: MetadataEdit) async throws {
        guard let client, let current = metadata[bundleID]?.value else { return }
        let draft = current.draft?.locales[edit.locale]
        let live = current.live.locales[edit.locale]
        try await client.save(edit,
                              appInfoLocalizationID: current.draft?.isAppInfoEditable == true ? draft?.appInfoLocalizationID : nil,
                              versionLocalizationID: current.draft?.isVersionEditable == true ? draft?.versionLocalizationID : nil,
                              promoVersionLocalizationID: live?.versionLocalizationID)
        await loadMetadata(bundleID: bundleID, force: true)
    }

    // MARK: - 노출 · 전환

    func loadFunnel(bundleID: String, force: Bool = false) async {
        await loadAnalytics("funnel", bundleID: bundleID, force: force, into: \.funnels,
                            noRequest: .noRequest) { client, requestID, appID in
            let funnel = try await client.funnel(requestID: requestID, appID: appID, days: Self.salesDays)
            return requestID == nil && funnel.instances == 0 ? nil : .ready(funnel)
        }
    }

    /// 분석 리포트로 만드는 것(퍼널 · 링크 감지)을 받는 공통 흐름.
    ///
    /// 처음 보면 디스크에 둔 리포트 파일로 먼저 그린다(`read` 에 요청 id 없이). 그다음
    /// 요청 id 를 붙여 다시 부르면, 인스턴스 목록만 새로 묻고 새 파일만 받아 덮는다.
    /// `read` 가 nil 이면 디스크에 그릴 것이 없다는 뜻이다.
    func loadAnalytics<Value>(_ kind: String, bundleID: String, force: Bool,
                              into state: ReferenceWritableKeyPath<AppStoreConnectStore, [String: LoadState<Value>]>,
                              noRequest: Value,
                              read: (AppStoreConnect, _ requestID: String?, _ appID: String) async throws -> Value?) async {
        guard let client else { return }
        let key = "\(kind):\(bundleID)"
        if !force, refreshed.contains(key) { return }
        refreshed.insert(key)

        if self[keyPath: state][bundleID]?.value == nil, let app = apps[bundleID],
           let cached = try? await read(client, nil, app.id), self[keyPath: state][bundleID]?.value == nil {
            self[keyPath: state][bundleID] = .loaded(cached)
        }
        if force || self[keyPath: state][bundleID]?.value == nil {
            self[keyPath: state][bundleID] = .loading
        }
        do {
            let app = try await resolveApp(bundleID)
            guard let request = try await client.analyticsRequestID(appID: app.id) else {
                self[keyPath: state][bundleID] = .loaded(noRequest)
                markFetched(key)
                return
            }
            if let value = try await read(client, request, app.id) {
                self[keyPath: state][bundleID] = .loaded(value)
            }
            markFetched(key)
        } catch {
            // 다음에 볼 때 다시 받는다. 디스크에서 그린 것이 있으면 그대로 둔다.
            refreshed.remove(key)
            if self[keyPath: state][bundleID]?.value == nil {
                self[keyPath: state][bundleID] = .failed(error.localizedDescription)
            }
        }
    }

    /// 리포트 요청을 만든다. 첫 데이터는 1~2일 뒤에 나온다.
    func requestAnalytics(bundleID: String) async {
        guard let client else { return }
        do {
            let app = try await resolveApp(bundleID)
            try await client.createAnalyticsRequest(appID: app.id)
            await loadFunnel(bundleID: bundleID, force: true)
            await loadReferrals(bundleID: bundleID, force: true)
        } catch {
            funnels[bundleID] = .failed(error.localizedDescription)
        }
    }

    // MARK: - 상품

    /// 디스크에 있으면 그것을 그대로 보이고, 이번 실행에서 처음 볼 때 한 번 새로 받는다.
    func loadCatalog(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        let key = "catalog:\(bundleID)"
        if !force, refreshed.contains(key) { return }
        refreshed.insert(key)
        let hasStored: Bool
        if case .loaded? = catalogs[bundleID] { hasStored = true } else { hasStored = false }
        if force || !hasStored { catalogs[bundleID] = .loading }
        do {
            let app = try await client.app(bundleID: bundleID)
            let products = try await client.products(appID: app.id)
            catalogs[bundleID] = .loaded(app, products)
            saveCatalogs()
            markFetched(key)
        } catch {
            refreshed.remove(key)
            if case .loaded? = catalogs[bundleID] { return }
            catalogs[bundleID] = .failed(error.localizedDescription)
        }
    }

    private func saveCatalogs() {
        var stored: [String: StoredCatalog] = [:]
        for (bundleID, state) in catalogs {
            if case .loaded(let app, let products) = state { stored[bundleID] = StoredCatalog(app: app, products: products) }
        }
        CacheFile.write(stored, to: Self.catalogsFile)
    }

    /// 이미 알아낸 App Store Connect 앱 id. 판매 리포트의 줄을 앱에 붙일 때 쓴다.
    func connectApp(for bundleID: String) -> ConnectApp? {
        if case .loaded(let app, _)? = catalogs[bundleID] { return app }
        return nil
    }

    func products(for bundleID: String) -> [StoreProduct]? {
        if case .loaded(_, let products)? = catalogs[bundleID] { return products }
        return nil
    }

    // MARK: - 판매

    /// 최근 30일 판매. 어제까지만 — 오늘 리포트는 아직 없다.
    func loadSales(force: Bool = false) async {
        guard let client, credentials?.hasVendorNumber == true else { return }
        guard force || (sales == nil && !isLoadingSales) else { return }
        isLoadingSales = true
        salesError = nil
        defer { isLoadingSales = false }

        let calendar = Calendar(identifier: .gregorian)
        let window = (1...Self.salesDays).compactMap { offset -> (key: String, date: Date)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (AppStoreConnect.day.string(from: date), date)
        }
        // 디스크에 있던 날들로 먼저 그린다. 빠진 날(대개 어제 하루)만 받고 나서 다시 그린다.
        if sales == nil {
            let stored = window.compactMap { day in reportCache[day.key].map { (key: day.key, lines: $0) } }
            if !stored.isEmpty { sales = SalesWindow(daily: stored, days: Self.salesDays, missingDays: 0) }
        }
        defer { CacheFile.write(reportCache.filter { Self.keepsDay($0.key, $0.value) }, to: Self.salesFile) }

        var days: [(key: String, lines: [SalesLine])] = []
        var missingDays = 0
        for (key, date) in window {
            if let cached = reportCache[key] { days.append((key, cached)); continue }
            do {
                let day = try await client.sales(on: date)
                if Self.keepsDay(key, day) { reportCache[key] = day }
                days.append((key, day))
            } catch {
                // 하루를 못 읽어도 나머지는 선다. 다만 키·권한 문제면 30번 되풀이할 이유가 없다.
                if let failure = error as? AppStoreConnect.Failure {
                    switch failure {
                    case .unauthorized, .forbidden, .missing:
                        salesError = failure.localizedDescription
                        return
                    default: break
                    }
                }
                missingDays += 1
            }
        }
        sales = SalesWindow(daily: days, days: Self.salesDays, missingDays: missingDays)
        markFetched("sales")
    }

    /// 최근 30일 판매를 Apple Identifier별로 접은 것.
    struct SalesWindow {
        let days: Int
        let missingDays: Int
        /// Apple Identifier → 합계.
        let byItem: [String: Totals]
        /// Apple Identifier → 날짜("yyyy-MM-dd") → 첫 다운로드. 추세를 가를 때 쓴다.
        let firstDownloadsByDay: [String: [String: Int]]
        /// 리포트를 받은 날짜들, 오래된 것부터.
        let dayKeys: [String]

        struct Totals {
            var units = 0
            var firstDownloads = 0
            var purchases = 0
            /// 0원에 받은 인앱 상품(프로모션 · 오퍼 코드).
            var freeRedemptions = 0
            /// 코드 이름 → 그 코드로 0원에 받은 건수.
            var codes: [String: Int] = [:]
            /// 통화 → 개발자 수익 합계.
            var proceeds: [String: Double] = [:]

            var proceedsLabel: String {
                let parts = proceeds.filter { $0.value != 0 }.sorted { $0.key < $1.key }
                    .map { AppStoreConnect.formatMoney($0.value, currency: $0.key) }
                return parts.isEmpty ? "—" : parts.joined(separator: " · ")
            }

            /// "LEEO 6,093건 · LEEO2 550건" — 많은 코드부터.
            var codesLabel: String {
                codes.sorted { $0.value > $1.value }
                    .map { "\($0.key) \(AppFormat.count($0.value))건" }
                    .joined(separator: " · ")
            }

            mutating func add(_ other: Totals) {
                units += other.units
                firstDownloads += other.firstDownloads
                purchases += other.purchases
                freeRedemptions += other.freeRedemptions
                for (code, count) in other.codes { codes[code, default: 0] += count }
                for (currency, amount) in other.proceeds { proceeds[currency, default: 0] += amount }
            }
        }

        init(daily: [(key: String, lines: [SalesLine])], days: Int, missingDays: Int) {
            self.days = days
            self.missingDays = missingDays
            self.dayKeys = daily.map(\.key).sorted()
            var byItem: [String: Totals] = [:]
            var byDay: [String: [String: Int]] = [:]
            for (day, lines) in daily {
                for line in lines where line.isFirstDownload {
                    byDay[line.appleID, default: [:]][day, default: 0] += line.units
                }
            }
            self.firstDownloadsByDay = byDay
            for line in daily.flatMap(\.lines) {
                var totals = byItem[line.appleID] ?? Totals()
                totals.units += line.units
                if line.isFirstDownload { totals.firstDownloads += line.units }
                if line.isPurchase { totals.purchases += line.units }
                if line.isFreeRedemption {
                    totals.freeRedemptions += line.units
                    totals.codes[line.promoCode.isEmpty ? "코드 없음" : line.promoCode, default: 0] += line.units
                }
                totals.proceeds[line.proceedsCurrency, default: 0] += Double(line.units) * line.proceedsPerUnit
                byItem[line.appleID] = totals
            }
            self.byItem = byItem
        }

        func totals(for id: String) -> Totals { byItem[id] ?? Totals() }

        /// 한 앱의 합계 — 앱 자체(다운로드) + 그 앱의 상품들(결제).
        func totals(app: ConnectApp, products: [StoreProduct]) -> Totals {
            var result = totals(for: app.id)
            for product in products { result.add(totals(for: product.id)) }
            return result
        }
    }
}

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
//  있다. 지난 날의 리포트는 바뀌지 않으므로 이번 실행 동안은 다시 받지 않는다.
//

import Foundation
import SwiftUI

@MainActor
final class AppStoreConnectStore: ObservableObject {

    @Published private(set) var credentials: AppStoreConnectCredentials?
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

    private var client: AppStoreConnect?
    private var reportCache: [String: [SalesLine]] = [:]

    init() {
        credentials = AppStoreConnectKeychain.load()
        client = credentials.map(AppStoreConnect.init)
    }

    var isConfigured: Bool { credentials != nil }

    // MARK: - 자격 증명

    func save(_ new: AppStoreConnectCredentials) throws {
        try new.validate()
        try AppStoreConnectKeychain.save(new)
        credentials = new
        client = AppStoreConnect(credentials: new)
        catalogs = [:]
        sales = nil
        salesError = nil
        reportCache = [:]
        metadata = [:]
        funnels = [:]
        apps = [:]
    }

    func signOut() {
        AppStoreConnectKeychain.delete()
        credentials = nil
        client = nil
        catalogs = [:]
        sales = nil
        salesError = nil
        reportCache = [:]
        metadata = [:]
        funnels = [:]
        apps = [:]
    }

    // MARK: - 앱 찾기

    private var apps: [String: ConnectApp] = [:]

    /// 번들 ID → App Store Connect 앱. 한 번 찾으면 이번 실행 동안 다시 안 묻는다.
    private func resolveApp(_ bundleID: String) async throws -> ConnectApp {
        if let app = apps[bundleID] ?? connectApp(for: bundleID) { return app }
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        let app = try await client.app(bundleID: bundleID)
        apps[bundleID] = app
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
        guard let client else { return }
        if !force, let state = funnels[bundleID], !(state.value == nil && !state.isLoading) { return }
        funnels[bundleID] = .loading
        do {
            let app = try await resolveApp(bundleID)
            guard let request = try await client.analyticsRequestID(appID: app.id) else {
                funnels[bundleID] = .loaded(.noRequest)
                return
            }
            let funnel = try await client.funnel(requestID: request, appID: app.id, days: Self.salesDays)
            funnels[bundleID] = .loaded(.ready(funnel))
        } catch {
            funnels[bundleID] = .failed(error.localizedDescription)
        }
    }

    /// 리포트 요청을 만든다. 첫 데이터는 1~2일 뒤에 나온다.
    func requestAnalytics(bundleID: String) async {
        guard let client else { return }
        do {
            let app = try await resolveApp(bundleID)
            try await client.createAnalyticsRequest(appID: app.id)
            await loadFunnel(bundleID: bundleID, force: true)
        } catch {
            funnels[bundleID] = .failed(error.localizedDescription)
        }
    }

    // MARK: - 상품

    func loadCatalog(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        if !force, let state = catalogs[bundleID] {
            if case .failed = state {} else { return }
        }
        catalogs[bundleID] = .loading
        do {
            let app = try await client.app(bundleID: bundleID)
            let products = try await client.products(appID: app.id)
            catalogs[bundleID] = .loaded(app, products)
        } catch {
            catalogs[bundleID] = .failed(error.localizedDescription)
        }
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
        var lines: [SalesLine] = []
        var missingDays = 0
        for offset in 1...Self.salesDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = AppStoreConnect.day.string(from: date)
            if let cached = reportCache[key] { lines += cached; continue }
            do {
                let day = try await client.sales(on: date)
                reportCache[key] = day
                lines += day
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
        sales = SalesWindow(lines: lines, days: Self.salesDays, missingDays: missingDays)
    }

    /// 최근 30일 판매를 Apple Identifier별로 접은 것.
    struct SalesWindow {
        let days: Int
        let missingDays: Int
        /// Apple Identifier → 합계.
        let byItem: [String: Totals]

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

        init(lines: [SalesLine], days: Int, missingDays: Int) {
            self.days = days
            self.missingDays = missingDays
            var byItem: [String: Totals] = [:]
            for line in lines {
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

//
//  StoreAnalytics.swift
//  FeedbackHubViewer
//
//  App Store 분석 리포트를 화면이 읽을 숫자로 접는다 — 순수 함수만 있다.
//
//  받는 일은 `AppStoreConnect+AnalyticsReports.swift`, 행은 머리글 이름 → 값의 사전이다.
//  열 이름은 2026-10 에 클립키보드의 실제 파일에서 확인한 것이다. Apple 이 열을 바꾸면
//  그 숫자만 0 으로 빠지고 나머지는 그대로 선다 — 그래서 열을 못 찾으면 화면이
//  "모름" 이라고 말하게 nil 을 둔다.
//
//  ── 누구를 세나 ──
//
//  스토어 쪽(노출 · 조회 · 다운로드 · 구매)은 모든 사람을 센다. 앱 쪽(세션 · 삭제 ·
//  크래시)은 기기 설정에서 "앱 개발자와 공유" 를 켠 사람만 센다. 그래서 앱 쪽 숫자는
//  실제보다 작고, 비율(세션당 길이 · 삭제의 나이)로 읽어야 한다. 그 몫이 얼마인지가
//  "App Opt In" 리포트다.
//
//  어느 리포트든 Apple 의 프라이버시 기준 아래인 작은 칸은 통째로 빠진다.
//

import Foundation

/// 이 화면이 받는 리포트. 값이 API 의 리포트 이름이다.
enum StoreAnalyticsReport: String, CaseIterable {
    case sessions = "App Sessions Standard"
    case installsDeletions = "App Store Installation and Deletion Standard"
    case downloads = "App Downloads Standard"
    case engagement = "App Store Discovery and Engagement Standard"
    case purchases = "App Store Purchases Standard"
    case subscriptionEvents = "App Store Subscription Event Report Standard"
    case subscriptionStates = "App Store Subscription State Report Standard"
    case webPreview = "App Store Web Preview Engagement Standard"
    case installPerformance = "App Install Performance"
    case crashes = "App Crashes"
    case optIn = "App Opt In"
    case platformInstalls = "Platform App Installs"

    var granularity: AnalyticsGranularity { self == .crashes ? .monthly : .daily }
}

/// 한 칸의 몫 — 막대 하나.
struct AnalyticsShare: Identifiable, Hashable {
    let key: String
    let value: Double
    var id: String { key }
}

/// 날짜 하나의 두 값 — 추이 차트 한 점.
struct AnalyticsDayPoint: Identifiable, Hashable {
    let day: String
    let first: Double
    let second: Double
    var id: String { day }
}

struct StoreAnalytics {
    let days: Int
    /// 받은 인스턴스 수 전부. 0 이면 아직 아무 파일도 없다.
    let instances: Int

    var sessions: Sessions?
    var installs: Installs?
    var downloads: Downloads?
    var engagement: Engagement?
    var purchases: Purchases?
    var webPreview: WebPreview?
    var installPerformance: InstallPerformance?
    var crashes: Crashes?
    var optIn: OptIn?
    var platformInstalls: PlatformInstalls?
    var subscriptionEvents: AnalyticsDigest?
    var subscriptionStates: AnalyticsDigest?
    /// 받은 원본 그대로 — 기간을 나눠 다시 읽는 분석(`StoreInsights`)이 쓴다.
    let raw: [StoreAnalyticsReport: AnalyticsRows]
    /// 원본에서 읽은 판정. 받을 때 한 번만 계산한다 — 행이 수만 개라 화면이 그릴 때마다 할 일이 아니다.
    private(set) var insights: StoreInsights?

    // MARK: - 사용

    struct Sessions {
        let sessions: Double
        /// 초.
        let duration: Double
        /// 날마다 센 고유 기기의 합 — 나누면 하루 평균 사용 기기.
        let deviceDays: Double
        let activeDays: Int
        /// 날짜 → (세션, 고유 기기).
        let daily: [AnalyticsDayPoint]
        let byVersion: [AnalyticsShare]
        let byTerritory: [AnalyticsShare]
        let byDevice: [AnalyticsShare]
        let bySource: [AnalyticsShare]
        /// 받은 지 며칠 된 사람이 쓰나 — 세션 기준.
        let byAge: [AnalyticsShare]

        var averageDuration: Double? { sessions > 0 ? duration / sessions : nil }
        var dailyDevices: Double? { activeDays > 0 ? deviceDays / Double(activeDays) : nil }
        var sessionsPerDevice: Double? { deviceDays > 0 ? sessions / deviceDays : nil }
    }

    // MARK: - 설치 · 삭제

    struct Installs {
        /// 설치 종류(첫 설치 · 다시 받기 · 업데이트 · 복원) → 건수.
        let installsByType: [AnalyticsShare]
        let deletions: Double
        /// 새로 들어온 설치(첫 설치 + 다시 받기).
        let newInstalls: Double
        /// 날짜 → (새 설치, 삭제).
        let daily: [AnalyticsDayPoint]
        /// 받고 나서 지운 때까지.
        let deletionAge: [AnalyticsShare]
        let deletionsByVersion: [AnalyticsShare]
        let deletionsByTerritory: [AnalyticsShare]
        let deletionsBySource: [AnalyticsShare]

        /// 지운 것 가운데 받고 일주일 안에 지운 몫 — 첫 경험에서 떠난 사람.
        ///
        /// "삭제 ÷ 새 설치" 는 쓰지 않는다. 지운 사람 대부분이 창보다 먼저 받은 사람이라
        /// 클립키보드에서 238% 가 나왔다 — 숫자는 맞아도 뜻이 없다.
        var earlyDeletions: Double {
            deletionAge.filter { $0.key == StoreAnalytics.ageBuckets[0] || $0.key == StoreAnalytics.ageBuckets[1] }
                .reduce(0) { $0 + $1.value }
        }
        var earlyDeletionShare: Double? { deletions > 0 ? earlyDeletions / deletions : nil }
    }

    // MARK: - 다운로드

    struct Downloads {
        let byType: [AnalyticsShare]
        /// 첫 다운로드만.
        let firstByTerritory: [AnalyticsShare]
        let firstByDevice: [AnalyticsShare]
        let firstByPage: [AnalyticsShare]
        /// 업데이트(자동 + 수동)가 어느 버전으로 갔나 — 새 버전이 퍼지는 속도.
        let updatesByVersion: [AnalyticsShare]
        let byPlatform: [AnalyticsShare]
        /// 날짜 → (첫 다운로드, 다시 받기).
        let daily: [AnalyticsDayPoint]

        var firstTime: Double { byType.first { $0.key == "First-time download" }?.value ?? 0 }
        var redownloads: Double { byType.first { $0.key == "Redownload" }?.value ?? 0 }
    }

    // MARK: - 스토어 참여

    struct Engagement {
        /// 사건(노출 · 조회 · 탭) → 고유 기기.
        let events: [AnalyticsShare]
        /// 탭이 무엇이었나(받기 · 열기 · 업데이트 · 공유 …).
        let taps: [AnalyticsShare]
        /// 조회한 페이지 종류(제품 페이지 · 개발자 페이지 · 개인정보 · 버전 기록 …).
        let pageViews: [AnalyticsShare]
        let impressionsBySource: [AnalyticsShare]
        let impressionsByTerritory: [AnalyticsShare]
        let impressionsByDevice: [AnalyticsShare]

        func count(_ event: String) -> Double { events.first { $0.key == event }?.value ?? 0 }
    }

    // MARK: - 구매

    struct Purchases {
        let purchases: Double
        let sales: Double
        let proceeds: Double
        let payingUsers: Double
        /// 상품(콘텐츠 이름) → 건수, 수익.
        let byProduct: [AnalyticsShare]
        let proceedsByProduct: [AnalyticsShare]
        let byTerritory: [AnalyticsShare]
        let proceedsByTerritory: [AnalyticsShare]
        let byPaymentMethod: [AnalyticsShare]
        let byType: [AnalyticsShare]
        let byDevice: [AnalyticsShare]
        /// 날짜 → (구매, 수익 USD).
        let daily: [AnalyticsDayPoint]
        /// 받은 날 → 산 날까지(구매 건수).
        let purchaseAge: [AnalyticsShare]

        /// 돈이 0인 구매(무료 상품 · 오퍼 코드 · 가족 공유 등).
        var freePurchases: Double { max(0, purchases - payingUsers) }
    }

    // MARK: - 웹 미리보기

    struct WebPreview {
        let pageViews: Double
        let taps: [AnalyticsShare]
        let byBrowser: [AnalyticsShare]
        let byTerritory: [AnalyticsShare]
        let byDevice: [AnalyticsShare]
    }

    // MARK: - 설치 성능

    struct InstallPerformance {
        let attempts: Double
        let failures: Double
        /// 밀리초, 건수로 무게를 단 중앙값. 평균은 백그라운드에서 몇 시간 걸린 업데이트
        /// 몇 건에 끌려가서(클립키보드에서 28분) 쓰지 않는다.
        let medianDuration: Double?
        let durationByPackage: [AnalyticsShare]
        let failuresByPlatform: [AnalyticsShare]
        let bySource: [AnalyticsShare]

        var successRate: Double? { attempts > 0 ? (attempts - failures) / attempts : nil }
    }

    // MARK: - 크래시

    struct Crashes {
        let crashes: Double
        let devices: Double
        /// 리포트의 달("2026-09-01").
        let months: [String]
        let byVersion: [AnalyticsShare]
        let byPlatform: [AnalyticsShare]
        let byDevice: [AnalyticsShare]
    }

    // MARK: - 분석 공유 동의

    struct OptIn {
        let downloading: Double
        let optingIn: Double
        var rate: Double? { downloading > 0 ? optingIn / downloading : nil }
    }

    // MARK: - 설치 경로

    struct PlatformInstalls {
        let installs: Double
        let byChannel: [AnalyticsShare]
        let byType: [AnalyticsShare]
        let byPlatform: [AnalyticsShare]
    }
}

// MARK: - 접기

extension StoreAnalytics {

    typealias Row = [String: String]

    /// 리포트마다 받은 행으로 만든다. 행이 없는 리포트의 칸은 nil.
    init(days: Int, rows: [StoreAnalyticsReport: AnalyticsRows]) {
        self.days = days
        raw = rows
        instances = rows.values.reduce(0) { $0 + $1.instances }
        func present(_ report: StoreAnalyticsReport) -> AnalyticsRows? {
            guard let found = rows[report], !found.byDate.isEmpty else { return nil }
            return found
        }
        sessions = present(.sessions).map(Self.readSessions)
        installs = present(.installsDeletions).map(Self.readInstalls)
        downloads = present(.downloads).map(Self.readDownloads)
        engagement = present(.engagement).map(Self.readEngagement)
        purchases = present(.purchases).map(Self.readPurchases)
        webPreview = present(.webPreview).map(Self.readWebPreview)
        installPerformance = present(.installPerformance).map(Self.readInstallPerformance)
        crashes = present(.crashes).map(Self.readCrashes)
        optIn = present(.optIn).map(Self.readOptIn)
        platformInstalls = present(.platformInstalls).map(Self.readPlatformInstalls)
        subscriptionEvents = present(.subscriptionEvents).map { AnalyticsDigest(rows: $0) }
        subscriptionStates = present(.subscriptionStates).map { AnalyticsDigest(rows: $0) }
        insights = StoreInsights(self)
    }

    /// 원본에 행이 있는 날짜들. 창(`days`)보다 훨씬 적으면 요청을 만든 지 얼마 안 된 것이다.
    var coveredDays: [String] {
        Set(raw.values.flatMap { $0.byDate.keys }).sorted()
    }

    var isEmpty: Bool {
        sessions == nil && installs == nil && downloads == nil && engagement == nil && purchases == nil
            && webPreview == nil && installPerformance == nil && crashes == nil && optIn == nil
            && platformInstalls == nil && subscriptionEvents == nil && subscriptionStates == nil
    }

    // MARK: 리포트별

    static func readSessions(_ report: AnalyticsRows) -> Sessions {
        let rows = report.all
        let daily = report.byDate.map { day, rows in
            AnalyticsDayPoint(day: day, first: sum(rows, "Sessions"), second: sum(rows, "Unique Devices"))
        }.sorted { $0.day < $1.day }
        return Sessions(sessions: sum(rows, "Sessions"),
                        duration: sum(rows, "Total Session Duration"),
                        deviceDays: sum(rows, "Unique Devices"),
                        activeDays: report.byDate.count,
                        daily: daily,
                        byVersion: tally(rows, by: "App Version", value: "Sessions"),
                        byTerritory: tally(rows, by: "Territory", value: "Sessions"),
                        byDevice: tally(rows, by: "Device", value: "Sessions"),
                        bySource: tally(rows, by: "Source Type", value: "Sessions"),
                        byAge: ageTally(rows, value: "Sessions"))
    }

    static func readInstalls(_ report: AnalyticsRows) -> Installs {
        let rows = report.all
        let installs = rows.filter { $0["Event"] == "Install" }
        let deletes = rows.filter { $0["Event"] == "Delete" }
        let fresh: Set<String> = ["First-time download", "Redownload"]
        let daily = report.byDate.map { day, rows in
            AnalyticsDayPoint(day: day,
                              first: sum(rows.filter { $0["Event"] == "Install" && fresh.contains($0["Download Type"] ?? "") }, "Counts"),
                              second: sum(rows.filter { $0["Event"] == "Delete" }, "Counts"))
        }.sorted { $0.day < $1.day }
        return Installs(installsByType: tally(installs, by: "Download Type", value: "Counts"),
                        deletions: sum(deletes, "Counts"),
                        newInstalls: sum(installs.filter { fresh.contains($0["Download Type"] ?? "") }, "Counts"),
                        daily: daily,
                        deletionAge: ageTally(deletes, value: "Counts"),
                        deletionsByVersion: tally(deletes, by: "App Version", value: "Counts"),
                        deletionsByTerritory: tally(deletes, by: "Territory", value: "Counts"),
                        deletionsBySource: tally(deletes, by: "Source Type", value: "Counts"))
    }

    static func readDownloads(_ report: AnalyticsRows) -> Downloads {
        let rows = report.all
        let first = rows.filter { $0["Download Type"] == "First-time download" }
        let updates = rows.filter { ($0["Download Type"] ?? "").hasSuffix("update") }
        let daily = report.byDate.map { day, rows in
            AnalyticsDayPoint(day: day,
                              first: sum(rows.filter { $0["Download Type"] == "First-time download" }, "Counts"),
                              second: sum(rows.filter { $0["Download Type"] == "Redownload" }, "Counts"))
        }.sorted { $0.day < $1.day }
        return Downloads(byType: tally(rows, by: "Download Type", value: "Counts"),
                         firstByTerritory: tally(first, by: "Territory", value: "Counts"),
                         firstByDevice: tally(first, by: "Device", value: "Counts"),
                         firstByPage: tally(first, by: "Page Type", value: "Counts"),
                         updatesByVersion: tally(updates, by: "App Version", value: "Counts"),
                         byPlatform: tally(rows, by: "Platform Version", value: "Counts"),
                         daily: daily)
    }

    static func readEngagement(_ report: AnalyticsRows) -> Engagement {
        let rows = report.all
        // 고유 기기가 있으면 그것, 없으면 건수.
        let unique: (Row) -> Double = { number($0["Unique Counts"]) ?? number($0["Counts"]) ?? 0 }
        let impressions = rows.filter { $0["Event"] == "Impression" }
        return Engagement(events: tally(rows, by: "Event", value: unique),
                          taps: tally(rows.filter { $0["Event"] == "Tap" }, by: "Engagement Type", value: "Counts"),
                          pageViews: tally(rows.filter { $0["Event"] == "Page view" }, by: "Page Type", value: unique),
                          impressionsBySource: tally(impressions, by: "Source Type", value: unique),
                          impressionsByTerritory: tally(impressions, by: "Territory", value: unique),
                          impressionsByDevice: tally(impressions, by: "Device", value: unique))
    }

    static func readPurchases(_ report: AnalyticsRows) -> Purchases {
        let rows = report.all
        let daily = report.byDate.map { day, rows in
            AnalyticsDayPoint(day: day, first: sum(rows, "Purchases"), second: sum(rows, "Proceeds in USD"))
        }.sorted { $0.day < $1.day }
        return Purchases(purchases: sum(rows, "Purchases"),
                         sales: sum(rows, "Sales in USD"),
                         proceeds: sum(rows, "Proceeds in USD"),
                         payingUsers: sum(rows, "Paying Users"),
                         byProduct: tally(rows, by: "Content Name", value: "Purchases"),
                         proceedsByProduct: tally(rows, by: "Content Name", value: "Proceeds in USD"),
                         byTerritory: tally(rows, by: "Territory", value: "Purchases"),
                         proceedsByTerritory: tally(rows, by: "Territory", value: "Proceeds in USD"),
                         byPaymentMethod: tally(rows, by: "Payment Method", value: "Purchases"),
                         byType: tally(rows, by: "Purchase Type", value: "Purchases"),
                         byDevice: tally(rows, by: "Device", value: "Purchases"),
                         daily: daily,
                         purchaseAge: ageTally(rows, value: "Purchases"))
    }

    static func readWebPreview(_ report: AnalyticsRows) -> WebPreview {
        let rows = report.all
        let views = rows.filter { $0["Event"] == "Page view" }
        return WebPreview(pageViews: sum(views, "Counts"),
                          taps: tally(rows.filter { $0["Event"] == "Tap" }, by: "Engagement Type", value: "Counts"),
                          byBrowser: tally(views, by: "Browser", value: "Counts"),
                          byTerritory: tally(views, by: "Territory", value: "Counts"),
                          byDevice: tally(views, by: "Device", value: "Counts"))
    }

    static func readInstallPerformance(_ report: AnalyticsRows) -> InstallPerformance {
        let rows = report.all
        let failures = rows.filter { $0["Install Status"] == "Failure" }
        // 설치 시간은 칸마다의 평균이라, 칸을 건수만큼 무게로 단 중앙값을 쓴다.
        var all: [(value: Double, weight: Double)] = []
        var byPackage: [String: [(value: Double, weight: Double)]] = [:]
        for row in rows where row["Install Status"] == "Success" {
            guard let average = number(row["Avg Install Duration"]), let count = number(row["Counts"]), count > 0 else { continue }
            all.append((average, count))
            byPackage[label(row["Install Package Type"]), default: []].append((average, count))
        }
        return InstallPerformance(attempts: sum(rows, "Counts"),
                                  failures: sum(failures, "Counts"),
                                  medianDuration: weightedMedian(all),
                                  durationByPackage: byPackage
                                    .compactMap { key, values in weightedMedian(values).map { AnalyticsShare(key: key, value: $0) } }
                                    .sorted { $0.value > $1.value },
                                  failuresByPlatform: tally(failures, by: "Platform Version", value: "Counts"),
                                  bySource: tally(rows, by: "Download Info", value: "Counts"))
    }

    static func readCrashes(_ report: AnalyticsRows) -> Crashes {
        let rows = report.all
        return Crashes(crashes: sum(rows, "Crashes"),
                       devices: sum(rows, "Unique Devices"),
                       months: report.byDate.keys.sorted(),
                       byVersion: tally(rows, by: "App Version", value: "Crashes"),
                       byPlatform: tally(rows, by: "Platform Version", value: "Crashes"),
                       byDevice: tally(rows, by: "Device", value: "Crashes"))
    }

    static func readOptIn(_ report: AnalyticsRows) -> OptIn {
        let rows = report.all
        return OptIn(downloading: sum(rows, "Downloading Users"), optingIn: sum(rows, "Users Opting-In"))
    }

    static func readPlatformInstalls(_ report: AnalyticsRows) -> PlatformInstalls {
        let rows = report.all
        return PlatformInstalls(installs: sum(rows, "Installs"),
                                byChannel: tally(rows, by: "Channel", value: "Installs"),
                                byType: tally(rows, by: "Install Type", value: "Installs"),
                                byPlatform: tally(rows, by: "Platform Version", value: "Installs"))
    }

    // MARK: 셈

    static func number(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: ""))
    }

    static func weightedMedian(_ values: [(value: Double, weight: Double)]) -> Double? {
        let sorted = values.sorted { $0.value < $1.value }
        let half = sorted.reduce(0) { $0 + $1.weight } / 2
        guard half > 0 else { return nil }
        var running = 0.0
        for item in sorted {
            running += item.weight
            if running >= half { return item.value }
        }
        return sorted.last?.value
    }

    static func sum(_ rows: [Row], _ column: String) -> Double {
        rows.reduce(0) { $0 + (number($1[column]) ?? 0) }
    }

    /// 빈 칸은 "없음" 으로 모은다 — 빼 버리면 합이 안 맞는다.
    static func label(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "(없음)" }
        return value
    }

    static func tally(_ rows: [Row], by column: String, value: String) -> [AnalyticsShare] {
        tally(rows, by: column) { number($0[value]) ?? 0 }
    }

    static func tally(_ rows: [Row], by column: String, value: (Row) -> Double) -> [AnalyticsShare] {
        var totals: [String: Double] = [:]
        for row in rows { totals[label(row[column]), default: 0] += value(row) }
        return totals.filter { $0.value > 0 }
            .map { AnalyticsShare(key: $0.key, value: $0.value) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    }

    /// 받은 날("App Download Date") → 행의 날짜까지 며칠인지 네 칸으로.
    /// 받은 날이 비어 있으면(창보다 오래전에 받았거나 모름) "오래전 · 모름".
    static let ageBuckets = ["받은 날", "1~7일", "8~30일", "31일 넘게", "오래전 · 모름"]

    static func ageTally(_ rows: [Row], value: String) -> [AnalyticsShare] {
        var totals: [String: Double] = [:]
        for row in rows {
            let count = number(row[value]) ?? 0
            guard count > 0 else { continue }
            totals[ageBucket(downloaded: row["App Download Date"], on: row["Date"]), default: 0] += count
        }
        return ageBuckets.compactMap { key in totals[key].map { AnalyticsShare(key: key, value: $0) } }
    }

    static func ageBucket(downloaded: String?, on date: String?) -> String {
        guard let downloaded, let date,
              let start = AppStoreConnect.day.date(from: downloaded),
              let end = AppStoreConnect.day.date(from: date) else { return ageBuckets[4] }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case ..<1: return ageBuckets[0]
        case 1...7: return ageBuckets[1]
        case 8...30: return ageBuckets[2]
        default: return ageBuckets[3]
        }
    }

    // MARK: 원문을 사람 말로

    /// 리포트에 나오는 영어 값을 한국어로. 모르는 값은 원문 그대로 — 감추면 새 값이 생긴 걸 모른다.
    static func word(_ value: String) -> String {
        switch value {
        case "First-time download": return "첫 다운로드"
        case "Redownload": return "다시 받기"
        case "Manual update": return "수동 업데이트"
        case "Auto-update": return "자동 업데이트"
        case "Update": return "업데이트"
        case "Restore": return "복원"
        case "Reinstall": return "재설치"
        case "First-time install": return "첫 설치"
        case "Impression": return "노출"
        case "Page view": return "페이지 조회"
        case "Tap": return "탭"
        case "Get": return "받기"
        case "Open": return "열기"
        case "Re-download": return "다시 받기"
        case "Share": return "공유"
        case "Product page": return "제품 페이지"
        case "Store sheet": return "스토어 시트(앱 안 · 웹 배너)"
        case "No page": return "페이지 없이(목록 · 검색 결과)"
        case "Developer page": return "개발자 페이지"
        case "App privacy": return "개인정보 상세"
        case "App version history": return "버전 기록"
        case "App Store search": return "App Store 검색"
        case "App Store browse": return "App Store 둘러보기"
        case "App referrer": return "다른 앱에서"
        case "Web referrer": return "웹에서"
        case "Unavailable": return "모름"
        case "In-app purchase": return "앱 내 구입"
        case "Auto-renewable subscription": return "자동 갱신 구독"
        case "Paid app": return "유료 앱"
        case "Other": return "기타"
        case "Desktop": return "Mac"
        case "Apple Vision": return "Vision Pro"
        case "Diff package update": return "차분 업데이트"
        case "Full package update": return "전체 업데이트"
        case "Full install": return "전체 설치"
        case "Non App Store": return "App Store 밖"
        case "View in Mac App Store": return "Mac App Store 에서 보기"
        case "Developer preview page": return "개발자 페이지로"
        case "Customer review modal open (\"more\")": return "리뷰 더 보기"
        case "(없음)": return "(없음)"
        default:
            if let name = Locale(identifier: "ko_KR").localizedString(forRegionCode: value), value.count == 2 {
                return name
            }
            return value
        }
    }
}

// MARK: - 아무 리포트나

/// 열의 뜻을 모르는 리포트를 그대로 접는다 — 숫자 열은 합(평균 열은 평균), 나머지 열은
/// 그 숫자로 무게를 단 상위 값. 구독 이벤트처럼 이 앱에 아직 행이 없어 열을 못 본
/// 리포트와, 전체 훑기에서 고른 리포트가 이걸로 보인다.
struct AnalyticsDigest {
    let rowCount: Int
    let days: [String]
    let measures: [Measure]
    let dimensions: [Dimension]
    /// 상위 값의 무게로 쓴 숫자 열.
    let weight: String?

    struct Measure: Identifiable, Hashable {
        let column: String
        let value: Double
        /// 합이 아니라 평균인가(이름에 Avg · Average · Rate · Percent 가 든 열).
        let isAverage: Bool
        var id: String { column }
    }

    struct Dimension: Identifiable, Hashable {
        let column: String
        let top: [AnalyticsShare]
        let distinct: Int
        var id: String { column }
    }

    /// 몇 번째 열이 날짜 · 앱 이름 같은 뻔한 것인지.
    private static let skipped: Set<String> = ["Date", "Install Day", "App Name", "App Apple Identifier"]
    /// 숫자로 읽히지만 세는 값이 아닌 열.
    private static let identifiers: Set<String> = ["Content Apple Identifier", "Browser Version", "Subscription Apple Identifier",
                                                   "Subscription Group Apple Identifier", "Original Transaction ID"]

    init(rows report: AnalyticsRows) {
        let rows = report.all
        rowCount = rows.count
        days = report.byDate.keys.sorted()
        var columns: [String] = []
        for row in rows.prefix(50) {
            for column in row.keys where !columns.contains(column) { columns.append(column) }
        }
        columns.sort()
        columns.removeAll { Self.skipped.contains($0) }

        func isNumeric(_ column: String) -> Bool {
            guard !Self.identifiers.contains(column), !column.hasSuffix("Date") else { return false }
            let values = rows.lazy.compactMap { $0[column] }.filter { !$0.isEmpty }
            guard values.first(where: { _ in true }) != nil else { return false }
            return values.allSatisfy { StoreAnalytics.number($0) != nil }
        }
        let numeric = columns.filter(isNumeric)
        measures = numeric.map { column in
            let lowered = column.lowercased()
            let isAverage = ["avg", "average", "rate", "percent", "median"].contains { lowered.contains($0) }
            let total = StoreAnalytics.sum(rows, column)
            let filled = rows.filter { StoreAnalytics.number($0[column]) != nil }.count
            return Measure(column: column, value: isAverage ? (filled > 0 ? total / Double(filled) : 0) : total,
                           isAverage: isAverage)
        }
        let countLike = measures.filter { !$0.isAverage }
        let weight = countLike.first { ["Counts", "Unique Devices", "Installs", "Sessions", "Purchases"].contains($0.column) }?.column
            ?? countLike.first?.column
        self.weight = weight
        dimensions = columns.filter { !numeric.contains($0) }.map { column in
            let tallied = StoreAnalytics.tally(rows, by: column) { row in
                weight.flatMap { StoreAnalytics.number(row[$0]) } ?? 1
            }
            return Dimension(column: column, top: Array(tallied.prefix(6)), distinct: tallied.count)
        }.filter { !$0.top.isEmpty }
    }
}

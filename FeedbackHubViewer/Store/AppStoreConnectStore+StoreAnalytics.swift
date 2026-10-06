//
//  AppStoreConnectStore+StoreAnalytics.swift
//  FeedbackHubViewer
//
//  "스토어 분석" 탭의 상태 — 앱마다 분석 리포트 열두 종을 접은 것(`StoreAnalytics`),
//  리포트 전부를 훑은 결과(`AnalyticsScan`), 훑기에서 고른 리포트 하나를 접은 것.
//
//  받는 흐름은 퍼널 · 링크 감지와 같다(`loadAnalytics`): 디스크의 파일로 먼저 그리고,
//  이번 실행에서 처음 볼 때 새 파일만 받아 덮는다. 처음 한 번은 리포트마다 한 달 치
//  파일을 받아서 1~2분 걸린다. 그다음부터는 하루 한 파일씩이다.
//

import Foundation

extension AppStoreConnectStore {

    enum StoreAnalyticsResult {
        case noRequest
        case ready(StoreAnalytics)
    }

    private static var scansFile: URL? { CacheFile.url("analytics-scans") }
    private static var coverageFile: URL? { CacheFile.url("analytics-coverage") }

    func forgetStoreAnalytics() {
        storeAnalytics = [:]
        analyticsScans = [:]
        analyticsDigests = [:]
        analyticsCoverage = nil
        CacheFile.remove(Self.scansFile)
        CacheFile.remove(Self.coverageFile)
    }

    /// 열두 종을 네 개씩 나란히 받는다. 공통 층이 날짜마다 한 벌로 맞춰 준다.
    func loadStoreAnalytics(bundleID: String, force: Bool = false) async {
        await loadAnalytics("store-analytics", bundleID: bundleID, force: force, into: \.storeAnalytics,
                            noRequest: .noRequest) { client, requestID, appID in
            let analytics = try await Self.storeAnalytics(client: client, requestID: requestID, appID: appID)
            return requestID == nil && analytics.instances == 0 ? nil : .ready(analytics)
        }
    }

    private static func storeAnalytics(client: AppStoreConnect, requestID: String?, appID: String) async throws -> StoreAnalytics {
        var rows: [StoreAnalyticsReport: AnalyticsRows] = [:]
        let reports = StoreAnalyticsReport.allCases
        var index = 0
        while index < reports.count {
            let batch = reports[index..<min(index + 4, reports.count)]
            index += batch.count
            try await withThrowingTaskGroup(of: (StoreAnalyticsReport, AnalyticsRows).self) { group in
                for report in batch {
                    group.addTask {
                        let found = try await client.analyticsRows(named: report.rawValue, granularity: report.granularity,
                                                                   requestID: requestID, appID: appID, days: salesDays)
                        return (report, found)
                    }
                }
                for try await (report, found) in group { rows[report] = found }
            }
        }
        return StoreAnalytics(days: salesDays, rows: rows)
    }

    // MARK: - 전부 훑기

    /// 디스크에 둔 지난 훑기. 없으면 nil.
    func restoredScan(bundleID: String) -> AnalyticsScan? {
        CacheFile.read([String: AnalyticsScan].self, at: Self.scansFile)?[bundleID]
    }

    /// 리포트 전부(150여 종)에 데이터가 있는지 묻는다. 종류마다 한 번이라 손으로 누를 때만.
    func scanAnalytics(bundleID: String) async {
        guard let client else { return }
        if analyticsScans[bundleID]?.value == nil { analyticsScans[bundleID] = .loading }
        do {
            let app = try await resolveApp(bundleID)
            guard let request = try await client.analyticsRequestID(appID: app.id) else {
                analyticsScans[bundleID] = .failed("이 앱은 아직 분석 리포트를 요청하지 않았습니다.")
                return
            }
            let scan = try await client.scanAnalytics(requestID: request)
            analyticsScans[bundleID] = .loaded(scan)
            var stored = CacheFile.read([String: AnalyticsScan].self, at: Self.scansFile) ?? [:]
            stored[bundleID] = scan
            CacheFile.write(stored, to: Self.scansFile)
        } catch {
            if analyticsScans[bundleID]?.value == nil {
                analyticsScans[bundleID] = .failed(error.localizedDescription)
            }
        }
    }

    static func digestKey(_ bundleID: String, _ report: String) -> String { "\(bundleID)|\(report)" }

    /// 훑기에서 고른 리포트 하나를 받아 그대로 접는다.
    func loadDigest(bundleID: String, entry: AnalyticsScan.Entry) async {
        guard let client, let granularity = entry.granularity else { return }
        let key = Self.digestKey(bundleID, entry.report.name)
        if analyticsDigests[key]?.isLoading == true || analyticsDigests[key]?.value != nil { return }
        analyticsDigests[key] = .loading
        do {
            let app = try await resolveApp(bundleID)
            let request = try await client.analyticsRequestID(appID: app.id)
            let rows = try await client.analyticsRows(named: entry.report.name, granularity: granularity,
                                                      requestID: request, appID: app.id, days: Self.salesDays)
            analyticsDigests[key] = .loaded(AnalyticsDigest(rows: rows))
        } catch {
            analyticsDigests[key] = .failed(error.localizedDescription)
        }
    }

    // MARK: - 계정 전체의 요청 현황

    /// 디스크의 지난 결과로 먼저 그리고, 이번 실행에서 처음 볼 때 한 번 새로 묻는다.
    func loadAnalyticsCoverage(force: Bool = false) async {
        guard let client else { return }
        if analyticsCoverage == nil, let stored = CacheFile.read(AnalyticsCoverage.self, at: Self.coverageFile) {
            analyticsCoverage = .loaded(stored)
        }
        let key = "analytics-coverage"
        if !force, refreshed.contains(key) { return }
        refreshed.insert(key)
        if analyticsCoverage?.value == nil { analyticsCoverage = .loading }
        do {
            let coverage = try await client.analyticsCoverage()
            analyticsCoverage = .loaded(coverage)
            CacheFile.write(coverage, to: Self.coverageFile)
            markFetched(key)
        } catch {
            refreshed.remove(key)
            if analyticsCoverage?.value == nil { analyticsCoverage = .failed(error.localizedDescription) }
        }
    }

    /// 요청이 없는 앱 전부에 요청을 만든다. 스토어에 보이는 것은 아무것도 바뀌지 않는다.
    /// 만들지 못한 앱의 이름과 까닭을 돌려준다.
    func requestAnalyticsForAll() async -> [String] {
        guard let client, let coverage = analyticsCoverage?.value else { return [] }
        var failures: [String] = []
        for entry in coverage.missing {
            do {
                try await client.createAnalyticsRequest(appID: entry.app.id)
            } catch {
                failures.append("\(entry.app.name): \(error.localizedDescription)")
            }
        }
        await loadAnalyticsCoverage(force: true)
        return failures
    }
}

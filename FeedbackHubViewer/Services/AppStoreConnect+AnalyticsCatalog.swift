//
//  AppStoreConnect+AnalyticsCatalog.swift
//  FeedbackHubViewer
//
//  리포트 요청 하나에 든 리포트 전부(2026-10 기준 156종)를 훑는다.
//
//  대부분은 그 앱이 쓰지 않는 프레임워크(ARKit · CarPlay · 블루투스 …)의 것이라 비어
//  있다. 그래서 종류마다 인스턴스가 있는지만 먼저 묻고, 있는 것만 행으로 받아 요약한다
//  (`AnalyticsDigest`). 화면이 따로 읽는 리포트(`StoreAnalytics`)에 없는 것 — 위젯 ·
//  단축어 · 구독 이벤트 같은 것 — 이 여기서 처음 보인다.
//

import Foundation

/// 리포트 요청 안의 리포트 한 종류.
struct AnalyticsReportInfo: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    /// APP_STORE_ENGAGEMENT · COMMERCE · APP_USAGE · FRAMEWORK_USAGE · PERFORMANCE
    let category: String

    var categoryLabel: String { Self.label(forCategory: category) }

    static func label(forCategory category: String) -> String {
        switch category {
        case "APP_STORE_ENGAGEMENT": return "스토어 참여"
        case "COMMERCE": return "다운로드 · 구매"
        case "APP_USAGE": return "앱 사용"
        case "FRAMEWORK_USAGE": return "기능 사용"
        case "PERFORMANCE": return "성능"
        default: return category
        }
    }

    /// 카테고리를 보이는 차례.
    static let categoryOrder = ["APP_STORE_ENGAGEMENT", "COMMERCE", "APP_USAGE", "PERFORMANCE", "FRAMEWORK_USAGE"]
}

/// 훑은 결과 — 데이터가 있는 리포트와, 그 리포트에 나온 단위.
struct AnalyticsScan: Codable {
    let scannedAt: Date
    let total: Int
    let reports: [Entry]

    struct Entry: Codable, Hashable, Identifiable {
        let report: AnalyticsReportInfo
        /// 단위 → 인스턴스 수. 비어 있지 않은 것만 담긴다.
        let instances: [String: Int]
        var id: String { report.id }

        /// 행으로 받을 단위. 날 단위가 있으면 그것, 없으면 달.
        var granularity: AnalyticsGranularity? {
            if instances["DAILY"] != nil { return .daily }
            if instances["MONTHLY"] != nil { return .monthly }
            return nil
        }
    }
}

extension AppStoreConnect {

    /// 요청 안의 리포트 전부.
    func analyticsReports(requestID: String) async throws -> [AnalyticsReportInfo] {
        let doc = try await list("v1/analyticsReportRequests/\(requestID)/reports", ["limit": "200"])
        return doc.data.compactMap { item in
            guard let name = item.string("name") else { return nil }
            return AnalyticsReportInfo(id: item.id, name: name, category: item.string("category") ?? "")
        }
    }

    /// 모든 리포트에 인스턴스가 있는지 묻는다. 종류마다 한 번씩이라 여덟 개씩 나란히.
    func scanAnalytics(requestID: String) async throws -> AnalyticsScan {
        let reports = try await analyticsReports(requestID: requestID)
        var entries: [AnalyticsScan.Entry] = []
        var index = 0
        while index < reports.count {
            let batch = reports[index..<min(index + 8, reports.count)]
            index += batch.count
            try await withThrowingTaskGroup(of: AnalyticsScan.Entry?.self) { group in
                for report in batch {
                    group.addTask {
                        let doc = try await self.list("v1/analyticsReports/\(report.id)/instances", ["limit": "200"])
                        var counts: [String: Int] = [:]
                        for instance in doc.data {
                            counts[instance.string("granularity") ?? "?", default: 0] += 1
                        }
                        return counts.isEmpty ? nil : AnalyticsScan.Entry(report: report, instances: counts)
                    }
                }
                for try await entry in group {
                    if let entry { entries.append(entry) }
                }
            }
        }
        entries.sort {
            let left = AnalyticsReportInfo.categoryOrder.firstIndex(of: $0.report.category) ?? 99
            let right = AnalyticsReportInfo.categoryOrder.firstIndex(of: $1.report.category) ?? 99
            return left != right ? left < right : $0.report.name < $1.report.name
        }
        return AnalyticsScan(scannedAt: Date(), total: reports.count, reports: entries)
    }
}

// MARK: - 계정 전체의 요청 현황

/// 계정의 앱마다 분석 리포트 요청이 있는가. 요청은 만든 날부터만 쌓이고 지난 기록은
/// 안 생겨서, 없는 앱은 하루하루 기록을 잃고 있다.
struct AnalyticsCoverage: Codable {
    let checkedAt: Date
    let apps: [Entry]

    struct Entry: Codable, Hashable, Identifiable {
        let app: ConnectApp
        let hasRequest: Bool
        var id: String { app.id }
    }

    var missing: [Entry] { apps.filter { !$0.hasRequest } }
}

extension AppStoreConnect {

    /// 계정의 앱 전부와 각 앱의 살아 있는 요청 여부. 앱마다 한 번씩이라 여덟 개씩 나란히.
    func analyticsCoverage() async throws -> AnalyticsCoverage {
        let doc = try await list("v1/apps", ["fields[apps]": "name,bundleId", "limit": "200"])
        let apps = doc.data.map { ConnectApp(id: $0.id, name: $0.string("name") ?? $0.id, bundleID: $0.string("bundleId") ?? "") }
        var entries: [AnalyticsCoverage.Entry] = []
        var index = 0
        while index < apps.count {
            let batch = apps[index..<min(index + 8, apps.count)]
            index += batch.count
            try await withThrowingTaskGroup(of: AnalyticsCoverage.Entry.self) { group in
                for app in batch {
                    group.addTask {
                        AnalyticsCoverage.Entry(app: app, hasRequest: try await self.analyticsRequestID(appID: app.id) != nil)
                    }
                }
                for try await entry in group { entries.append(entry) }
            }
        }
        entries.sort { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        return AnalyticsCoverage(checkedAt: Date(), apps: entries)
    }
}

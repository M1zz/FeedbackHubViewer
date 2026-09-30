//
//  AppStoreConnect+AnalyticsReports.swift
//  FeedbackHubViewer
//
//  App Store 분석 리포트(Analytics Reports API)를 행으로 받는 공통 층.
//
//  이 층이 아는 것은 "어느 리포트를, 며칠 치, 날짜마다 한 벌씩" 뿐이고, 행을 무엇으로
//  읽을지는 모른다. 노출 · 전환 퍼널(`AppStoreConnect+ASO.swift`)과 링크 감지
//  (`AppStoreConnect+Referrals.swift`)가 같은 행을 다르게 읽는다.
//
//  흐름: 앱마다 ONGOING 리포트 요청이 하나 있고, Apple이 그 안에 리포트 종류별로
//  하루 한 인스턴스를 만든다. 인스턴스마다 세그먼트(미리 서명된 gzip TSV 주소)가 있다.
//
//  ── 한 날짜가 두 파일에 들어 있다 ──
//
//  인스턴스는 가공한 날짜별로 나오는데, **한 날짜가 연속된 두 파일에 똑같이 들어
//  있다**(9월 22일 파일에 20 · 21일, 23일 파일에 21 · 22일). 파일을 그냥 더하면 모든 날이
//  두 번 세어진다 — 실제로 첫 다운로드가 판매 리포트의 두 배로 나왔다. 그래서 날짜마다
//  가장 늦게 가공된 파일 하나만 쓴다(늦은 쪽이 고쳐진 값일 수 있다).
//
//  ── 받은 파일은 디스크에 둔다 ──
//
//  한 번 가공된 인스턴스는 바뀌지 않는다. 그래서 파일은 인스턴스 id 로 디스크에 두고
//  (`AnalyticsCache`), 다음부터는 인스턴스 목록만 물어 새로 생긴 것만 받는다. 목록도
//  남겨 두어서, 앱을 켜자마자 네트워크 없이 지난번 결과를 그릴 수 있다(`requestID: nil`).
//

import Foundation

/// 받을 수 있는 분석 리포트. 값이 API의 리포트 이름이다.
///
/// Standard 와 Detailed 는 같은 사건을 다른 해상도로 센다. Detailed 에만 출처의 이름
/// (`Source Info` — 웹 도메인 · 앱 번들 ID)과 캠페인이 있지만, 프라이버시 임계값 때문에
/// 작은 칸이 통째로 빠져 합계가 Standard 보다 크게 작다. 그래서 **합계는 Standard,
/// 출처의 이름은 Detailed** 로 읽는다.
enum AnalyticsReport: String {
    case engagementStandard = "App Store Discovery and Engagement Standard"
    case downloadsStandard = "App Downloads Standard"
    case engagementDetailed = "App Store Discovery and Engagement Detailed"
    case downloadsDetailed = "App Downloads Detailed"
}

/// 한 리포트를 날짜별로 한 벌씩 모은 것.
struct AnalyticsRows {
    /// 날짜("yyyy-MM-dd") → 그날의 행. 행은 머리글 이름 → 값.
    var byDate: [String: [[String: String]]] = [:]
    /// 읽은 인스턴스 수. 0이면 리포트가 아직 안 쌓였다(요청을 만든 지 1~2일 안).
    var instances = 0

    /// 날짜 차례와 무관한 모든 행.
    var all: [[String: String]] { byDate.values.flatMap { $0 } }
}

extension AppStoreConnect {

    // MARK: 요청

    /// 이 앱의 살아 있는 리포트 요청. 없으면 nil — 만들어야 1~2일 뒤부터 쌓인다.
    func analyticsRequestID(appID: String) async throws -> String? {
        let doc = try await list("v1/apps/\(appID)/analyticsReportRequests", [:])
        return doc.data.first {
            $0.string("accessType") == "ONGOING" && $0.bool("stoppedDueToInactivity") != true
        }?.id
    }

    /// 계속 쌓이는(ONGOING) 리포트 요청을 만든다. 앱마다 하나면 되고, 그 안에
    /// Standard 와 Detailed 가 다 들어 있다.
    func createAnalyticsRequest(appID: String) async throws {
        _ = try await write("POST", "v1/analyticsReportRequests", body: [
            "data": [
                "type": "analyticsReportRequests",
                "attributes": ["accessType": "ONGOING"],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]]
            ]
        ])
    }

    // MARK: 행

    /// 최근 `days`일의 행을 날짜마다 한 벌씩(머리말).
    ///
    /// `requestID` 가 nil 이면 네트워크 없이 디스크에 둔 파일만 읽는다 — 지난번에 본
    /// 인스턴스 목록과 그 파일들. 있으면 목록을 새로 묻고, 디스크에 없는 파일만 받는다.
    ///
    /// 가공일로 먼저 거르는 창을 사흘 넓게 잡는다 — 가공은 사건보다 하루 이틀 늦어서,
    /// 창 첫날의 행이 그보다 늦게 가공된 파일에 들어 있다.
    func analyticsRows(_ report: AnalyticsReport, requestID: String?, appID: String,
                       days: Int) async throws -> AnalyticsRows {
        let calendar = Calendar(identifier: .gregorian)
        let cutoff = Self.day.string(from: calendar.date(byAdding: .day, value: -(days + 3), to: Date()) ?? Date())
        let firstDay = Self.day.string(from: calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date())

        let recent: [AnalyticsCache.Instance]
        if let requestID {
            let reports = try await list("v1/analyticsReportRequests/\(requestID)/reports", ["filter[name]": report.rawValue])
            guard let found = reports.data.first else { return AnalyticsRows() }
            let instances = try await list("v1/analyticsReports/\(found.id)/instances", [
                "filter[granularity]": "DAILY", "limit": "200"
            ])
            recent = instances.data
                .map { AnalyticsCache.Instance(id: $0.id, processingDate: $0.string("processingDate") ?? "") }
                .filter { $0.processingDate >= cutoff }
            AnalyticsCache.remember(recent, appID: appID, report: report)
        } else {
            recent = AnalyticsCache.instances(appID: appID, report: report).filter { $0.processingDate >= cutoff }
        }

        var result = AnalyticsRows()
        /// 날짜 → 그 날짜를 준 파일의 가공일. 늦게 가공된 파일이 이긴다.
        var processedFor: [String: String] = [:]
        for instance in recent {
            let segments: [Data]
            if let cached = AnalyticsCache.segments(instanceID: instance.id) {
                segments = cached
            } else if requestID != nil {
                segments = try await downloadSegments(instanceID: instance.id)
                AnalyticsCache.store(segments, instanceID: instance.id)
            } else {
                continue
            }
            result.instances += 1
            var rowsByDate: [String: [[String: String]]] = [:]
            for row in Self.rows(gzipped: segments) {
                guard row["App Apple Identifier"] == nil || row["App Apple Identifier"] == appID,
                      let date = row["Date"], date >= firstDay else { continue }
                rowsByDate[date, default: []].append(row)
            }
            for (date, rows) in rowsByDate where instance.processingDate > (processedFor[date] ?? "") {
                processedFor[date] = instance.processingDate
                result.byDate[date] = rows
            }
        }
        return result
    }

    /// 한 인스턴스의 모든 세그먼트를 받은 그대로(gzip).
    private func downloadSegments(instanceID: String) async throws -> [Data] {
        let segments = try await list("v1/analyticsReportInstances/\(instanceID)/segments", [:])
        var files: [Data] = []
        for segment in segments.data {
            guard let link = segment.string("url").flatMap(URL.init(string:)) else { continue }
            // 미리 서명된 주소라 인증 머리를 붙이지 않는다.
            let (data, _) = try await URLSession.shared.data(from: link)
            files.append(data)
        }
        return files
    }

    /// gzip 세그먼트들을 행으로.
    static func rows(gzipped segments: [Data]) -> [[String: String]] {
        segments.flatMap { data -> [[String: String]] in
            guard let text = gunzip(data).flatMap({ String(data: $0, encoding: .utf8) }) else { return [] }
            return rows(text)
        }
    }

    /// 탭으로 나뉜 표를 머리글 이름으로 읽는다.
    static func rows(_ text: String) -> [[String: String]] {
        var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst()
        return lines.map { Dictionary(zip(header, $0), uniquingKeysWith: { first, _ in first }) }
    }
}

// MARK: - 디스크

/// 받은 분석 리포트 파일과, 리포트마다 최근에 본 인스턴스 목록.
///
/// 파일은 인스턴스 id 하나에 한 파일(받은 gzip 그대로)이라 작고, 목록에서 빠진
/// 인스턴스(창 밖으로 밀려난 것)의 파일은 목록을 고칠 때 함께 지운다.
/// 계정에 딸린 것이라 키를 바꾸거나 지우면 `forget()` 으로 통째로 지운다.
enum AnalyticsCache {

    struct Instance: Codable, Hashable {
        let id: String
        let processingDate: String
    }

    /// 앱 id → 리포트 이름 → 최근에 본 인스턴스.
    private typealias Index = [String: [String: [Instance]]]

    private static var indexFile: URL? { CacheFile.url("analytics-index") }

    private static var directory: URL? {
        guard let base = CacheFile.url("analytics-index")?.deletingLastPathComponent() else { return nil }
        let directory = base.appendingPathComponent("analytics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func file(_ instanceID: String) -> URL? {
        directory?.appendingPathComponent("\(instanceID).json")
    }

    static func instances(appID: String, report: AnalyticsReport) -> [Instance] {
        CacheFile.read(Index.self, at: indexFile)?[appID]?[report.rawValue] ?? []
    }

    /// 새 목록으로 바꾸고, 빠진 인스턴스의 파일을 지운다.
    static func remember(_ instances: [Instance], appID: String, report: AnalyticsReport) {
        var index = CacheFile.read(Index.self, at: indexFile) ?? [:]
        let old = index[appID]?[report.rawValue] ?? []
        guard old != instances else { return }
        index[appID, default: [:]][report.rawValue] = instances
        CacheFile.write(index, to: indexFile)
        let kept = Set(instances.map(\.id))
        for gone in old where !kept.contains(gone.id) { CacheFile.remove(file(gone.id)) }
    }

    static func segments(instanceID: String) -> [Data]? {
        CacheFile.read([Data].self, at: file(instanceID))
    }

    static func store(_ segments: [Data], instanceID: String) {
        CacheFile.write(segments, to: file(instanceID))
    }

    static func forget() {
        CacheFile.remove(indexFile)
        CacheFile.remove(directory)
    }
}

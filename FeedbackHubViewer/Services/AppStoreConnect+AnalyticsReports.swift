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
    /// 가공일로 먼저 거르는 창을 사흘 넓게 잡는다 — 가공은 사건보다 하루 이틀 늦어서,
    /// 창 첫날의 행이 그보다 늦게 가공된 파일에 들어 있다.
    func analyticsRows(_ report: AnalyticsReport, requestID: String, appID: String,
                       days: Int) async throws -> AnalyticsRows {
        let calendar = Calendar(identifier: .gregorian)
        let cutoff = Self.day.string(from: calendar.date(byAdding: .day, value: -(days + 3), to: Date()) ?? Date())
        let firstDay = Self.day.string(from: calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date())

        let reports = try await list("v1/analyticsReportRequests/\(requestID)/reports", ["filter[name]": report.rawValue])
        guard let found = reports.data.first else { return AnalyticsRows() }
        let instances = try await list("v1/analyticsReports/\(found.id)/instances", [
            "filter[granularity]": "DAILY", "limit": "200"
        ])
        let recent = instances.data.filter { ($0.string("processingDate") ?? "") >= cutoff }

        var result = AnalyticsRows(instances: recent.count)
        /// 날짜 → 그 날짜를 준 파일의 가공일. 늦게 가공된 파일이 이긴다.
        var processedFor: [String: String] = [:]
        for instance in recent {
            let processed = instance.string("processingDate") ?? ""
            var rowsByDate: [String: [[String: String]]] = [:]
            for row in try await segmentRows(instanceID: instance.id) {
                guard row["App Apple Identifier"] == nil || row["App Apple Identifier"] == appID,
                      let date = row["Date"], date >= firstDay else { continue }
                rowsByDate[date, default: []].append(row)
            }
            for (date, rows) in rowsByDate where processed > (processedFor[date] ?? "") {
                processedFor[date] = processed
                result.byDate[date] = rows
            }
        }
        return result
    }

    /// 한 인스턴스의 모든 세그먼트를 받아 행으로.
    private func segmentRows(instanceID: String) async throws -> [[String: String]] {
        let segments = try await list("v1/analyticsReportInstances/\(instanceID)/segments", [:])
        var rows: [[String: String]] = []
        for segment in segments.data {
            guard let link = segment.string("url").flatMap(URL.init(string:)) else { continue }
            // 미리 서명된 주소라 인증 머리를 붙이지 않는다.
            let (data, _) = try await URLSession.shared.data(from: link)
            guard let text = Self.gunzip(data).flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
            rows += Self.rows(text)
        }
        return rows
    }

    /// 탭으로 나뉜 표를 머리글 이름으로 읽는다.
    static func rows(_ text: String) -> [[String: String]] {
        var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst()
        return lines.map { Dictionary(zip(header, $0), uniquingKeysWith: { first, _ in first }) }
    }
}

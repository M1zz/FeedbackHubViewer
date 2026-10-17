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

/// 인스턴스의 단위. 대부분은 날마다 나오지만, 크래시처럼 달마다만 나오는 리포트가 있다.
enum AnalyticsGranularity: String {
    case daily = "DAILY"
    case monthly = "MONTHLY"

    /// 디스크 목록의 열쇠. 날 단위는 예전처럼 리포트 이름 그대로 둔다.
    func cacheKey(_ name: String) -> String {
        self == .daily ? name : "\(name)#\(rawValue)"
    }
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
    ///
    /// ONGOING 은 **만든 날부터만** 쌓는다. App Store Connect 웹의 분석 탭에는 지난 기록이
    /// 다 있는데 이 탭은 비어 있던 까닭이다. 그래서 지난 기록을 한 번 만들어 달라는
    /// 요청(ONE_TIME_SNAPSHOT)을 같이 낸다. 그것이 실패해도 ONGOING 은 선다.
    func createAnalyticsRequest(appID: String) async throws {
        try await createRequest(appID: appID, accessType: "ONGOING")
        try? await createAnalyticsSnapshot(appID: appID)
    }

    /// 지난 기록을 한 번 만들어 달라는 요청. 이미 있으면 다시 만들지 않는다.
    /// 1~2일 뒤에 파일이 생기고, 읽는 쪽(`analyticsRows`)이 ONGOING 의 것과 합친다.
    func createAnalyticsSnapshot(appID: String) async throws {
        if try await analyticsSnapshotID(appID: appID, refresh: true) != nil { return }
        try await createRequest(appID: appID, accessType: "ONE_TIME_SNAPSHOT")
        snapshotRequests[appID] = nil
    }

    private func createRequest(appID: String, accessType: String) async throws {
        _ = try await write("POST", "v1/analyticsReportRequests", body: [
            "data": [
                "type": "analyticsReportRequests",
                "attributes": ["accessType": accessType],
                "relationships": ["app": ["data": ["type": "apps", "id": appID]]]
            ]
        ])
    }

    /// 지난 기록 요청의 id. 없으면 nil. 한 번 찾으면 이번 실행 동안 다시 묻지 않는다.
    func analyticsSnapshotID(appID: String, refresh: Bool = false) async throws -> String? {
        if !refresh, let known = snapshotRequests[appID] { return known }
        let doc = try await list("v1/apps/\(appID)/analyticsReportRequests", [:])
        let id = doc.data.first { $0.string("accessType") == "ONE_TIME_SNAPSHOT" }?.id
        snapshotRequests[appID] = .some(id)
        return id
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
        try await analyticsRows(named: report.rawValue, requestID: requestID, appID: appID, days: days)
    }

    /// 이름으로 고른 리포트의 행. 달 단위 리포트는 행의 날짜가 그달 1일이라, 창을 한 달
    /// 더 넓혀야 지난달 파일이 잡힌다.
    func analyticsRows(named name: String, granularity: AnalyticsGranularity = .daily,
                       requestID: String?, appID: String, days: Int) async throws -> AnalyticsRows {
        let calendar = Calendar(identifier: .gregorian)
        let span = granularity == .monthly ? days + 31 : days
        let cutoff = Self.day.string(from: calendar.date(byAdding: .day, value: -(span + 3), to: Date()) ?? Date())
        let firstDay = Self.day.string(from: calendar.date(byAdding: .day, value: -span, to: Date()) ?? Date())
        let key = granularity.cacheKey(name)

        let recent: [AnalyticsCache.Instance]
        if let requestID {
            // 계속 쌓는 요청과, 있으면 지난 기록 요청. 같은 날짜가 둘에 다 있으면 아래에서
            // 늦게 가공된 파일 하나만 쓴다.
            var requests = [requestID]
            // 여기서는 "없음" 과 "묻다 실패" 를 가를 필요가 없다 — 둘 다 계속 쌓는 것만 읽는다.
            if let snapshot = try? await analyticsSnapshotID(appID: appID) { requests.append(snapshot) }
            var found: [AnalyticsCache.Instance] = []
            for request in requests {
                found += try await instances(request: request, name: name, granularity: granularity)
            }
            recent = Array(Set(found)).filter { $0.processingDate >= cutoff }.sorted { $0.processingDate < $1.processingDate }
            AnalyticsCache.remember(recent, appID: appID, key: key)
        } else {
            recent = AnalyticsCache.instances(appID: appID, key: key).filter { $0.processingDate >= cutoff }
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
                // 설치 경로 리포트(Platform App Installs)만 날짜 열 이름이 다르다.
                guard row["App Apple Identifier"] == nil || row["App Apple Identifier"] == appID,
                      let date = row["Date"] ?? row["Install Day"], date >= firstDay else { continue }
                rowsByDate[date, default: []].append(row)
            }
            for (date, rows) in rowsByDate where instance.processingDate > (processedFor[date] ?? "") {
                processedFor[date] = instance.processingDate
                result.byDate[date] = rows
            }
        }
        return result
    }

    /// 한 요청 안에서 이름으로 고른 리포트의 인스턴스.
    private func instances(request: String, name: String, granularity: AnalyticsGranularity) async throws -> [AnalyticsCache.Instance] {
        let reports = try await list("v1/analyticsReportRequests/\(request)/reports", ["filter[name]": name])
        guard let found = reports.data.first(where: { $0.string("name") == name }) ?? reports.data.first else { return [] }
        let instances = try await list("v1/analyticsReports/\(found.id)/instances", [
            "filter[granularity]": granularity.rawValue, "limit": "200"
        ])
        return instances.data.map { AnalyticsCache.Instance(id: $0.id, processingDate: $0.string("processingDate") ?? "") }
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

    /// `key` 는 `AnalyticsGranularity.cacheKey` — 리포트 이름(날 단위)이거나 이름#단위.
    static func instances(appID: String, key: String) -> [Instance] {
        CacheFile.read(Index.self, at: indexFile)?[appID]?[key] ?? []
    }

    /// 새 목록으로 바꾸고, 빠진 인스턴스의 파일을 지운다.
    static func remember(_ instances: [Instance], appID: String, key: String) {
        var index = CacheFile.read(Index.self, at: indexFile) ?? [:]
        let old = index[appID]?[key] ?? []
        guard old != instances else { return }
        index[appID, default: [:]][key] = instances
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

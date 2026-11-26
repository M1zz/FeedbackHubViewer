//
//  DeviceTests.swift
//  FeedbackHubViewer
//
//  연결한 아이폰에서 앱마다 돌린 테스트 결과 — 품질 탭의 "기기 테스트" 줄의 재료.
//
//  `workspace/Auto/docs/quality-tests.json` 을 읽는다. 이 파일은 `scripts/device-qa.sh` 가
//  앱을 하나씩 아이폰에 올려 단위 테스트 · UI 테스트 · 설치하고 켜 보기를 하고 쓴다.
//  맥이 레포 폴더 허락(`KeywordStore.repoFolder`)으로 읽어 캐시로 옮기고, 아이폰은 iCloud 로 받은 그 사본을 읽는다.
//

import Foundation

struct DeviceTestReport: Decodable {
    var generatedAt: Date?
    var device: String?
    var apps: [DeviceTestResult]

    static let relativePath = "docs/quality-tests.json"

    /// 번들 id(소문자) → 결과. 한 레포의 번들(위젯 등)이 모두 같은 결과를 가리킨다.
    static func load(_ data: Data?) -> [String: DeviceTestResult] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let report = try decoder.decode(DeviceTestReport.self, from: data)
            var result: [String: DeviceTestResult] = [:]
            for app in report.apps {
                for id in app.bundleIDs { result[id.lowercased()] = app }
            }
            return result
        } catch {
            print("❌ [DeviceTestReport.load] \(error)")
            return [:]
        }
    }
}

struct DeviceTestResult: Decodable, Equatable {
    struct Counts: Decodable, Equatable {
        var passed = 0
        var failed = 0
        var skipped = 0
    }

    var folder: String
    var bundleIDs: [String]
    var testedAt: Date?
    var version: String?
    /// 아이폰용으로 빌드했나. 못 했으면 나머지는 모른다.
    var built: Bool
    /// 설치하고 켠 뒤 몇 초 동안 살아 있었나. 못 봤으면 nil.
    var launched: Bool?
    var unit: Counts?
    var ui: Counts?
    /// 실패한 테스트 · 실행 실패 이유, 사람이 읽을 한 줄씩.
    var failures: [String] = []

    var failedCount: Int { (unit?.failed ?? 0) + (ui?.failed ?? 0) }
    var passedCount: Int { (unit?.passed ?? 0) + (ui?.passed ?? 0) }
}

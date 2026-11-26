//
//  TestCoverage.swift
//  FeedbackHubViewer
//
//  앱마다 테스트 커버리지 — 품질 탭의 "커버리지" 줄의 재료.
//
//  `workspace/Auto/docs/test-coverage.json` 을 읽는다. 이 파일은 `scripts/test-coverage.py` 가
//  테스트를 새로 돌리지 않고 DerivedData 에 남은 가장 새 .xcresult 의 줄 커버리지를 읽어 쓴다.
//  xcresult 가 없는 앱은 테스트 함수 수만 센 정적 측정이다 — 커버리지가 아니라서 그렇게 적는다.
//  맥이 레포 폴더 허락(`KeywordStore.repoFolder`)으로 읽어 캐시로 옮기고, 아이폰은 iCloud 로 받은 그 사본을 읽는다.
//

import Foundation

struct TestCoverageReport: Decodable {
    var generatedAt: Date?
    var apps: [TestCoverage]

    static let relativePath = "docs/test-coverage.json"

    /// 번들 id(소문자) → 결과. 한 레포의 번들(위젯 등)이 모두 같은 결과를 가리킨다.
    static func load(_ data: Data?) -> [String: TestCoverage] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let report = try decoder.decode(TestCoverageReport.self, from: data)
            var result: [String: TestCoverage] = [:]
            for app in report.apps {
                for id in app.bundleIDs { result[id.lowercased()] = app }
            }
            return result
        } catch {
            print("❌ [TestCoverageReport.load] \(error)")
            return [:]
        }
    }
}

struct TestCoverage: Decodable, Equatable {
    var folder: String
    var bundleIDs: [String]
    /// 정적 측정 — 늘 있다.
    var testFunctions: Int
    var sourceFiles: Int
    /// xcresult 에서 읽은 앱 · 확장의 줄 수. 테스트를 커버리지 켜고 돌린 적이 없으면 nil.
    var coveredLines: Int?
    var executableLines: Int?
    var measuredAt: Date?

    var lineCoverage: Double? {
        guard let coveredLines, let executableLines, executableLines > 0 else { return nil }
        return Double(coveredLines) / Double(executableLines)
    }
}

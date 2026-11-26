//
//  KeywordStore+Quality.swift
//  FeedbackHubViewer
//
//  품질 탭이 스토어 · 레포에서 읽는 것 두 가지.
//
//  1. 별점 — 모든 나라 가게의 합. `itunes.apple.com/lookup` 은 가게 하나의 별점만 준다. 키워드가
//     읽어 둔 앱 정보는 한국 가게 것이라, 미국 · 중국에서 별점을 받은 앱도 "별점 0개" 였다.
//     나라마다 한 번씩(앱 전부를 한 요청에) 물어 개수는 더하고 평균은 개수로 가중한다. 하루 한 번,
//     받은 것은 기기 사이에서 나눈다(`AppStoreConnectStore.syncedCacheFiles`) — 한 기기만 묻는다.
//  2. 기기 테스트 · 커버리지 — 맥이 레포 폴더의 `docs/*.json` 을 캐시로 옮기면 같은 길로 아이폰에 간다.
//     아이폰은 레포를 못 읽는다.
//

import Foundation

/// 나라 가게마다 받은 별점. 나라 → App Store id → 그 가게의 평균 · 개수.
struct StoreRatings: Codable, Equatable {
    struct Rating: Codable, Equatable {
        var average: Double
        var count: Int
    }

    var fetchedAt: Date
    var byCountry: [String: [String: Rating]] = [:]

    /// 모든 가게를 합친 것. 개수가 하나도 없으면 nil.
    func world(trackId: Int) -> (average: Double, count: Int, countries: Int)? {
        let ratings = byCountry.values.compactMap { $0[String(trackId)] }.filter { $0.count > 0 }
        let count = ratings.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }
        let sum = ratings.reduce(0.0) { $0 + $1.average * Double($1.count) }
        return (sum / Double(count), count, ratings.count)
    }
}

extension KeywordStore {

    nonisolated static let storeRatingsFile = "store-ratings"
    /// 레포 폴더의 시험 결과를 옮겨 둔 캐시 — 이름은 레포 파일과 같다.
    nonisolated static let deviceTestsFile = "quality-tests"
    nonisolated static let testCoverageFile = "test-coverage"

    /// 별점은 하루에 크게 움직이지 않는다.
    private static let ratingsFreshness: TimeInterval = 24 * 3600

    func worldRating(for project: String) -> (average: Double, count: Int, countries: Int)? {
        guard let trackId = trackId(for: project) else { return nil }
        return storeRatings?.world(trackId: trackId)
    }

    /// 디스크(또는 다른 기기가 iCloud 로 보낸 것)에서 — 켤 때와 캐시를 받았을 때.
    func restoreQualityCaches() {
        storeRatings = CacheFile.read(StoreRatings.self, at: CacheFile.url(Self.storeRatingsFile))
        let tests = DeviceTestReport.load(CacheFile.url(Self.deviceTestsFile).flatMap { try? Data(contentsOf: $0) })
        let coverage = TestCoverageReport.load(CacheFile.url(Self.testCoverageFile).flatMap { try? Data(contentsOf: $0) })
        if deviceTests != tests { deviceTests = tests }
        if testCoverage != coverage { testCoverage = coverage }
    }

    /// 나라마다 한 번씩 묻는다. 어느 기기든 하루 안에 받았으면 묻지 않는다. 못 받은 나라는 지난 값을 둔다.
    func refreshStoreRatings() async {
        if let fetched = storeRatings?.fetchedAt, Date().timeIntervalSince(fetched) < Self.ratingsFreshness { return }
        let ids = Array(Set(history.links.values)).sorted()
        guard !ids.isEmpty else { return }
        var ratings = storeRatings ?? StoreRatings(fetchedAt: Date())
        var answered = 0
        for country in ChartStorefronts.all {
            guard let apps = try? await directory.lookup(ids: ids, country: country) else { continue }
            answered += 1
            ratings.byCountry[country] = Dictionary(
                apps.compactMap { app in app.averageRating.map { (String(app.id), StoreRatings.Rating(average: $0, count: app.ratingCount)) } },
                uniquingKeysWith: { first, _ in first })
        }
        guard answered > 0 else { return }
        ratings.fetchedAt = Date()
        storeRatings = ratings
        CacheFile.write(ratings, to: CacheFile.url(Self.storeRatingsFile))
    }
}

extension CacheFile {

    /// 바이트 그대로 — 다를 때만 쓴다(같은 내용을 다시 써서 iCloud 에 또 올리지 않게).
    static func mirror(_ data: Data, named name: String) {
        guard let url = url(name), (try? Data(contentsOf: url)) != data,
              (try? data.write(to: url, options: .atomic)) != nil else { return }
        NotificationCenter.default.post(name: didWrite, object: name)
    }
}

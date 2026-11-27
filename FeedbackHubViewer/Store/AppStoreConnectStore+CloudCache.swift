//
//  AppStoreConnectStore+CloudCache.swift
//  FeedbackHubViewer
//
//  App Store Connect 에서 받은 것을 기기 사이에서 나눠 쓴다.
//
//  예전에는 켤 때마다 화면이 처음 볼 때 한 번씩 상품 · 스토어 문구 · 버전 · 분석 요청 현황을
//  새로 물었고, 맥이 여러 대면 같은 것을 기기마다 다시 받았다. 이제는
//
//   1. 켜면 iCloud 에 있는 캐시 묶음(`CacheFileBundle`)부터 받아 디스크에 들인다.
//   2. 화면이 무엇을 받으려 하면, 어느 기기든 `connectFreshness` 안에 받은 것이 있으면
//      묻지 않는다(`shouldFetch`). 새로고침 단추(force)는 늘 받는다.
//   3. 이 기기가 새로 받아 디스크에 쓰면 잠깐 뒤 iCloud 에 올린다.
//

import Foundation

extension AppStoreConnectStore {

    /// 기기 사이에 나누는 파일. 분석 리포트 원본(`analytics-index` · 조각 파일)은 크고 이 기기가
    /// 다시 접을 때만 쓰므로 빼고, 접은 결과(`analytics-results`)를 나눈다. 확인한 리뷰는
    /// 따로 합집합으로 나눈다(`viewedReviewsCloud`).
    nonisolated static let syncedCacheFiles = [
        "connect-fetched-at", "connect-apps-v2", "store-catalogs-v2", "store-metadata",
        "sales-days", "subscription-event-days", "exchange-rates",
        "store-reviews", "store-reviews-alerted", "store-review-priority", "store-versions", "store-stability",
        "analytics-results", "analytics-coverage", "analytics-scans", "referral-ledger",
        // 품질 탭 — 별점 합계와, 맥만 읽을 수 있는 레포의 시험 결과(`KeywordStore+Quality.swift`).
        KeywordStore.storeRatingsFile, KeywordStore.deviceTestsFile, KeywordStore.testCoverageFile,
    ]

    /// 받은 지 이만큼 안 됐으면 어느 기기가 받았든 다시 묻지 않는다. 리포트 · 상품 · 문구는
    /// 하루에 몇 번 바뀌지 않는다. 지금 것이 필요하면 새로고침 단추.
    static let connectFreshness: TimeInterval = 6 * 3600

    func startCacheSync() {
        cacheWriteObserver = NotificationCenter.default.addObserver(forName: CacheFile.didWrite, object: nil,
                                                                    queue: .main) { [weak self] note in
            guard let name = note.object as? String, Self.syncedCacheFiles.contains(name) else { return }
            MainActor.assumeIsolated { self?.cacheCloud.schedulePush() }
        }
        guard isConfigured else { return }
        initialCloudPull = Task { await cacheCloud.pull() }
    }

    /// 앞으로 올 때마다 — 그 사이 다른 기기가 받은 것.
    func pullCachesFromCloud() {
        guard isConfigured else { return }
        Task { await cacheCloud.pull(minimumInterval: 60) }
    }

    /// 네트워크로 새로 받을까. 손으로 누른 새로고침이면 받는다. 아니면 iCloud 것을 먼저 들이고,
    /// 이번 실행에 이미 받았거나 어느 기기든 `connectFreshness` 안에 받아 둔 값이 있으면 받지 않는다.
    func shouldFetch(_ key: String, force: Bool, has: @autoclosure () -> Bool) async -> Bool {
        if force {
            refreshed.insert(key)
            return true
        }
        guard !refreshed.contains(key) else { return false }
        refreshed.insert(key)
        await initialCloudPull?.value
        if has(), let at = fetchedAt[key], Date().timeIntervalSince(at) < Self.connectFreshness { return false }
        return true
    }

    /// iCloud 에서 받은 묶음을 디스크에 쓰고 화면에 들인다. 다른 것이 없으면 아무것도 안 한다.
    func adoptSyncedCaches(_ merged: CacheFileBundle) {
        guard isConfigured, merged.write(over: CacheFileBundle.read(Self.syncedCacheFiles)) else { return }
        rates = CacheFile.read(ExchangeRates.self, at: Self.ratesFile) ?? rates
        restoreReferralLedger()
        restoreReviews()
        restoreStability()
        restoreStoreCaches()
        if let coverage = CacheFile.read(AnalyticsCoverage.self, at: Self.coverageFile) {
            analyticsCoverage = .loaded(coverage)
        }
        redrawReportsFromCache()
        NotificationCenter.default.post(name: CacheFileBundle.didAdopt, object: nil)
    }
}

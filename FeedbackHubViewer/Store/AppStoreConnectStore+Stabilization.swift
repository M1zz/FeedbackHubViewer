//
//  AppStoreConnectStore+Stabilization.swift
//  FeedbackHubViewer
//
//  안정화 지표 중 App Store Connect 에서 오는 것 — 제출된 버전 기록과 버전별 성능.
//  디스크에 두고, 하루에 몇 번 움직이지 않는 값이라 12시간에 한 번만 다시 받는다.
//

import Foundation

extension AppStoreConnectStore {

    static let stabilityFreshness: TimeInterval = 12 * 3600

    private static var stabilityFile: URL? { CacheFile.url("store-stability") }

    func restoreStability() {
        stabilitySources = CacheFile.read([String: Stabilization.Source].self, at: Self.stabilityFile) ?? [:]
    }

    func forgetStability() {
        stabilitySources = [:]
        stabilityErrors = [:]
        CacheFile.remove(Self.stabilityFile)
    }

    func loadStability(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        if !force, let fetched = stabilitySources[bundleID]?.fetchedAt,
           Date().timeIntervalSince(fetched) < Self.stabilityFreshness { return }
        do {
            let app = try await resolveApp(bundleID)
            let releases = try await client.releases(appID: app.id)
            // 성능은 덤이다. 못 받아도 버전 기록으로 잴 수 있는 것은 잰다.
            let performance = (try? await client.performanceMetrics(appID: app.id))
                ?? stabilitySources[bundleID]?.performance ?? []
            stabilitySources[bundleID] = Stabilization.Source(releases: releases, performance: performance,
                                                              fetchedAt: Date())
            stabilityErrors[bundleID] = nil
            CacheFile.write(stabilitySources, to: Self.stabilityFile)
        } catch {
            stabilityErrors[bundleID] = error.localizedDescription
        }
    }

    /// 여러 앱을 차례로(한꺼번에 쏘면 시간당 한도를 쓴다).
    func loadStability(bundleIDs: [String], force: Bool = false) async {
        guard isConfigured else { return }
        for key in bundleIDs where key != Feedback.unclassifiedProject {
            await loadStability(bundleID: key, force: force)
        }
    }
}

extension AppStoreConnect {

    /// 이미 심사를 통과해 나간 적 있는 상태들. 거절 · 작성 중인 버전은 릴리즈가 아니다.
    private static let releasedStates: Set<String> = [
        "READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "PROCESSING_FOR_APP_STORE",
        "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE",
        "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"
    ]

    /// 나간 버전 전부. 플랫폼마다 번호를 따로 매길 수 있어 릴리즈가 가장 많은 플랫폼만 쓴다.
    func releases(appID: String) async throws -> [Stabilization.Release] {
        let (data, status) = try await send(url("v1/apps/\(appID)/appStoreVersions", [
            "fields[appStoreVersions]": "versionString,appStoreState,createdDate,platform",
            "limit": "200"
        ]))
        try check(data, status)
        guard let page = try? JSONDecoder().decode(ASCDocument.self, from: data) else { throw Failure.decoding }
        let released = page.data.filter { Self.releasedStates.contains($0.string("appStoreState") ?? "") }
        let byPlatform = Dictionary(grouping: released) { $0.string("platform") ?? "" }
        let main = byPlatform.values.max { $0.count < $1.count } ?? []
        return main.compactMap { item in
            guard let version = item.string("versionString"),
                  let created = Self.parseDate(item.string("createdDate")) else { return nil }
            return Stabilization.Release(version: version, submittedAt: created)
        }
    }

    /// Xcode Organizer 의 Metrics 탭과 같은 값. 사용자가 적은 앱은 비어 있다.
    func performanceMetrics(appID: String) async throws -> [Stabilization.PerformanceMetric] {
        let (data, status) = try await send(url("v1/apps/\(appID)/perfPowerMetrics", [
            "filter[metricType]": "HANG,LAUNCH,DISK"
        ]), accept: "application/vnd.apple.xcode-metrics+json")
        try check(data, status)
        return Stabilization.parsePerformance(data)
    }
}

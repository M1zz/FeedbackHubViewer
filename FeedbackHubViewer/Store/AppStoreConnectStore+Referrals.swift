//
//  AppStoreConnectStore+Referrals.swift
//  FeedbackHubViewer
//
//  링크 감지의 상태 — 앱마다 받은 리포트와, 출처를 처음 본 날의 기록.
//
//  기록(`referralLedger`)은 디스크에 남는다. 리포트 창은 30일이라 창만 보면 두 달 전에
//  링크했던 곳이 다시 나타나도 "새로"가 된다(`ReferralDetection`). 기록은 계정에 딸린
//  것이라 키를 바꾸거나 지우면 함께 지운다.
//

import Foundation

extension AppStoreConnectStore {

    /// 리포트 요청이 없으면 링크 감지도 없다 — 퍼널과 같은 요청을 쓴다.
    enum ReferralResult {
        case noRequest
        case ready(ReferralDetection, ReferralReport)
    }

    private static var ledgerFile: URL? { CacheFile.url("referral-ledger") }

    /// 번들 ID → (출처 id → 처음 본 날).
    typealias ReferralLedger = [String: [String: String]]

    func restoreReferralLedger() {
        referralLedger = CacheFile.read(ReferralLedger.self, at: Self.ledgerFile) ?? [:]
    }

    func forgetReferrals() {
        referrals = [:]
        referralLedger = [:]
        CacheFile.remove(Self.ledgerFile)
    }

    func loadReferrals(bundleID: String, force: Bool = false) async {
        guard let client else { return }
        if !force, let state = referrals[bundleID], !(state.value == nil && !state.isLoading) { return }
        referrals[bundleID] = .loading
        do {
            let app = try await resolveApp(bundleID)
            guard let request = try await client.analyticsRequestID(appID: app.id) else {
                referrals[bundleID] = .loaded(.noRequest)
                return
            }
            let report = try await client.referrals(requestID: request, appID: app.id, days: Self.salesDays)
            let detection = ReferralDetection(report: report, ledger: referralLedger[bundleID] ?? [:])
            if detection.ledger != referralLedger[bundleID] {
                referralLedger[bundleID] = detection.ledger
                CacheFile.write(referralLedger, to: Self.ledgerFile)
            }
            referrals[bundleID] = .loaded(.ready(detection, report))
        } catch {
            referrals[bundleID] = .failed(error.localizedDescription)
        }
    }
}

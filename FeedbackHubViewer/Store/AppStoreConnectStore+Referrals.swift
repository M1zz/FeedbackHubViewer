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

    /// 디스크에 둔 상세 리포트로 먼저 그리고, 새 파일이 있으면 받아 다시 가린다.
    /// 처음 본 날의 기록은 새로 받은 것으로만 고친다.
    func loadReferrals(bundleID: String, force: Bool = false) async {
        await loadAnalytics("referrals", bundleID: bundleID, force: force, into: \.referrals,
                            noRequest: .noRequest) { client, requestID, appID in
            let report = try await client.referrals(requestID: requestID, appID: appID, days: Self.salesDays)
            if requestID == nil && report.instances == 0 { return nil }
            let detection = ReferralDetection(report: report, ledger: referralLedger[bundleID] ?? [:])
            if requestID != nil, detection.ledger != referralLedger[bundleID] {
                referralLedger[bundleID] = detection.ledger
                CacheFile.write(referralLedger, to: Self.ledgerFile)
            }
            return .ready(detection, report)
        }
    }
}

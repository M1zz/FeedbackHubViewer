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

    /// 퍼지는 곳을 처음 봤으면 바로 알린다 — 같은 곳 · 같은 상태는 한 번만(기기마다).
    /// 아침 브리핑에도 오르지만, 행사 다음 날 어디로 퍼졌는지는 그때 알아야 그곳에 답을 단다.
    private func notifySpreading(_ detection: ReferralDetection, bundleID: String) {
        let key = "referral-notified"
        let defaults = UserDefaults.standard
        // 이 기능이 처음 돈 날 — 그 전에 이미 있던 것은 알리지 않는다(앱마다 알림이 한꺼번에 쏟아지지 않게).
        let sinceKey = "referral-notified-since"
        let today = AppStoreConnect.day.string(from: Date())
        let since = defaults.string(forKey: sinceKey) ?? today
        if defaults.string(forKey: sinceKey) == nil { defaults.set(today, forKey: sinceKey) }
        var seen = Set(defaults.stringArray(forKey: key) ?? [])
        let fresh = detection.spreading.filter { item in
            let happened = item.status == .new ? item.firstSeen : (item.tally.lastDate ?? item.firstSeen)
            return happened >= since && !seen.contains("\(bundleID)|\(item.source.id)|\(item.status.label)|\(item.firstSeen)")
        }
        guard !fresh.isEmpty else { return }
        for item in fresh { seen.insert("\(bundleID)|\(item.source.id)|\(item.status.label)|\(item.firstSeen)") }
        defaults.set(Array(seen).suffix(1000), forKey: key)
        // 허브의 알림 스위치(`FeedbackStore.notificationsEnabled`)를 따른다.
        guard defaults.bool(forKey: "notificationsEnabled") else { return }
        let name = connectApp(for: bundleID)?.name ?? bundleID
        NotificationService.notifyReferrals(app: name, items: fresh.map { ($0.profile.name, $0.status == .new, $0.recent) })
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
            if requestID != nil { notifySpreading(detection, bundleID: bundleID) }
            return .ready(detection, report)
        }
        saveAnalyticsResults()
    }
}

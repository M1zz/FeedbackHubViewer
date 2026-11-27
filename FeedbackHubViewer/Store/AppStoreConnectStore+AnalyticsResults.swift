//
//  AppStoreConnectStore+AnalyticsResults.swift
//  FeedbackHubViewer
//
//  유입 화면이 쓰는 결과(노출 · 전환 퍼널, 링크 감지)를 접은 채로 디스크에 둔다.
//
//  원본 리포트 파일은 이미 디스크에 있지만(`AnalyticsCache`), 그것을 다시 읽어 접으려면
//  앱마다 수십 개 파일을 풀어야 해서 켤 때마다 화면이 늦게 찼다. 접은 결과를 두면 앱을
//  켜자마자 지난번 숫자로 그리고, 받은 지 `analyticsFreshness` 가 안 됐으면 다시 묻지도 않는다.
//
//  링크 감지의 "새로 · 급증" 은 오늘 날짜에 따라 바뀌므로 판정은 저장하지 않고,
//  리포트만 두었다가 꺼낼 때 기록(`referralLedger`)과 다시 견준다.
//

import Foundation

extension AppStoreConnectStore {

    /// 분석 리포트는 하루 한 번 나온다. 이보다 새로 받은 것이면 네트워크로 다시 묻지 않는다.
    static let analyticsFreshness: TimeInterval = 6 * 3600

    private static var resultsFile: URL? { CacheFile.url("analytics-results") }

    private struct StoredResults: Codable {
        var funnels: [String: StoreFunnel] = [:]
        var referrals: [String: ReferralReport] = [:]
        /// 리포트 요청이 없던 앱("funnel:번들 ID" · "referrals:번들 ID").
        var noRequest: Set<String> = []
    }

    func restoreAnalyticsResults() {
        guard let stored = CacheFile.read(StoredResults.self, at: Self.resultsFile) else { return }
        for (bundleID, funnel) in stored.funnels {
            funnels[bundleID] = .loaded(.ready(funnel))
        }
        for (bundleID, report) in stored.referrals {
            let detection = ReferralDetection(report: report, ledger: referralLedger[bundleID] ?? [:])
            referrals[bundleID] = .loaded(.ready(detection, report))
        }
        for key in stored.noRequest {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "funnel": funnels[parts[1]] = .loaded(.noRequest)
            case "referrals": referrals[parts[1]] = .loaded(.noRequest)
            default: break
            }
        }
    }

    /// 지금 손에 든 결과를 통째로 쓴다. 받다 실패해도 화면은 지난 값을 그대로 두므로 그것이 다시 남는다.
    func saveAnalyticsResults() {
        var stored = StoredResults()
        for (bundleID, state) in funnels {
            switch state.value {
            case .ready(let funnel): stored.funnels[bundleID] = funnel
            case .noRequest: stored.noRequest.insert("funnel:\(bundleID)")
            case nil: break
            }
        }
        for (bundleID, state) in referrals {
            switch state.value {
            case .ready(_, let report): stored.referrals[bundleID] = report
            case .noRequest: stored.noRequest.insert("referrals:\(bundleID)")
            case nil: break
            }
        }
        CacheFile.write(stored, to: Self.resultsFile)
    }

    func forgetAnalyticsResults() {
        CacheFile.remove(Self.resultsFile)
    }
}

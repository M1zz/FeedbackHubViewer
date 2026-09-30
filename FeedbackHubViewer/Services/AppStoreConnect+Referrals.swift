//
//  AppStoreConnect+Referrals.swift
//  FeedbackHubViewer
//
//  링크 감지에 쓰는 요청 — 두 상세 리포트를 받아 출처별로 모은다.
//  리포트를 받는 일은 공통 층이, 행을 출처로 읽는 일은 `ReferralReport` 가 한다.
//

import Foundation

extension AppStoreConnect {

    /// 최근 `days`일 출처별 셈. 상세 리포트는 퍼널이 쓰는 Standard 와 같은 요청 안에 있어서
    /// 따로 요청을 만들 필요가 없다.
    func referrals(requestID: String, appID: String, days: Int) async throws -> ReferralReport {
        let downloads = try await analyticsRows(.downloadsDetailed, requestID: requestID, appID: appID, days: days)
        let engagement = try await analyticsRows(.engagementDetailed, requestID: requestID, appID: appID, days: days)
        return ReferralReport(days: days, downloads: downloads, engagement: engagement)
    }
}

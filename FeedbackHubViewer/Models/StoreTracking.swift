//
//  StoreTracking.swift
//  FeedbackHubViewer
//
//  App Store 에 나가 있지 않은 앱은 추적하지 않는다 — 삭제한(판매 중지한) 앱과 아직 배포하지 않은 앱.
//  허브의 목록 · 홈 · 뱃지 · 알림에서 빠지는 것은 "숨긴 앱" 과 같다. 기록은 지우지 않는다.
//
//  무엇으로 아나 (보인 증거만 — 모르면 추적한다):
//   · App Store Connect 의 가장 새 버전이 판매 중지(DEVELOPER_REMOVED_FROM_SALE · REMOVED_FROM_SALE) → 내린 앱.
//   · App Store 조회(번들 ID)가 그 앱을 돌려주지 않음(`KeywordStore.storeAbsent`) → 배포 전이거나 삭제됨.
//     단, App Store Connect 가 "판매 중" 이라 하면 조회 쪽이 틀린 것으로 보고 추적한다(한 나라에서만 파는 앱).
//
//  잘못 빠진 앱은 "다시 추적" 으로 되돌린다(`FeedbackStore.trackAnyway`). 스토어에 다시 나타나면 저절로 돌아온다.
//

import Foundation

enum StoreTracking {

    static let removedStates: Set<String> = ["DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE"]
    static let liveStates: Set<String> = ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION"]

    /// 추적하지 않을 앱 → 까닭.
    static func untracked(absent: Set<String>, versions: [String: AppVersionStatus],
                          forced: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for (project, status) in versions where removedStates.contains(status.state) {
            result[project] = "App Store 에서 내림"
        }
        for project in absent where result[project] == nil && project != Feedback.unclassifiedProject {
            if let status = versions[project] {
                if liveStates.contains(status.state) { continue }
                result[project] = "아직 App Store 에 안 나감 · \(status.version) \(status.stateLabel)"
            } else {
                result[project] = "App Store 에 없음 · 배포 전이거나 삭제됨"
            }
        }
        for project in forced { result.removeValue(forKey: project) }
        return result
    }
}

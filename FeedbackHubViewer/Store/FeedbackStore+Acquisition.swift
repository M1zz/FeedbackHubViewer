//
//  FeedbackStore+Acquisition.swift
//  FeedbackHubViewer
//
//  유입 판정에 넣을 앱 구역 숫자. 새로 세지 않고 통계 화면이 이미 만드는 것을 꺼낸다 —
//  사다리는 usage-spec 대시보드의 같은 카드이고, 페이월은 같은 이벤트 집계다.
//

import Foundation

extension FeedbackStore {

    /// 지도가 가리키는 사다리(또는 퍼널)의 마지막 칸까지 몇이 오나.
    func acquisitionLadder(for project: String, map: AcquisitionMap) -> AcquisitionDiagnosis.Ladder? {
        guard let title = map.appZone?.activation else { return nil }
        for section in dashboard(for: project, audience: .all) {
            for insight in section.insights {
                guard case .funnel(let frame, let steps, let goal) = insight, frame.title == title,
                      let first = steps.first, let last = steps.last, !last.isMissing
                else { continue }
                let worst = steps.dropFirst()
                    .filter { !$0.isMissing && $0.fromPrevious != nil }
                    .min { ($0.fromPrevious ?? 1) < ($1.fromPrevious ?? 1) }
                // 하한과 견줄 값은 순서 무관(앱이 선을 그렇게 정의했다).
                return .init(label: title, reached: goal?.reached ?? last.ratio,
                             worstStep: worst?.label, worstPass: worst?.fromPrevious,
                             base: first.count)
            }
        }
        return nil
    }

    /// 페이월을 본 설치 수와 전체 설치 수.
    func acquisitionPaywall(for project: String, map: AcquisitionMap) -> AcquisitionDiagnosis.Paywall? {
        guard let event = map.appZone?.paywallEvent else { return nil }
        let context = dashboardContext(for: project, audience: .all)
        guard context.installCount > 0 else { return nil }
        var installs: Set<String> = []
        for (name, total) in context.events where ProjectStatsSpec.eventBase(name) == event {
            installs.formUnion(total.installs)
        }
        return .init(installs: installs.count, total: context.installCount)
    }
}

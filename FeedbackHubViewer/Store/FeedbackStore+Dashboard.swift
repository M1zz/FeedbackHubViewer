//
//  FeedbackStore+Dashboard.swift
//  FeedbackHubViewer
//
//  스펙이 카드를 만드는 데 필요한 입력을 한 자루에 담아 넘기는 곳.
//
//  여기 있는 것은 **자루를 싸는 일뿐**이다. 무엇을 셀지도, 어떻게 그릴지도 스펙과
//  평가가 정한다(`ProjectStatsSpec+Dashboard.swift`). 그래서 카드 종류가 늘어도
//  이 파일은 안 바뀐다 — 자루에 이미 든 것으로 만들 수 있는 한.
//
//  한때는 그렇지 않았다. 수익 카드가 권한(열림/안 열림)을 필요로 했는데 그 값은
//  스토어에만 있어서, 카드 계산이 통째로 스토어 안으로 들어왔고 스펙은 그 카드를
//  모르는 채로 남았다. 카드 한 장 늘리는 데 파일 넷을 고쳐야 했던 이유가 그것이다.
//  이제 권한도 자루에 담아 보낸다.
//

import Foundation

extension FeedbackStore {

    /// 이 범위·이 무리의 대시보드 입력.
    ///
    /// `unlocked`는 `installs`와 **같은 순서·같은 길이**다. 한도 카드가 설치마다
    /// "이미 열렸나"를 봐야 하는데, 지표 묶음만 넘기면 그 짝을 잃는다.
    func dashboardContext(for project: String?, audience: Audience) -> ProjectStatsSpec.Context {
        let snaps = snapshots(for: project, audience: audience)
        let access = project.flatMap { self.entitlement(for: $0) }
        // `access?.isUnlocked(_:)` 는 Bool?? 라 한 겹 벗겨야 한다.
        // 두 겹의 nil 은 뜻이 같다: 권한을 못 읽는 설치.
        var unlocked: [Bool?] = []
        for snapshot in snaps {
            unlocked.append(access.flatMap { $0.isUnlocked(snapshot) })
        }
        return ProjectStatsSpec.Context(
            installs: snaps.map(\.metrics),
            events: eventTallies(for: project, audience: audience),
            eventCountsAvailable: usage(for: project, audience: audience).hasEventCounts,
            unlocked: unlocked)
    }

    /// 이 앱의 대시보드 — 스펙이 정한 차례대로, 스펙이 정한 묶음으로.
    /// 스펙이 없는 앱에서는 빈 배열이고, 화면은 그 사실을 따로 말한다.
    func dashboard(for project: String?, audience: Audience) -> [ProjectStatsSpec.Section] {
        guard let project, let spec = ProjectStatsSpecCatalog.spec(for: project) else { return [] }
        return spec.dashboard(in: dashboardContext(for: project, audience: audience))
    }
}

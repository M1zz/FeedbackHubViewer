//
//  FeedbackStore+Release.swift
//  FeedbackHubViewer
//
//  릴리즈 건강을 이미 읽어 둔 레코드로 잰다. 새 CloudKit 질의는 없다.
//
//   - 사용 이벤트: 이 기기가 들고 있는 원본(`events(for:)`, 최근 90일 · 최대 5,000건).
//     버전별 설치 집합은 원본에만 있다. 일 버킷(`rollups`)은 버전을 모른다.
//   - 진단 · 피드백: 읽어 둔 전부.
//   - "한 번이라도 온 이벤트": 전 기간 집계(`eventTallies`). 불안정 이벤트를 믿을지 가른다.
//
//  계산 자체는 `ReleaseHealth.measure` (순수 함수)가 한다. 여기는 레코드를 넘기기만 한다.
//

import Foundation

extension FeedbackStore {

    /// 한 앱의 릴리즈 건강. 창 안에 버전을 가를 사용 이벤트가 없으면 nil.
    func releaseHealth(for project: String) -> ReleaseHealth.Report? {
        memoized(\.releaseHealth, project) {
            let everSeen = Set(eventTallies(for: project).keys.map {
                String($0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
            })
            return ReleaseHealth.measure(events: events(for: project),
                                         crashes: crashes(for: project),
                                         feedback: feedback(for: project),
                                         spec: ProjectStatsSpecCatalog.spec(for: project)?.release,
                                         everSeenEvents: everSeen,
                                         coverageStart: rawEventCoverageStart)
        }
    }

    /// 원본 이벤트 보관 상한에 걸렸을 때, 남아 있는 가장 오래된 시각. 상한은 앱별이
    /// 아니라 허브 전체에 걸리므로, 이 시각 앞의 이벤트는 **어느 앱이든** 이 기기에 없다.
    /// 상한에 안 걸렸으면 nil (보관 기간 90일은 창 14일보다 길다).
    var rawEventCoverageStart: Date? {
        guard fetchedEvents.count >= Self.eventLimit else { return nil }
        return fetchedEvents.map(\.occurredAt).min()
    }

    /// 목록 점의 색. 잴 수 없으면 nil 이라 점이 안 뜬다(초록으로 칠하지 않는다).
    func releaseLevel(for project: String) -> ReleaseHealth.Level? {
        guard project != Feedback.unclassifiedProject else { return nil }
        return releaseHealth(for: project)?.verdict.level
    }

    /// "빨강 먼저"를 켰을 때의 차례. 빨강 · 노랑 · 나머지 순이고, 같은 무리 안에서는
    /// 받은 차례(어제 DAU 순)를 그대로 둔다.
    func redFirst<Item>(_ items: [Item], key: (Item) -> String) -> [Item] {
        func rank(_ item: Item) -> Int {
            switch releaseLevel(for: key(item)) {
            case .red: return 0
            case .yellow: return 1
            default: return 2
            }
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element), r = rank(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }
}

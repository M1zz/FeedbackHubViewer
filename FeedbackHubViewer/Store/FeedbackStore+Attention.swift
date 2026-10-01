//
//  FeedbackStore+Attention.swift
//  FeedbackHubViewer
//
//  "새로 온 것" — 안 읽은 피드백, 아직 안 본 진단, 아직 안 본 스토어 리뷰. 진단 · 리뷰
//  탭의 뱃지, 툴바의 종, 앱 아이콘 뱃지가 모두 이 수를 읽는다.
//
//  피드백은 한 건씩 열어 읽음이 되지만(`markRead`), 진단과 리뷰는 그 탭을 열면
//  확인한 것으로 친다 — 한 건씩 여는 화면이 아니라 목록으로 훑는 화면이라서다.
//

import Foundation

extension FeedbackStore {

    /// 아직 안 본 진단 수. 한 앱(nil 이면 전체).
    func newCrashCount(for project: String?) -> Int {
        guard let viewed = viewedCrashIDs else { return 0 }
        return crashes(for: project).reduce(0) { $0 + (viewed.contains($1.id) ? 0 : 1) }
    }

    /// 진단 탭을 열었을 때 — 그 앱(nil 이면 전체)의 진단을 확인한 것으로.
    func markCrashesViewed(project: String?) {
        let ids = Set(crashes(for: project).map(\.id))
        guard let viewed = viewedCrashIDs, !ids.isSubset(of: viewed) else { return }
        viewedCrashIDs = viewed.union(ids)
        persistViewedCrashes()
        refreshBadge()
    }

    /// 앱 아이콘과 종이 보이는 수.
    var attentionCount: Int {
        unreadCount + newCrashCount(for: nil) + newStoreReviewCount
    }

    /// 이 기기에서 처음 진단을 받았을 때, 이미 있던 것은 새것으로 치지 않는다.
    func seedViewedCrashes() {
        guard viewedCrashIDs == nil, !allCrashes.isEmpty else { return }
        viewedCrashIDs = Set(allCrashes.map(\.id))
        persistViewedCrashes()
    }
}

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
//  무엇을 뱃지로 셀지는 설정(`badgeKinds`)이 정한다. 기본은 리뷰 · 피드백 — 진단은
//  진단 탭 안에서 보면 되고, 뱃지에 섞이면 사람이 쓴 것(리뷰 · 피드백)이 묻힌다.
//

import Foundation

/// 뱃지 · 알림으로 알리는 것. 순서가 곧 우선순위 — 종 목록과 탭에서 이 순서로 선다.
enum AttentionKind: String, CaseIterable, Identifiable {
    case review, feedback, crash

    var id: String { rawValue }

    var name: String {
        switch self {
        case .review: "리뷰"
        case .feedback: "피드백"
        case .crash: "진단"
        }
    }

    var systemImage: String {
        switch self {
        case .review: "star.bubble.fill"
        case .feedback: "envelope.badge.fill"
        case .crash: "exclamationmark.triangle.fill"
        }
    }

    /// 처음 켠 기기의 기본값.
    static let defaultBadgeKinds: Set<AttentionKind> = [.review, .feedback]
    static let defaultAlertKinds: Set<AttentionKind> = [.review, .feedback, .crash]
}

extension FeedbackStore {

    func showsBadge(_ kind: AttentionKind) -> Bool { badgeKinds.contains(kind) }

    /// 아직 안 본 진단 수. 한 앱(nil 이면 전체).
    func newCrashCount(for project: String?) -> Int {
        guard let viewed = viewedCrashIDs else { return 0 }
        return crashes(for: project).reduce(0) { $0 + (viewed.contains($1.id) ? 0 : 1) }
    }

    /// 아직 안 본 진단의 id.
    func newCrashIDs(for project: String?) -> Set<String> {
        guard let viewed = viewedCrashIDs else { return [] }
        return Set(crashes(for: project).map(\.id)).subtracting(viewed)
    }

    /// 진단 탭을 열었을 때 — 그 앱(nil 이면 전체)의 진단을 확인한 것으로.
    func markCrashesViewed(project: String?) {
        let ids = Set(crashes(for: project).map(\.id))
        guard let viewed = viewedCrashIDs, !ids.isSubset(of: viewed) else { return }
        viewedCrashIDs = viewed.union(ids)
        persistViewedCrashes()
        refreshBadge()
    }

    /// 앱 아이콘과 종이 보이는 수 — 설정에서 켠 것만.
    var attentionCount: Int {
        (showsBadge(.review) ? newStoreReviewCount : 0)
            + (showsBadge(.feedback) ? unreadCount : 0)
            + (showsBadge(.crash) ? newCrashCount(for: nil) : 0)
    }

    /// 이 기기에서 처음 진단을 받았을 때, 이미 있던 것은 새것으로 치지 않는다.
    func seedViewedCrashes() {
        guard viewedCrashIDs == nil, !allCrashes.isEmpty else { return }
        viewedCrashIDs = Set(allCrashes.map(\.id))
        persistViewedCrashes()
    }
}

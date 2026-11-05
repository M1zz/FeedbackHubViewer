//
//  BadgeReset.swift
//  FeedbackHubViewer
//
//  뱃지 모두 읽기 — 사이드바 맨 위 단추 · 칸마다 "읽음으로 표시" · 아이폰 더 보기 메뉴.
//
//  "읽음" 으로 지울 수 있는 뱃지만 지운다: 안 읽은 피드백 · 새 리뷰 · 새 진단 · 새 소식 ·
//  본 뒤 바뀐 것 · 릴리즈 빨강. 릴리즈 빨강은 그 버전이 빨강인 것을 알았다는 뜻으로만 지운다 —
//  판정과 빨강 점은 남고, 새 버전이 빨강이 되면 뱃지가 다시 선다. 할 일(남은 일) · 마케팅
//  "올렸나요?" 는 읽어서 사라지는 게 아니라 해야 사라지는 것이라 그대로 둔다.
//
//  "본 뒤 바뀐 것" 은 지우면서도 무엇이 바뀌었는지는 남긴다 — 그 칸을 열면 맨 위 띠가 여전히
//  말해 준다(`SectionChanges.markSeen`).
//

import Foundation

@MainActor
enum BadgeReset {
    /// 읽음으로 지울 수 있는 칸.
    static let readable: [FeedbackStore.ProjectSection] =
        [.feedback, .reviews, .crashes, .news, .leads] + SectionChanges.tracked

    static func isReadable(_ section: FeedbackStore.ProjectSection) -> Bool {
        readable.contains(section)
    }

    /// 이 칸에서 읽음으로 지울 수 있는 수. 뱃지와 다를 수 있다 — 리뷰 뱃지는 새 리뷰가 없으면
    /// "답 안 한 리뷰" 를 세는데, 그건 답해야 사라진다.
    static func readableCount(_ section: FeedbackStore.ProjectSection, metrics: SectionMetrics) -> Int {
        let store = metrics.store
        switch section {
        case .feedback: return store.showsBadge(.feedback) ? store.unreadCount(for: nil) : 0
        case .reviews: return store.showsBadge(.review) ? metrics.purchases.newReviewCount(for: nil) : 0
        case .crashes: return store.showsBadge(.crash) ? store.newCrashCount(for: nil) : 0
        case .news: return metrics.news.unreadCount(for: nil)
        case .leads: return LeadStore.shared.unseenCount(for: nil)
        case .release:
            return SectionChanges.shared.releaseAlerts(metrics: metrics).values.reduce(0, +)
        default: return SectionChanges.shared.changedCount(section, project: nil, metrics: metrics)
        }
    }

    /// 지금 지울 수 있는 뱃지 수의 합.
    static func readableCount(_ metrics: SectionMetrics) -> Int {
        readable.reduce(0) { $0 + readableCount($1, metrics: metrics) }
    }

    static func markRead(_ section: FeedbackStore.ProjectSection, metrics: SectionMetrics) {
        let news = metrics.news
        switch section {
        case .feedback: metrics.store.markAllRead(project: nil)
        case .reviews: metrics.purchases.markReviewsViewed(bundleID: nil)
        case .crashes: metrics.store.markCrashesViewed(project: nil)
        case .news: news.markAllRead()
        case .leads: LeadStore.shared.markViewed(project: nil)
        case .release:
            SectionChanges.shared.acknowledgeRed(metrics.store.projectCounts.map(\.key), store: metrics.store)
            SectionChanges.shared.markSeen(section,
                                           signatures: SectionChanges.signatures(section, project: nil, metrics: metrics))
        default:
            guard SectionChanges.tracked.contains(section) else { return }
            SectionChanges.shared.markSeen(section,
                                           signatures: SectionChanges.signatures(section, project: nil, metrics: metrics))
        }
    }

    static func markAllRead(metrics: SectionMetrics) {
        for section in readable { markRead(section, metrics: metrics) }
    }
}

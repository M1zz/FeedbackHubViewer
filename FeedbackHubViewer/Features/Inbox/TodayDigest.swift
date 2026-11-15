//
//  TodayDigest.swift
//  FeedbackHubViewer
//
//  할 일 맨 위의 "알아 둘 것" — 예전에는 볼 것을 알려 주는 곳이 여섯 군데(할 일 · 소식 브리핑 ·
//  사이드바 "확인할 것" · 툴바 종 · 아이폰 현황 · 칸마다 뱃지)라 다 열어 봐야 했다. 이제
//  손볼 것(아래 목록)과 알아 둘 것(여기)을 한 화면에 둔다:
//
//   1. 소식 브리핑 — 지난 하루 볼 만한 일(`BriefingCard`).
//   2. 뱃지가 선 다른 칸 — 진단 · 릴리즈 · 키워드 … 누르면 그 칸의 전체 앱으로.
//

import SwiftUI

struct TodayDigest: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore

    /// 아래 목록이 이미 다루는 칸(피드백 · 리뷰)과 할 일 · 소식 자신은 뺀다.
    static let skipped: Set<FeedbackStore.ProjectSection> = [.inbox, .news, .feedback, .reviews]

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)
        let flagged = FeedbackStore.ProjectSection.allCases.compactMap { section -> (FeedbackStore.ProjectSection, SectionMetrics.Badge)? in
            guard !Self.skipped.contains(section), let badge = metrics.badge(section, project: nil) else { return nil }
            return (section, badge)
        }
        VStack(alignment: .leading, spacing: 12) {
            BriefingCard(briefing: news.briefing())
            if !flagged.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(flagged, id: \.0) { section, badge in
                        Button {
                            store.open(project: nil, section: section)
                        } label: {
                            Label("\(section.rawValue) · \(badge.name) \(badge.count)", systemImage: badge.systemImage)
                                .font(.body)
                                .foregroundStyle(badge.tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(badge.tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

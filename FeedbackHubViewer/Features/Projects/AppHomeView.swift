//
//  AppHomeView.swift
//  FeedbackHubViewer
//
//  앱부터 고르는 길. 기능 목록(`FeatureListView`)은 "기능 → 앱" 차례라 한 앱을 리뷰 · 통계 ·
//  진단으로 넘겨 보려면 기능마다 그 앱을 다시 골라야 했다. 여기서는 앱 하나를 쥐고 그 앱의
//  기능을 무리별로 늘어놓는다. 줄마다 그 앱에 대한 한마디와 뱃지(`SectionMetrics`, 다른
//  목록과 같은 셈).
//
//  맥 · 아이패드는 사이드바가 이 구실을 한다(`FeedbackStore.focusedApp`). 이 화면은 아이폰에서
//  현황의 앱 카드를 누르면 밀려 들어온다.
//

import SwiftUI

/// 할 일 · 소식은 모든 앱을 한 목록에 두는 칸이라 한 앱의 기능 목록에서는 뺀다.
enum AppScopedSections {
    static func groups() -> [(group: FeedbackStore.ProjectSection.Group, sections: [FeedbackStore.ProjectSection])] {
        FeedbackStore.ProjectSection.Group.allCases.compactMap { group in
            let sections = group.phoneSections.filter(\.usesAppList)
            return sections.isEmpty ? nil : (group, sections)
        }
    }
}

struct AppHomeView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var icons = StoreIcons.shared
    let project: String

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)
        List {
            Section {
                HStack(spacing: 12) {
                    AppIcon(url: icons.url(for: project, keywords: keywords), size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.displayName(for: project))
                            .font(.title3.weight(.semibold))
                        if let platform = store.platformTag(for: project) {
                            Text(platform)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(AppScopedSections.groups(), id: \.group) { entry in
                Section(entry.group.rawValue) {
                    ForEach(entry.sections) { section in
                        NavigationLink(value: FeedbackStore.ProjectRoute(project: project, section: section)) {
                            FeatureRow(section: section,
                                       detail: metrics.label(section, project: project),
                                       badge: metrics.badge(section, project: project),
                                       isSelected: false)
                        }
                    }
                }
            }
        }
        .navigationTitle(store.displayName(for: project))
        .task { await icons.resolve([project], keywords: keywords) }
    }
}

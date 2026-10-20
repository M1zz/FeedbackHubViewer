//
//  ProjectSectionView.swift
//  FeedbackHubViewer
//
//  기능 하나를 앱 하나(nil 이면 전체 앱)에 대해 연 화면 — 앱의 마지막 단계.
//  기능은 맨 먼저 고르고(`FeatureListView`), 앱은 그 기능의 앱 목록에서 고른다
//  (`AppListView`). 이 화면은 둘 다 받기만 하고, 칸을 바꾸는 단추를 따로 두지 않는다.
//  예전의 열한 칸짜리 알약 줄이 그 자리였는데, 기능이 늘수록 줄이 길어져 읽히지 않았다.
//

import SwiftUI

struct ProjectSectionView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    /// nil == 전체 앱.
    let project: String?
    /// 어느 기능의 화면인가. 아이폰은 탭마다 다른 기능이 열려 있으므로 가게의 "지금 기능"
    /// 이 아니라 이 값을 따른다.
    let section: FeedbackStore.ProjectSection
    /// The Mac's inspector follows this; a phone pushes the detail instead.
    @Binding var selection: Feedback.ID?

    init(project: String?, section: FeedbackStore.ProjectSection,
         selection: Binding<Feedback.ID?> = .constant(nil)) {
        self.project = project
        self.section = section
        _selection = selection
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Everything downstream reads the scope off the store, so the pushed
            // screen and the store can never disagree about which project this is.
            // 다시 보일 때마다(아이폰 탭을 오갈 때도) 맞춘다 — 다른 탭이 가게를 바꿔 놓았을 수 있다.
            // 할 일은 앱을 가리지 않으므로 다른 기능에서 고른 앱을 지우지 않는다.
            .onAppear(perform: syncStore)
            .onChange(of: project) { syncStore() }
            // 진단 · 리뷰는 열면 확인한 것으로 — 보고 있는 동안 새로 들어온 것도.
            .task(id: viewedKey) { markViewed() }
            // 통계 · 차트 같은 칸은 열어 본 지금의 말을 본 것으로 — 보는 동안 바뀐 것도.
            .onChange(of: seenSignatures, initial: true) { _, signatures in
                SectionChanges.shared.markSeen(section, signatures: signatures)
            }
            .navigationTitle(title)
            .hubNavigationSubtitle(metrics.subtitle(section, project: project))
    }

    private func syncStore() {
        if store.projectSection != section { store.projectSection = section }
        if section.usesAppList, store.selectedProject != project { store.selectedProject = project }
    }

    private var viewedKey: String {
        let fresh: Int
        switch section {
        case .crashes: fresh = store.newCrashCount(for: project)
        case .reviews: fresh = purchases.newReviewCount(for: project)
        default: fresh = 0
        }
        return "\(project ?? "")|\(section.rawValue)|\(fresh)"
    }

    private var seenSignatures: [String: String] {
        guard SectionChanges.tracked.contains(section) else { return [:] }
        return SectionChanges.signatures(section, project: project, metrics: metrics)
    }

    private func markViewed() {
        switch section {
        case .crashes: store.markCrashesViewed(project: project)
        case .reviews: purchases.markReviewsViewed(bundleID: project)
        default: break
        }
    }

    private var title: String {
        guard section.usesAppList else { return section.rawValue }
        guard let project else { return "전체 앱" }
        return store.displayName(for: project)
    }

    private var metrics: SectionMetrics {
        SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .inbox:
            InboxView(selection: $selection)
        case .news:
            NewsView()
        case .feedback:
            FeedbackListView(selection: $selection)
        case .stats:
            StatisticsDashboard(project: project)
        case .release:
            ReleaseHealthView(project: project)
        case .acquisition:
            AcquisitionView(project: project)
        case .crashes:
            CrashListView(project: project)
        case .keywords:
            KeywordsView(project: project)
        case .charts:
            ChartRanksView(project: project)
        case .purchases:
            InAppPurchasesView(project: project)
        case .reviews:
            ReviewsView(project: project)
        case .design:
            DesignDocsView(project: project)
        case .storeAnalytics:
            StoreAnalyticsView(project: project)
        }
    }
}

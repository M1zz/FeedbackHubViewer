//
//  PhoneRootView.swift
//  FeedbackHubViewer
//
//  The iPhone layout: 하단 탭 다섯 — 현황 · 할 일 · 목소리 · 앱 상태 · 마케팅(`FeedbackStore.PhoneTab`).
//  현황은 모든 기능의 지금을 한 장에 둔 첫 화면이다(`PhoneOverviewView`).
//
//  탭마다 맨 앞은 맥 사이드바 같은 기능 목록이다(줄마다 한마디와 뱃지). 기능을 누르면 그
//  기능으로 본 앱 목록을 밀고, 앱을 누르면 그 앱의 화면 → 피드백 상세로 민다. 할 일 · 소식은
//  이미 모든 앱을 한 목록에 둔 화면이라 앱 목록 없이 바로 연다.
//
//  탭마다 스택이 따로라(`FeedbackStore.phonePaths`) 탭을 오가도 보던 자리가 남는다.
//

#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var changes = SectionChanges.shared
    /// 마케팅 칸의 "올렸나요?" 뱃지.
    @ObservedObject private var marketing = MarketingStore.shared

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)

        TabView(selection: tabSelection(metrics)) {
            ForEach(FeedbackStore.PhoneTab.allCases) { tab in
                PhoneTab(tab: tab)
                    .tabItem { Label(tab.rawValue, systemImage: tab.systemImage) }
                    .badge(badgeCount(tab, metrics: metrics))
                    .tag(tab)
            }
        }
        .modifier(SectionChangesBaseline(metrics: metrics))
        // Cross-screen links push here rather than re-scoping a column.
        .task { store.usesStackNavigation = true }
    }

    /// 지금 열린 탭을 다시 누르면 그 탭의 맨 앞으로 — 아이폰 앱들이 다 그렇게 한다.
    private func tabSelection(_ metrics: SectionMetrics) -> Binding<FeedbackStore.PhoneTab> {
        Binding(get: { store.phoneTab },
                set: { tab in
                    if tab == store.phoneTab { store.phonePaths[tab] = NavigationPath() }
                    store.phoneTab = tab
                })
    }

    /// 탭 뱃지 = 그 무리 기능들의 "손볼 것" 합. 숫자가 없으면 뱃지도 없다(0은 안 뜬다).
    private func badgeCount(_ tab: FeedbackStore.PhoneTab, metrics: SectionMetrics) -> Int {
        tab.sections.reduce(0) { $0 + (metrics.badge($1, project: nil)?.count ?? 0) }
    }
}

/// 탭 하나: 제 스택과 그 맨 앞 화면.
private struct PhoneTab: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var changes = SectionChanges.shared
    @ObservedObject private var marketing = MarketingStore.shared
    let tab: FeedbackStore.PhoneTab

    var body: some View {
        NavigationStack(path: path) {
            root
                // 큰 제목 자리는 비워 둘 만큼 쓸모가 없다 — 그 높이만큼 목록이 밀려 내려간다.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EnvironmentBadge() }
                }
                .hubToolbar()
                .navigationDestination(for: FeedbackStore.SectionRoute.self) { route in
                    appList(route.section)
                        .hubToolbar()
                }
                .navigationDestination(for: FeedbackStore.ProjectRoute.self) { route in
                    ProjectSectionView(project: route.project,
                                       section: route.section ?? tab.sections.first ?? .inbox)
                        .hubToolbar()
                }
                .navigationDestination(for: FeedbackStore.AppRoute.self) { route in
                    AppHomeView(project: route.project)
                        .hubToolbar()
                }
                .navigationDestination(for: Feedback.self) { feedback in
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                }
        }
    }

    private var path: Binding<NavigationPath> {
        Binding(get: { store.phonePaths[tab] ?? NavigationPath() },
                set: { store.phonePaths[tab] = $0 })
    }

    private var metrics: SectionMetrics {
        SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)
    }

    /// 맨 앞 — 현황 탭은 한 장짜리 현황, 나머지는 기능 목록.
    @ViewBuilder
    private var root: some View {
        if tab == .overview {
            PhoneOverviewView()
        } else {
            sectionList
        }
    }

    /// 한 기능으로 본 앱 목록. 목록을 봤으면 그 기능의 뱃지는 지운다 — 어느 앱이 바뀌었는지는 줄에 남는다.
    private func appList(_ section: FeedbackStore.ProjectSection) -> some View {
        AppListView(section: section, pushes: true)
            .onAppear { store.projectSection = section }
            .onChange(of: section) { _, new in store.projectSection = new }
            .modifier(SectionVisitTracker(section: section, project: nil, metrics: metrics,
                                          isActive: store.phoneTab == tab))
    }

    /// 맥 사이드바처럼 무리별 기능 목록. 줄에 그 기능의 한마디와 뱃지. 무리가 하나면 머리글은 없다.
    private var sectionList: some View {
        let metrics = metrics
        return List {
            ForEach(tab.groups) { group in
                Section {
                    ForEach(group.phoneSections) { section in
                        link(section) {
                            FeatureRow(section: section,
                                       detail: metrics.label(section, project: nil),
                                       badge: metrics.badge(section, project: nil),
                                       isSelected: false)
                        }
                    }
                } header: {
                    if tab.groups.count > 1 { Text(group.rawValue) }
                }
            }
        }
        .navigationTitle(tab.rawValue)
    }

    /// 앱 목록을 거치는 기능은 앱 목록으로, 할 일 · 소식은 그 화면으로.
    @ViewBuilder
    private func link(_ section: FeedbackStore.ProjectSection,
                      @ViewBuilder label: () -> some View) -> some View {
        if section.usesAppList {
            NavigationLink(value: FeedbackStore.SectionRoute(section: section), label: label)
        } else {
            NavigationLink(value: FeedbackStore.ProjectRoute(project: nil, section: section), label: label)
        }
    }
}

#Preview {
    PhoneRootView()
        .environmentObject(FeedbackStore())
        .environmentObject(AppStoreConnectStore())
}
#endif

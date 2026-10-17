//
//  PhoneRootView.swift
//  FeedbackHubViewer
//
//  The iPhone layout: 하단 탭 하나가 기능 무리 하나다 — 할 일 · 목소리 · 품질 · 성장 · 수익.
//  맥의 기능 사이드바와 같은 무리를 엄지 닿는 자리로 옮긴 것이라, 두 기기에서 무엇이
//  어디 있는지가 같다.
//
//  무리 안에 기능이 여럿이면(목소리 = 피드백 · 리뷰) 탭 맨 위의 세그먼트로 고르고, 그 아래가
//  그 기능으로 본 앱 목록이다. 앱을 누르면 그 앱의 화면 → 피드백 상세로 민다. 할 일은 이미
//  모든 앱을 앱별로 묶은 화면이라 앱 목록 없이 바로 연다.
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

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts)

        TabView(selection: tabSelection) {
            ForEach(FeedbackStore.ProjectSection.Group.phoneTabs) { tab in
                PhoneTab(tab: tab)
                    .tabItem { Label(tab.tabTitle, systemImage: tab.systemImage) }
                    .badge(badgeCount(tab, metrics: metrics))
                    .tag(tab)
            }
        }
        // Cross-screen links push here rather than re-scoping a column.
        .task { store.usesStackNavigation = true }
    }

    /// 지금 열린 탭을 다시 누르면 그 탭의 맨 앞으로 — 아이폰 앱들이 다 그렇게 한다.
    private var tabSelection: Binding<FeedbackStore.ProjectSection.Group> {
        Binding(get: { store.phoneTab },
                set: { tab in
                    if tab == store.phoneTab { store.phonePaths[tab] = NavigationPath() }
                    store.phoneTab = tab
                })
    }

    /// 탭 뱃지 = 그 무리 기능들의 "손볼 것" 합. 숫자가 없으면 뱃지도 없다(0은 안 뜬다).
    private func badgeCount(_ tab: FeedbackStore.ProjectSection.Group, metrics: SectionMetrics) -> Int {
        tab.phoneSections.reduce(0) { $0 + (metrics.badge($1, project: nil)?.count ?? 0) }
    }
}

/// 탭 하나: 제 스택과 그 맨 앞 화면.
private struct PhoneTab: View {
    @EnvironmentObject private var store: FeedbackStore
    let tab: FeedbackStore.ProjectSection.Group

    var body: some View {
        NavigationStack(path: path) {
            root
                // 큰 제목 자리는 비워 둘 만큼 쓸모가 없다 — 그 높이만큼 목록이 밀려 내려간다.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EnvironmentBadge() }
                }
                .hubToolbar()
                .navigationDestination(for: FeedbackStore.ProjectRoute.self) { route in
                    ProjectSectionView(project: route.project,
                                       section: route.section ?? store.phoneSection(for: tab))
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

    @ViewBuilder
    private var root: some View {
        let section = store.phoneSection(for: tab)
        if section.usesAppList {
            AppListView(section: section, pushes: true)
                .safeAreaInset(edge: .top, spacing: 0) { header(current: section) }
                .onAppear { store.projectSection = section }
                .onChange(of: section) { _, new in store.projectSection = new }
        } else {
            ProjectSectionView(project: nil, section: section)
                .safeAreaInset(edge: .top, spacing: 0) { banner }
        }
    }

    /// 무리 안의 기능 고르기 + 개발 빌드 띠. 기능이 하나뿐이면 세그먼트는 없다.
    @ViewBuilder
    private func header(current: FeedbackStore.ProjectSection) -> some View {
        let sections = tab.phoneSections
        if sections.count > 1 || CloudKitEnvironment.current == .development {
            VStack(spacing: 8) {
                DevelopmentBanner()
                if sections.count > 1 {
                    Picker("기능", selection: Binding(get: { current },
                                                     set: { store.phoneSections[tab] = $0 })) {
                        ForEach(sections) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .hubHeaderBar(horizontalPadding: 16, verticalPadding: 8)
        }
    }

    @ViewBuilder
    private var banner: some View {
        if CloudKitEnvironment.current == .development {
            DevelopmentBanner()
                .hubHeaderBar(horizontalPadding: 16, verticalPadding: 8)
        }
    }
}

#Preview {
    PhoneRootView()
        .environmentObject(FeedbackStore())
        .environmentObject(AppStoreConnectStore())
}
#endif

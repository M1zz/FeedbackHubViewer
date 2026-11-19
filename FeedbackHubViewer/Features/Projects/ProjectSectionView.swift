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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 탭 이름 옆 숫자가 알아본 순간 지워지게.
    @ObservedObject private var changes = SectionChanges.shared
    /// nil == 전체 앱.
    let project: String?
    /// 어느 기능의 화면인가. 아이폰은 탭마다 다른 기능이 열려 있으므로 가게의 "지금 기능"
    /// 이 아니라 이 값을 따른다.
    let requested: FeedbackStore.ProjectSection
    /// 지금 보이는 탭. 묶인 칸(`ProjectSection.members`)이면 화면 위 탭으로 바꾼다.
    @State private var section: FeedbackStore.ProjectSection
    /// The Mac's inspector follows this; a phone pushes the detail instead.
    @Binding var selection: Feedback.ID?
    /// 이 화면을 열 때 새것이던 진단 · 리뷰 — "앱|칸" 과 함께. 줄마다 "새" 를 남긴다.
    @State private var fresh: (key: String, ids: Set<String>) = ("", [])
    /// 그려 둔 화면의 "앱|칸". 다르면 먼저 로딩 표시를 띄우고 다음 순간에 그린다 — 무거운 칸(유입 ·
    /// 통계)을 누른 순간 사이드바 선택조차 바뀌지 않은 채 멈춰 보이던 것. 누르면 바로 반응한다.
    @State private var drawnKey: String?
    /// 이 화면을 열 때 선 뱃지 — "앱|칸" 과 함께. 열자마자 읽음으로 넘어가 뱃지가 사라져도
    /// 보는 동안은 맨 위에 어디서 온 뱃지였는지 남긴다.
    @State private var openedBadge: (key: String, badge: SectionMetrics.Badge?) = ("", nil)

    init(project: String?, section: FeedbackStore.ProjectSection,
         selection: Binding<Feedback.ID?> = .constant(nil)) {
        self.project = project
        self.requested = section
        _section = State(initialValue: section)
        _selection = selection
    }

    var body: some View {
        Group {
            if drawnKey == freshKey {
                content
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
            // 칸 · 앱을 바꾸면 새 화면이 툭 갈아 끼워지지 않고 짧게 번져 들어온다.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: drawnKey == freshKey)
            // 로딩 표시가 한 번 그려질 틈을 준 뒤 화면을 그린다.
            .task(id: freshKey) {
                guard drawnKey != freshKey else { return }
                try? await Task.sleep(for: .milliseconds(16))
                drawnKey = freshKey
            }
            .environment(\.freshItemIDs, fresh.key == freshKey ? fresh.ids : [])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 뱃지를 눌러 들어왔으면 무엇이 바뀌었는지가 맨 위에.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    memberTabs
                    badgeSource
                    SectionChangesBanner(section: section, project: project)
                }
            }
            .onChange(of: requested) { section = requested }
            .onChange(of: section) {
                if !store.usesStackNavigation, store.projectSection != section { store.projectSection = section }
            }
            // 띠를 얹은 화면은 "띠 + 내용" 높이를 우겨 맥 창보다 커졌고, 넘친 만큼 위아래로
            // 삐져 띠 윗부분이 툴바 밑에 깔렸다. 높이는 창이 주는 만큼만 — 띠 아래 내용이 준다.
            .frame(minHeight: 0, maxHeight: .infinity)
            // Everything downstream reads the scope off the store, so the pushed
            // screen and the store can never disagree about which project this is.
            // 다시 보일 때마다(아이폰 탭을 오갈 때도) 맞춘다 — 다른 탭이 가게를 바꿔 놓았을 수 있다.
            // 할 일은 앱을 가리지 않으므로 다른 기능에서 고른 앱을 지우지 않는다.
            .onAppear(perform: syncStore)
            .onChange(of: project) { syncStore() }
            // 진단 · 리뷰는 열면 확인한 것으로 — 보고 있는 동안 새로 들어온 것도.
            .task(id: viewedKey) { markViewed() }
            .modifier(SectionVisitTracker(section: section, project: project, metrics: metrics))
            .navigationTitle(title)
            .hubNavigationSubtitle(metrics.subtitle(section, project: project))
    }

    /// 묶인 칸의 탭 — 진단은 릴리즈 안, 스토어 분석은 통계 안 … (`ProjectSection.host`).
    @ViewBuilder
    private var memberTabs: some View {
        let members = section.members
        if members.count > 1 {
            // 가게에는 여기서 쓰지 않는다 — 탭 이름의 숫자가 바뀌면 맥의 세그먼트가 다시 만들어지며
            // 그리는 도중에 선택을 다시 써 넣는데, 그때 `@Published` 를 바꾸면 경고가 난다.
            // 가게는 `onChange(of: section)` 이 그린 뒤에 맞춘다.
            Picker("보기", selection: $section) {
                // 칸 뱃지는 탭들의 합이라, 어느 탭에서 온 수인지 탭 이름 옆에 적는다.
                ForEach(members) { member in
                    let count = metrics.countedBadge(member, project: project)?.count ?? 0
                    Text(count > 0 ? "\(member.rawValue) \(count)" : member.rawValue).tag(member)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .hubHeaderBar(verticalPadding: 8)
        }
    }

    /// 뱃지가 어디서 왔나 — 사이드바 · 앱 목록에서 본 숫자가 이 칸의 무엇인지 맨 위에 한 줄로.
    /// 본 뒤 바뀐 것은 아래 띠(`SectionChangesBanner`)가 말하므로 여기서는 한 건씩 세는 뱃지만.
    @ViewBuilder
    private var badgeSource: some View {
        let current = metrics.itemBadge(section, project: project)
        if let badge = current ?? (openedBadge.key == freshKey ? openedBadge.badge : nil) {
            HStack(spacing: 8) {
                Image(systemName: badge.systemImage)
                    .foregroundStyle(badge.tint)
                Text("뱃지 \(AppFormat.count(badge.count)) · \(badge.name)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(badge.tint)
                Spacer(minLength: 8)
                if current == nil {
                    Text("열어서 확인함")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(badge.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
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

    private var freshKey: String { "\(project ?? "")|\(section.rawValue)" }

    /// 확인한 것으로 넘기기 전에 새것이던 것을 적어 둔다 — 보고 있는 동안 새로 들어온 것도 더한다.
    private func markViewed() {
        if openedBadge.key != freshKey {
            openedBadge = (freshKey, metrics.itemBadge(section, project: project))
        }
        var ids = fresh.key == freshKey ? fresh.ids : []
        switch section {
        case .crashes:
            ids.formUnion(store.newCrashIDs(for: project))
            store.markCrashesViewed(project: project)
        case .reviews:
            ids.formUnion(purchases.newReviewIDs(for: project))
            purchases.markReviewsViewed(bundleID: project)
        default: break
        }
        fresh = (freshKey, ids)
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
        case .giftCodes:
            GiftCodesView(project: project)
        case .supporters:
            SupportersView(project: project)
        case .reviews:
            ReviewsView(project: project)
        case .design:
            DesignDocsView(project: project)
        case .storeAnalytics:
            StoreAnalyticsView(project: project)
        case .marketing:
            MarketingView(project: project)
        case .experience:
            ExperienceView(project: project)
        }
    }
}

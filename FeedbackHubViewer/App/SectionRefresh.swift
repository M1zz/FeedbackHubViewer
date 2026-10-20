//
//  SectionRefresh.swift
//  FeedbackHubViewer
//
//  화면마다 제 데이터만 새로 받는 새로고침.
//
//  예전에는 툴바의 새로고침 하나가 CloudKit(피드백 · 사용 통계 · 진단)과 App Store
//  Connect(리뷰 · 판매 · 상품 · 노출 · 링크 출처)를 한꺼번에 받았다. 리뷰를 보다가 누르면
//  몇 분 걸리는 사용 현황까지 같이 돌고, 정작 차트 순위나 키워드 순위는 받지 않았다. 어느
//  단추가 무엇을 받는지 알 수 없었다. 이제 툴바 단추 · ⌘R · 당겨서 새로고침은 지금 보는
//  화면에 나오는 것만 받고, 전부는 ⇧⌘R 과 데이터 상태 칸의 "모두 새로고침"이 받는다.
//

import SwiftUI

/// 화면마다 무엇을 받는지. 고른 앱이 없으면(전체 프로젝트) 그 화면이 보여 주는 모든 앱의 것.
@MainActor
struct SectionRefresh {
    let store: FeedbackStore
    let connect: AppStoreConnectStore
    let keywords: KeywordStore
    let charts: ChartStore
    let news: NewsStore
    let design: DesignDocsStore

    var section: FeedbackStore.ProjectSection { store.projectSection }

    /// 고른 앱. 분류 안 된 피드백 묶음은 스토어에 없는 앱이라 전체로 친다.
    var project: String? {
        store.selectedProject == Feedback.unclassifiedProject ? nil : store.selectedProject
    }

    private var appKeys: [String] {
        store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject }
    }

    /// 단추 이름 — 무엇을 받는지가 이름에 있다.
    var title: String {
        switch section {
        case .inbox: "할 일 새로고침"
        case .news: "소식 새로 찾기"
        case .feedback: "피드백 새로고침"
        case .reviews: "리뷰 새로고침"
        case .stats: "통계 새로고침"
        case .release: "릴리즈 새로고침"
        case .acquisition: "유입 새로고침"
        case .storeAnalytics: "스토어 분석 새로고침"
        case .crashes: "진단 새로고침"
        case .keywords: "키워드 순위 확인"
        case .charts: "차트 순위 새로고침"
        case .purchases: "앱 내 구입 새로고침"
        case .design: "설계 문서 다시 읽기"
        }
    }

    /// 받는 것의 목록. 단추에 마우스를 올리면 나온다.
    var sources: String {
        let scope = project == nil ? "모든 앱의 " : ""
        return switch section {
        case .inbox: "피드백 · 진단 · 모든 앱의 리뷰"
        case .news: "바깥 뉴스(Google 뉴스 · 레딧)와 소식 다시 모으기"
        case .feedback: "피드백"
        case .reviews: "\(scope)App Store 리뷰"
        case .stats: "사용 현황 · 이벤트"
        case .release: project == nil ? "사용 현황 · 이벤트 · 진단" : "사용 현황 · 이벤트 · 진단 · 리뷰"
        case .acquisition: project == nil ? "모든 앱의 노출 · 전환 · 스토어 문구" : "노출 · 전환 · 스토어 문구 · 링크 출처"
        case .storeAnalytics: project == nil ? "분석 리포트가 있는 앱 목록" : "스토어 분석 리포트"
        case .crashes: "진단"
        case .keywords: "오늘 아직 확인 안 한 키워드 순위"
        case .charts: "나라마다 인기 차트 순위"
        case .purchases: project == nil ? "판매 · 모든 앱의 상품" : "판매 · 상품 · 노출 · 전환"
        case .design: "리포의 설계 문서 목록"
        }
    }

    /// 이 화면의 것을 받는 중인가. 단추를 막고 바퀴를 돌린다.
    var isRunning: Bool {
        switch section {
        case .inbox:
            return store.isRefreshing || appKeys.contains { connect.reviewFeeds[$0]?.isLoading == true }
        case .feedback, .stats, .crashes:
            return store.isRefreshing
        case .release:
            return store.isRefreshing || project.map { connect.reviewFeeds[$0]?.isLoading == true } == true
        case .news:
            return news.isSearchingWeb
        case .reviews:
            return (project.map { [$0] } ?? appKeys).contains { connect.reviewFeeds[$0]?.isLoading == true }
        case .acquisition:
            guard let project else { return false }
            return connect.funnels[project]?.isLoading == true
                || connect.metadata[project]?.isLoading == true
                || connect.referrals[project]?.isLoading == true
        case .storeAnalytics:
            guard let project else { return false }
            return connect.storeAnalytics[project]?.isLoading == true
        case .keywords:
            return keywords.isChecking
        case .charts:
            return charts.isScanning
        case .purchases:
            return connect.isLoadingSales || project.map(connect.isCatalogLoading) == true
        case .design:
            return false
        }
    }

    /// 이 화면의 것만 받는다. App Store Connect 처럼 오래 걸리는 것은 뒤에서 받고, 당겨서
    /// 새로고침의 바퀴는 CloudKit 이 끝날 때까지만 붙잡는다(`HubRefresh.now` 와 같은 까닭).
    func run() async {
        let project = project
        let connect = connect
        let appKeys = appKeys
        switch section {
        case .inbox:
            Task { await connect.loadReviews(bundleIDs: appKeys, force: true) }
            await store.load([.feedback, .crashes])
        case .news:
            await news.refreshWebIfDue(force: true)
            news.collect()
        case .feedback:
            await store.load(.feedback)
        case .reviews:
            if let project {
                await connect.loadReviews(bundleID: project, force: true)
            } else {
                await connect.loadReviews(bundleIDs: appKeys, force: true)
            }
        case .stats:
            await store.load(.numbers)
        case .release:
            if let project { Task { await connect.loadReviews(bundleID: project, force: true) } }
            await store.load([.numbers, .crashes])
        case .acquisition:
            if let project {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await connect.loadFunnel(bundleID: project, force: true) }
                    group.addTask { await connect.loadMetadata(bundleID: project, force: true) }
                    group.addTask { await connect.loadReferrals(bundleID: project, force: true) }
                }
            } else {
                for map in AcquisitionCatalog.all {
                    await connect.loadFunnel(bundleID: map.appId, force: true)
                    await connect.loadMetadata(bundleID: map.appId, force: true)
                }
            }
        case .storeAnalytics:
            if let project {
                await connect.loadStoreAnalytics(bundleID: project, force: true)
            } else {
                await connect.loadAnalyticsCoverage(force: true)
            }
        case .crashes:
            await store.load(.crashes)
        case .keywords:
            keywords.check(bundleIds: store.allProjectKeys)
        case .charts:
            let ids = Set(store.projectCounts.compactMap { keywords.trackId(for: $0.key) })
            await charts.scan(trackIds: ids)
        case .purchases:
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await connect.loadSales(force: true) }
                if connect.subscriptionEvents != nil {
                    group.addTask { await connect.loadSubscriptionEvents(force: true) }
                }
                if let project {
                    group.addTask { await connect.loadCatalog(bundleID: project, force: true) }
                    group.addTask { await connect.loadFunnel(bundleID: project, force: true) }
                } else {
                    group.addTask {
                        for key in appKeys { await connect.loadCatalog(bundleID: key, force: true) }
                    }
                }
            }
        case .design:
            design.rescan()
        }
    }
}

/// 지금 보는 화면의 것만 새로 받는 단추. 이름이 화면마다 바뀐다(리뷰 새로고침 · 차트 순위 새로고침 …).
struct RefreshButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var design: DesignDocsStore

    var body: some View {
        let refresh = SectionRefresh(store: store, connect: connect, keywords: keywords,
                                     charts: charts, news: news, design: design)
        Button {
            Task { await refresh.run() }
        } label: {
            Label(refresh.title, systemImage: "arrow.clockwise")
        }
        .disabled(refresh.isRunning)
        .help("새로 받는 것: \(refresh.sources) (⌘R) · 전부는 ⇧⌘R")
    }
}

/// 이 화면의 새로고침을 당겨서 새로고침에도.
struct SectionRefreshable: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var design: DesignDocsStore

    func body(content: Content) -> some View {
        content.refreshable {
            await SectionRefresh(store: store, connect: connect, keywords: keywords,
                                 charts: charts, news: news, design: design).run()
        }
    }
}

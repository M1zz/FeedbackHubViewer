//
//  AppStoreConnectStore+Refresh.swift
//  FeedbackHubViewer
//
//  새로고침 단추 하나로 App Store Connect 쪽도 다시 받는다.
//
//  예전에는 툴바의 새로고침이 CloudKit(피드백 · 사용 통계)만 읽고, 리뷰 · 판매 · 상품 ·
//  노출 · 링크 출처는 화면마다 따로 있는 "다시 읽기"를 눌러야 했다. 어느 단추가 무엇을
//  새로 받는지 알 길이 없었다. 이제 툴바의 새로고침이 지금 보는 앱에 딸린 것을 전부
//  다시 받고, 무엇을 언제 받았는지는 데이터 상태 칸(`DataSourcesPanel`)이 말한다.
//

import Foundation

extension AppStoreConnectStore {

    /// 지금 보는 앱(nil 이면 계정 전체)에 딸린 것을 한꺼번에 새로 받는다. 이미 받는 중인
    /// 것은 건너뛴다 — 같은 리포트를 두 번 받을 이유가 없다.
    func refreshAll(project: String?) async {
        guard isConfigured else { return }
        let project = project == Feedback.unclassifiedProject ? nil : project
        // 앱 id 를 먼저 한 번 찾아 둔다. 아래 다섯이 동시에 같은 것을 묻지 않게.
        if let project { _ = try? await resolveApp(project) }

        await withTaskGroup(of: Void.self) { group in
            if !isLoadingSales {
                group.addTask { await self.loadSales(force: true) }
            }
            // 구독 이벤트는 구독 앱을 열었을 때만 받는다(서른 날치 요청). 받은 적 있을 때만.
            if subscriptionEvents != nil, !isLoadingSubscriptionEvents {
                group.addTask { await self.loadSubscriptionEvents(force: true) }
            }
            guard let project else { return }
            if reviewFeeds[project]?.isLoading != true {
                group.addTask { await self.loadReviews(bundleID: project, force: true) }
            }
            if !isCatalogLoading(project) {
                group.addTask { await self.loadCatalog(bundleID: project, force: true) }
            }
            if metadata[project]?.isLoading != true {
                group.addTask { await self.loadMetadata(bundleID: project, force: true) }
            }
            if funnels[project]?.isLoading != true {
                group.addTask { await self.loadFunnel(bundleID: project, force: true) }
            }
            if referrals[project]?.isLoading != true {
                group.addTask { await self.loadReferrals(bundleID: project, force: true) }
            }
        }
    }

    func isCatalogLoading(_ project: String) -> Bool {
        if case .loading? = catalogs[project] { return true }
        return false
    }

    /// 지금 받는 중인 것의 이름들. 툴바 상태 줄이 CloudKit 다음으로 말한다.
    func loadingSources(project: String?) -> [String] {
        var names: [String] = []
        if let project {
            if reviewFeeds[project]?.isLoading == true { names.append("리뷰") }
            if isCatalogLoading(project) { names.append("상품") }
            if metadata[project]?.isLoading == true { names.append("스토어 문구") }
            if funnels[project]?.isLoading == true { names.append("노출 · 전환") }
            if referrals[project]?.isLoading == true { names.append("링크 출처") }
        }
        if isLoadingSales { names.append("판매") }
        if isLoadingSubscriptionEvents { names.append("구독 이벤트") }
        return names
    }
}

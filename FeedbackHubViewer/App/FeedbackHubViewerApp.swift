//
//  FeedbackHubViewerApp.swift
//  FeedbackHubViewer
//
//  A small multiplatform app (macOS + iOS/iPadOS) that shows feedback collected
//  in the CloudKit public database of the "iCloud.com.Ysoup.FeedbackHub"
//  container.
//

import SwiftUI

@main
struct FeedbackHubViewerApp: App {
    @StateObject private var store = FeedbackStore()
    /// App Store search ranks. A store of its own because it reads a different
    /// source entirely (see `KeywordStore`) and must not be disturbed by — or
    /// disturb — anything the CloudKit refresh does.
    @StateObject private var keywords = KeywordStore()
    /// 나라별 App Store 인기 차트 순위. 공개 피드를 읽고 파일도 제 것이다(`ChartStore`).
    @StateObject private var charts = ChartStore()
    /// App Store Connect — 상품과 판매. 키가 있을 때만 읽는다(`AppStoreConnectStore`).
    @StateObject private var purchases = AppStoreConnectStore()
    /// 앱 리포의 설계 문서 폴더를 지켜본다(맥만).
    @StateObject private var designDocs = DesignDocsStore()
    /// 새 피드백 · 리뷰 알림(`AlertWatcher`).
    @StateObject private var watcher = AlertWatcher()
    /// 내 앱 소식 — 다른 가게들이 받아 둔 것에서 사건을 찾아 알린다(`NewsStore`).
    @StateObject private var news = NewsStore()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(HubAppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(HubAppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .environmentObject(keywords)
                .environmentObject(purchases)
                .environmentObject(designDocs)
                .environmentObject(charts)
                .environmentObject(news)
                .task {
                    // Paint the cached hub, then check CloudKit for changes on
                    // a task the store owns — the window never waits for it.
                    store.start()
                    watcher.start(store: store, purchases: purchases)
                    // The rank history is its own small file and waits for
                    // nothing — it is on screen before the hub has finished
                    // decoding.
                    keywords.restore()
                    charts.restore()
                    // The daily rank check does wait: the apps it looks for in
                    // each result list are the hub's project keys, and before
                    // the restore there are none.
                    await store.awaitRestore()
                    keywords.start(bundleIds: store.allProjectKeys)
                    startChartsIfDue()
                    news.start(store: store, keywords: keywords, charts: charts, purchases: purchases)
                }
                // 그리고 그 뒤로도. 위의 목록은 캐시가 그려진 순간의 것이고,
                // 앱이 처음 리포트를 보내면 그 앱은 **새로고침이 끝난 뒤에야**
                // 목록에 들어온다 — 아이콘을 그때 다시 묻지 않으면 다음 실행
                // 때까지 점선 자리표시자로 남는다. 이미 물어본 것은 다시 묻지
                // 않으므로(`syncLinks`) 새로고침마다 요청이 늘지 않는다.
                .onChange(of: store.allProjectKeys) { _, keys in
                    keywords.syncLinks(bundleIds: keys)
                    startChartsIfDue()
                }
                // 앱 이름은 스토어에 걸린 이름으로. 두 스토어가 나누는 것은 여기
                // 이 이름표 하나뿐이다(`FeedbackStore.storeAppNames`).
                //
                // 넘겨받은 값에서 읽는다 - `$history`는 값이 바뀌기 **전에** 울려서,
                // 그 순간 `keywords.history`를 읽으면 한 박자 늦은 이름이 된다.
                .onReceive(keywords.$history) { history in
                    store.storeAppNames = history.storeNames
                    startChartsIfDue(links: history.links)
                }
                // 다른 기기에서 넣은 App Store Connect 키는 iCloud 키체인이 언제 내려 줄지
                // 모른다. 앱이 앞으로 올 때마다 키가 없으면 다시 본다.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        purchases.reloadCredentialsIfMissing()
                        news.collect()
                    }
                    #if os(iOS)
                    // 뒤로 가면 리뷰를 볼 다음 차례를 iOS 에 부탁해 둔다.
                    if phase == .background { AlertWatcher.scheduleAppRefresh() }
                    #endif
                }
                // 앱 아이콘 뱃지에 새 스토어 리뷰도 — 리뷰는 App Store Connect 쪽이 쥐고 있다.
                .onChange(of: purchases.newReviewCount(for: nil), initial: true) { _, count in
                    store.newStoreReviewCount = count
                }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(AlertWatcher.refreshTaskID)) {
            await watcher.backgroundCheck(store: store, purchases: purchases)
            news.start(store: store, keywords: keywords, charts: charts, purchases: purchases)
            await news.refreshWebIfDue()
            news.collect()
        }
        #endif
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("모두 새로고침") {
                    Task { await HubRefresh.now(store, purchases) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        // ⌘, — App Store Connect 키, 뱃지 · 알림.
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(purchases)
                .environmentObject(news)
        }
        #endif
    }

    /// 차트는 스토어와 이어진 내 앱만 본다. 앱 목록이 생길 때(복원 뒤) · 이음이 새로 생길 때
    /// 불리고, 볼 때가 아니면 그냥 돌아온다 — 저절로는 12시간에 한 번(`ChartStore.startIfDue`).
    /// `links` 는 `$history` 가 울린 순간의 새 값(그때 `keywords.history` 는 아직 옛것이다).
    private func startChartsIfDue(links: [String: Int]? = nil) {
        let links = links ?? keywords.history.links
        charts.startIfDue(trackIds: Set(store.allProjectKeys.compactMap { links[$0] }))
    }

    @ViewBuilder
    private var rootView: some View {
        #if os(macOS)
        ContentView()
            .frame(minWidth: SplitRootView.windowMinWidth, minHeight: 560)
        #else
        ContentView()
        #endif
    }
}

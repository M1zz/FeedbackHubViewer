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

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .environmentObject(keywords)
                .task {
                    // Paint the cached hub, then check CloudKit for changes on
                    // a task the store owns — the window never waits for it.
                    store.start()
                    // The rank history is its own small file and waits for
                    // nothing — it is on screen before the hub has finished
                    // decoding.
                    keywords.restore()
                    // The daily rank check does wait: the apps it looks for in
                    // each result list are the hub's project keys, and before
                    // the restore there are none.
                    await store.awaitRestore()
                    keywords.start(bundleIds: store.allProjectKeys)
                }
                // 그리고 그 뒤로도. 위의 목록은 캐시가 그려진 순간의 것이고,
                // 앱이 처음 리포트를 보내면 그 앱은 **새로고침이 끝난 뒤에야**
                // 목록에 들어온다 — 아이콘을 그때 다시 묻지 않으면 다음 실행
                // 때까지 점선 자리표시자로 남는다. 이미 물어본 것은 다시 묻지
                // 않으므로(`syncLinks`) 새로고침마다 요청이 늘지 않는다.
                .onChange(of: store.allProjectKeys) { _, keys in
                    keywords.syncLinks(bundleIds: keys)
                }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await store.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        #if os(macOS)
        ContentView()
            .frame(minWidth: 900, minHeight: 560)
        #else
        ContentView()
        #endif
    }
}

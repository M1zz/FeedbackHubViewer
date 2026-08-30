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
                    // Ranks move by the day, so this checks at most once a day.
                    // It waits for the cache first: the apps it looks for in
                    // each result list are the hub's project keys, and before
                    // the restore there are none.
                    await store.awaitRestore()
                    keywords.start(bundleIds: store.allProjectKeys)
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

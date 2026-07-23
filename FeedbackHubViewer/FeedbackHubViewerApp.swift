//
//  FeedbackHubViewerApp.swift
//  FeedbackHubViewer
//
//  A small macOS app that shows feedback collected in the
//  CloudKit public database of the "iCloud.com.Ysoup.FeedbackHub" container.
//

import SwiftUI

@main
struct FeedbackHubViewerApp: App {
    @StateObject private var store = FeedbackStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    // Load once when the window first appears.
                    if store.allFeedback.isEmpty {
                        await store.load()
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await store.load() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

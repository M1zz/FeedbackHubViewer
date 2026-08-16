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

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(store)
                .task {
                    // Load once when the window first appears.
                    if store.allFeedback.isEmpty {
                        await store.load()
                    }
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

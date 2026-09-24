//
//  ContentView.swift
//  FeedbackHubViewer
//
//  Picks the layout for the running platform and window size: a three-column
//  split view on macOS and iPad (`SplitRootView`), a stack on iPhone
//  (`PhoneRootView`).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        layout
            // A refresh writes what it has read every few seconds; this is what
            // keeps the last few from being lost when the app is quit or —
            // on a phone, which is most of the time — switched away from
            // while the read is still running.
            //
            // It hangs here rather than on the `WindowGroup`'s own content
            // because SwiftUI builds the saved-window-frame key out of that
            // view's type name: a modifier up there renames the key and every
            // Mac forgets the window size it had.
            .onReceive(NotificationCenter.default.publisher(for: Platform.willStopNotification)) { _ in
                store.flushCache()
            }
            #if os(iOS)
            // 맥은 설정 창(⌘,)이고, 터치 기기는 "더 보기 → 설정"이 이 시트를 연다.
            .sheet(isPresented: $connect.isShowingSettings) {
                SettingsView()
                    .environmentObject(connect)
            }
            #endif
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        SplitRootView()
        #else
        // A regular width (iPad, or an iPhone in landscape on the biggest
        // devices) has room for the same three columns the Mac uses.
        if horizontalSizeClass == .regular {
            SplitRootView()
        } else {
            PhoneRootView()
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(FeedbackStore())
        .environmentObject(AppStoreConnectStore())
}

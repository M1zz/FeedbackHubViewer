//
//  HubToolbar.swift
//  FeedbackHubViewer
//
//  The controls that belong to the hub rather than to any one screen: refresh
//  now, refresh every minute, notify me, and who am I to CloudKit.
//
//  Three layouts want them — the Mac window toolbar, the iPad column, the
//  iPhone stack — and the two touch layouts had grown their own copies of the
//  same overflow menu, which is how the iPad's lost the "알림을 허용하세요" line
//  that the iPhone's had.
//

import SwiftUI

/// 지금 새로고침. Disabled while a read is already in flight.
struct RefreshButton: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        Button {
            Task { await store.load() }
        } label: {
            Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(store.isRefreshing)
        .help("지금 새로고침")
    }
}

/// The touch platforms' "더 보기" menu: everything the Mac spreads across its
/// window toolbar, folded into one item.
struct HubOverflowMenu: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        Menu {
            Toggle(isOn: $store.autoRefresh) {
                Label("자동 갱신 (1분)", systemImage: "timer")
            }
            Toggle(isOn: $store.notificationsEnabled) {
                Label("새 피드백·진단 알림", systemImage: "bell.badge")
            }
            if store.notificationsEnabled && !store.notificationsAuthorized {
                Section {
                    Text("시스템 설정에서 이 앱의 알림을 허용해야 알림이 표시됩니다.")
                }
            }
            // What a running refresh is doing, or when the last one landed.
            // There is no status line in a navigation bar to put it on.
            if let progress = store.refreshProgress {
                Section { Text(progress.text) }
            } else if let updated = store.lastUpdated {
                Section { Text("업데이트: \(AppFormat.time(updated))") }
            }
            Section {
                IdentityMenu()
            }
        } label: {
            Label("더 보기", systemImage: "ellipsis.circle")
        }
    }
}

#if os(iOS)
/// Navigation-bar items for every screen in a touch layout's stack, plus
/// pull-to-refresh. Applied per screen because a `NavigationStack` gives each
/// pushed view its own bar.
struct HubToolbar: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { RefreshButton() }
                ToolbarItem(placement: .topBarTrailing) { HubOverflowMenu() }
            }
            .refreshable { await store.load() }
    }
}

extension View {
    func hubToolbar() -> some View { modifier(HubToolbar()) }
}
#endif

/// The toolbar's status line: what a running refresh is doing, or when the
/// data last came in.
///
/// The cached hub is already on screen by now, so a refresh reports in passing
/// rather than replacing the window with a spinner. What it reports is the step
/// it is on and how many records it has read — see `FeedbackStore.RefreshProgress`
/// for why there is no percentage to show.
///
/// It is its own view, not inline in the toolbar body, so a store change
/// rebuilds this label alone rather than the whole toolbar (see `IdentityMenu`).
struct RefreshStatus: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        if store.isRefreshing {
            HStack(spacing: 6) {
                if let progress = store.refreshProgress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 54)
                    Text(progress.text)
                } else {
                    ProgressView().controlSize(.small)
                    Text("업데이트 확인 중…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // The step number and the record count both change width as they
            // climb; without this the neighbouring toolbar items jitter.
            .frame(minWidth: 210, alignment: .leading)
            .monospacedDigit()
        } else if let updated = store.lastUpdated {
            Text("업데이트: \(AppFormat.time(updated))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A menu that shows which CloudKit environment is being read and this
/// account's user record name — the value to register in an admin Security
/// Role so the account can read feedback that World is not permitted to read.
///
/// State is read inside the menu body, never in the label: a toolbar item with
/// a state-dependent label is rebuilt on every store change, and on macOS 26
/// such rebuilds have been seen to crash the toolbar mid-update.
struct IdentityMenu: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        Menu {
            Section("CloudKit 환경") {
                Text(store.environmentDescription)
            }
            if let name = store.userRecordName, !name.isEmpty {
                Section("내 CloudKit User Record Name") {
                    Text(name)
                }
                Button {
                    Platform.copyToPasteboard(name)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                Text("CloudKit Console → Security Roles의 admin 역할에 이 값을 등록하고 피드백 레코드 타입에 read 권한을 준 뒤 Production으로 배포하세요.")
            } else {
                Text("iCloud 계정을 확인할 수 없습니다. 이 \(Platform.deviceNoun)에 iCloud 로그인이 되어 있는지 확인하세요.")
            }

            if store.notificationsEnabled && !store.notificationsAuthorized {
                Section("알림") {
                    Text("시스템 설정에서 이 앱의 알림을 허용해야 알림이 표시됩니다.")
                }
            }

            // The saved hub is what makes a launch instant; this is the way
            // back to a clean read when it looks stale or wrong.
            Section("저장된 데이터") {
                Button {
                    Task { await store.resetCacheAndReload() }
                } label: {
                    Label("캐시 비우고 전체 다시 불러오기", systemImage: "arrow.clockwise.circle")
                }
                .disabled(store.isRefreshing)
            }
        } label: {
            Label("내 계정 ID", systemImage: "person.crop.circle.badge.questionmark")
        }
        .help("Security Role 등록에 쓸 내 CloudKit User Record Name")
    }
}

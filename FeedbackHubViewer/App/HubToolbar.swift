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
        if store.isRefreshing || store.isPublishingSummary {
            HStack(spacing: 6) {
                // 올리기는 새로고침의 마지막 걸음이라 같은 자리에 나온다.
                // 먼저 묻는 이유는 그때 이미 읽기가 끝나 있기 때문이다 —
                // 남은 진행 표시를 그대로 두면 다 읽은 것을 아직 읽는
                // 중이라고 말하게 된다.
                if store.isPublishingSummary {
                    ProgressView().controlSize(.small)
                    Text("iCloud 요약본 올리는 중…")
                } else if let progress = store.refreshProgress {
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

            // 숫자가 어디서 온 것인지. 기기마다 값이 다른 것보다 나쁜 것은
            // 왜 다른지 알 수 없는 것이라, 이 줄은 잘 되고 있을 때에도 보인다.
            Section("기기 사이 숫자") {
                SummaryStatusItems()
            }

            // 켜져 있으면 굳이 말할 것도 없지만, 꺼져 있는 것은 반드시 보여야
            // 한다 — 안 그러면 다른 기기에서 처리한 게 왜 안 넘어오는지 알 길이
            // 없다.
            Section("읽음 · 처리 동기화") {
                if store.isReviewStateSynced {
                    Label("이 iCloud 계정의 기기끼리 맞춰집니다", systemImage: "checkmark.icloud")
                } else {
                    Label("이 \(Platform.deviceNoun)에서만 기억합니다", systemImage: "icloud.slash")
                    Text("iCloud 로그인과 iCloud Drive가 켜져 있어야 읽음·반영함 표시가 기기 사이에서 하나가 됩니다.")
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

/// 요약본이 지금 어떤 상태인지, 메뉴 한 칸에 들어갈 만큼만.
///
/// 실행할 때 iCloud에서 받아온 요약본이 화면의 바탕이므로, 그것이 **언제**
/// **어느 기기**에서 만들어졌는지는 숨길 것이 아니다. 맥과 아이폰의 숫자가
/// 같아진 다음에도 사람이 확인할 수 있어야 그 숫자를 믿는다.
struct SummaryStatusItems: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        if let notice = store.summaryNotice {
            Label("이 \(Platform.deviceNoun)에서 읽은 것만 셉니다", systemImage: "icloud.slash")
            Text(notice)
        } else if store.isPublishingSummary {
            Label("iCloud에 올리는 중…", systemImage: "icloud.and.arrow.up")
        } else if let at = store.summaryUpdatedAt {
            Label("\(AppFormat.dateTime(at)) · \(store.summaryDevice ?? "다른 기기")",
                  systemImage: "checkmark.icloud")
            Text("실행할 때 이 요약본을 받아오고, 새로고침하면 여기가 갱신됩니다. 그래서 어느 기기에서 보든 같은 숫자입니다.")
        } else {
            Label("아직 올린 요약본이 없습니다", systemImage: "icloud")
            Text("한 번 새로고침하면 이 기기가 읽은 것이 iCloud에 올라가고, 다른 기기가 실행할 때 그것을 받아 갑니다.")
        }
    }
}

//
//  ContentView.swift
//  FeedbackHubViewer
//
//  Picks the layout for the running platform and window size: a three-column
//  split view on macOS and iPad, a tab-based layout on iPhone (PhoneRootView).
//

import SwiftUI

struct ContentView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
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

/// Three columns, one per level of the hierarchy: which project on the left,
/// that project's 피드백 · 통계 · 진단 in the middle, and the selected feedback
/// on the right.
struct SplitRootView: View {
    @EnvironmentObject private var store: FeedbackStore
    @State private var selection: Feedback.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .navigationTitle("프로젝트")
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        // The project screen sits beside the project list here rather than on
        // top of it, so cross-screen links re-scope the column instead of
        // pushing (see `FeedbackStore.open(project:section:)`).
        .task { store.usesStackNavigation = false }
        #if os(macOS)
        .toolbar { macToolbarContent }
        #endif
    }

    /// The selected project's screen. Which project it is comes from the
    /// sidebar; which of its three sections is showing comes from the store.
    private var contentColumn: some View {
        NavigationStack(path: $store.path) {
            ProjectSectionView(project: store.selectedProject, selection: $selection)
            #if os(iOS)
            // iPad pushes the detail inside this column when the third column
            // is collapsed; the Mac always has the detail column.
            .navigationDestination(for: Feedback.self) { feedback in
                FeedbackDetailView(feedback: feedback,
                                   projectLabel: store.displayName(for: feedback.projectKey))
            }
            // On iPad a toolbar attached to the split view itself never appears —
            // the shared controls have to live on a column.
            .toolbar { padToolbarContent }
            #endif
        }
        .navigationSplitViewColumnWidth(min: 340, ideal: 480, max: 760)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selection, let feedback = store.allFeedback.first(where: { $0.id == id }) {
            FeedbackDetailView(feedback: feedback,
                               projectLabel: store.displayName(for: feedback.projectKey))
        } else {
            ContentUnavailableView(
                "피드백을 선택하세요",
                systemImage: "text.bubble",
                description: Text("목록에서 항목을 선택하면 전체 내용이 여기에 표시됩니다.")
            )
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.load() }
        } label: {
            Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(store.isRefreshing)
        .help("지금 새로고침")
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            RefreshStatus()
        }

        ToolbarItem(placement: .primaryAction) {
            IdentityMenu()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $store.notificationsEnabled) {
                Label("알림", systemImage: "bell.badge")
            }
            .help("새 피드백·진단이 들어오면 알리고, 앱 아이콘에 안 읽은 수를 표시합니다")
            .toggleStyle(.button)

            Toggle(isOn: $store.autoRefresh) {
                Label("자동 갱신", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("1분마다 자동으로 새로고침합니다")
            .toggleStyle(.button)

            refreshButton
        }
    }
    #else
    @ToolbarContentBuilder
    private var padToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { refreshButton }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $store.autoRefresh) {
                    Label("자동 갱신 (1분)", systemImage: "arrow.triangle.2.circlepath")
                }
                Toggle(isOn: $store.notificationsEnabled) {
                    Label("새 피드백·진단 알림", systemImage: "bell.badge")
                }
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
    #endif
}

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

#Preview {
    ContentView()
        .environmentObject(FeedbackStore())
}

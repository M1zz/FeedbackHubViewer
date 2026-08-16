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

/// Three-column layout: filters + stats on the left, the feedback list in the
/// middle, the selected item's detail on the right.
struct SplitRootView: View {
    @EnvironmentObject private var store: FeedbackStore
    @State private var selection: Feedback.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .navigationTitle("Feedback Hub")
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        #if os(macOS)
        .toolbar { macToolbarContent }
        #endif
    }

    /// 개요 / 통계 are the two panes; the feedback list is pushed on top of
    /// them (from a project card, or from the statistics dashboard).
    private var contentColumn: some View {
        NavigationStack(path: $store.listPath) {
            Group {
                switch store.viewMode {
                case .overview:
                    ProjectOverviewView()
                case .stats:
                    StatisticsView()
                }
            }
            .navigationDestination(for: FeedbackStore.ListRoute.self) { route in
                FeedbackListView(selection: $selection)
                    .task { store.selectedProject = route.project }
            }
            #if os(iOS)
            // iPad pushes inside this column the way the phone pushes inside a
            // tab; the Mac shows the feedback itself in the detail column.
            .navigationDestination(for: FeedbackStore.StatsRoute.self) { route in
                StatisticsDashboard(project: route.project)
                    .task { store.selectedProject = route.project }
            }
            #endif
            .navigationDestination(for: FeedbackStore.CrashRoute.self) { route in
                CrashListView(project: route.project)
            }
            #if os(iOS)
            .navigationDestination(for: Feedback.self) { feedback in
                FeedbackDetailView(feedback: feedback,
                                   projectLabel: store.displayName(for: feedback.projectKey))
            }
            // On iPad a toolbar attached to the split view itself never appears —
            // the shared controls have to live on a column.
            .toolbar { padToolbarContent }
            #endif
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 460, max: 720)
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

    /// The view-mode switch, shared by both platforms' toolbars.
    private var modePicker: some View {
        Picker("보기", selection: $store.viewMode) {
            ForEach(FeedbackStore.ViewMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
            }
        }
        #if os(iOS)
        .pickerStyle(.segmented)
        #endif
        .help("프로젝트 개요·통계·목록 전환")
    }

    private var refreshButton: some View {
        Button {
            Task { await store.load() }
        } label: {
            Label("새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(store.isLoading)
        .help("지금 새로고침")
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if let updated = store.lastUpdated {
                Text("업데이트: \(AppFormat.time(updated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .principal) { modePicker }

        ToolbarItem(placement: .primaryAction) {
            IdentityMenu()
        }

        ToolbarItemGroup(placement: .primaryAction) {
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
        // Leading, not principal: a principal item makes iOS draw the
        // title/subtitle twice next to the large title.
        ToolbarItem(placement: .topBarLeading) {
            // A fixed width: inside a navigation bar the segmented control
            // otherwise collapses to a few unreadable pixels.
            modePicker.frame(width: 176)
        }

        ToolbarItem(placement: .topBarTrailing) { refreshButton }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $store.autoRefresh) {
                    Label("자동 갱신 (1분)", systemImage: "arrow.triangle.2.circlepath")
                }
                Toggle(isOn: $store.notificationsEnabled) {
                    Label("새 피드백·진단 알림", systemImage: "bell.badge")
                }
                if let updated = store.lastUpdated {
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

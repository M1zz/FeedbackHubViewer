//
//  SplitRootView.swift
//  FeedbackHubViewer
//
//  Three columns, one per level of the hierarchy: which project on the left,
//  that project's 피드백 · 통계 · 진단 · 키워드 in the middle, and the selected
//  feedback on the right. The Mac's layout, and the iPad's at a regular width.
//

import SwiftUI

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
    /// sidebar; which of its sections is showing comes from the store.
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
            .hubToolbar()
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

    #if os(macOS)
    /// The Mac spreads the hub controls across the window toolbar; the touch
    /// platforms fold the same set into `HubOverflowMenu`.
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

            // A stopwatch, not a second round arrow: beside the refresh
            // button the old icon was the same glyph twice, and nothing said
            // which one ran now and which one only scheduled. Spelling the
            // title out would say it plainer still, but it widens the group
            // enough to push the toolbar into its overflow menu.
            Toggle(isOn: $store.autoRefresh) {
                Label("자동 갱신", systemImage: "timer")
            }
            .help("1분마다 자동으로 새로고침합니다")
            .toggleStyle(.button)

            RefreshButton()
        }
    }
    #endif
}

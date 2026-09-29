//
//  SplitRootView.swift
//  FeedbackHubViewer
//
//  Which project on the left, that project's 피드백 · 통계 · 진단 · 키워드 beside
//  it. The selected feedback opens as an inspector on the right only while
//  one is selected **and 피드백 is the open section** — on 리뷰 · 통계 and the
//  rest a feedback detail has nothing to do with what is on screen, so the
//  section gets the full width. Nothing sits there empty. The Mac's layout, and the
//  iPad's at a regular width (where rows push their detail instead).
//

import SwiftUI

struct SplitRootView: View {
    @EnvironmentObject private var store: FeedbackStore
    @State private var selection: Feedback.ID?
    /// 고른 피드백은 그대로 두고 오른쪽 상세 칸만 접은 상태. 다른 행을 고르면 다시 연다.
    @State private var isDetailCollapsed = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .navigationTitle("프로젝트")
        } detail: {
            contentColumn
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
        #if os(macOS)
        .inspector(isPresented: isShowingDetail) {
            if let feedback = selectedFeedback {
                FeedbackDetailView(feedback: feedback,
                                   projectLabel: store.displayName(for: feedback.projectKey))
                    .inspectorColumnWidth(min: 320, ideal: 420, max: 640)
            }
        }
        .onChange(of: selection) { isDetailCollapsed = false }
        #endif
    }

    private var selectedFeedback: Feedback? {
        guard let id = selection else { return nil }
        return store.allFeedback.first(where: { $0.id == id })
    }

    /// Open while a row is selected, 피드백 is showing, and the user hasn't
    /// folded it away.
    private var isShowingDetail: Binding<Bool> {
        Binding(get: { selectedFeedback != nil && store.projectSection == .feedback && !isDetailCollapsed },
                set: { isDetailCollapsed = !$0 })
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

        // 상세 칸을 접고 펴는 스위치. 고른 피드백이 있을 때만 뜻이 있다.
        ToolbarItem(placement: .primaryAction) {
            Button {
                isDetailCollapsed.toggle()
            } label: {
                Label(isDetailCollapsed ? "상세 펴기" : "상세 접기", systemImage: "sidebar.right")
            }
            .help("오른쪽 피드백 상세 칸을 접거나 폅니다")
            .disabled(selectedFeedback == nil || store.projectSection != .feedback)
            .keyboardShortcut("i", modifiers: [.command, .option])
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

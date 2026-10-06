//
//  SplitRootView.swift
//  FeedbackHubViewer
//
//  Which project on the left, that project's 피드백 · 통계 · 진단 · 키워드 beside
//  it. The selected feedback opens as a panel on the right only while
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
    /// 동작 줄이기를 켠 사람에게는 상세가 미끄러지지 않고 바로 나타난다.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: Self.sidebarMaxWidth)
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
        #if os(macOS)
        // 상세는 `.inspector` 가 아니라 이 칸 안에 나란히 둔다.
        //
        // `.inspector` 는 AppKit 분할 칸 하나를 더 만들고, 칸마다 제 툴바 구역과 최소
        // 너비를 따로 셈한다. 피드백을 고르면 읽음 표시 · 툴바 글자가 바뀌며 그 최소 너비가
        // 거듭 다시 계산됐고, AppKit 이 "Update Constraints in Window pass" 예외로 앱을
        // 죽였다(창을 1020pt 로 넓혀도 똑같았다). 한 칸 안의 `HStack` 은 분할 칸끼리
        // 최소 너비를 주고받을 일이 없다.
        HStack(spacing: 0) {
            // 가운데 칸에는 최소 너비를 박지 않는다. 박으면 가운데 + 상세가 사이드바를
            // 뺀 자리보다 넓어질 때 분할 칸이 사이드바를 줄여 주지 않고, 칸 전체가 창보다
            // 넓어져 가운데 정렬된 채 **양옆이 잘린다**(사이드바 왼쪽 · 상세 오른쪽).
            // 줄어드는 몫은 목록이 받는다. 얼마까지 줄지는 창의 최소 너비가 정한다.
            projectStack
                .frame(maxWidth: .infinity)
            if isShowingDetail.wrappedValue, let feedback = selectedFeedback {
                // 열고 닫을 때만 오른쪽에서 밀려 들어오고 나간다. 다른 행을 고를 때는
                // 바깥 틀이 그대로라 미끄러지지 않고 안의 내용만 바뀐다 — `.id` 는 안쪽에 둔다.
                HStack(spacing: 0) {
                    Divider()
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                        .id(feedback.id)
                }
                .frame(width: Self.detailWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // 미끄러지는 동안 상세가 목록 위로 삐져나오지 않게.
        .clipped()
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isShowingDetail.wrappedValue)
        .onChange(of: selection) { isDetailCollapsed = false }
        #else
        projectStack
        #endif
    }

    private var projectStack: some View {
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
    }

    /// 창의 최소 너비 = 가장 넓은 사이드바 + 상세 + 상세를 열어도 가운데 목록이 쓸 만한
    /// 너비(`FeedbackHubViewerApp`). 가운데 칸에 최소 너비를 박는 대신 여기서 받아 낸다.
    static let sidebarMaxWidth: CGFloat = 340
    static let detailWidth: CGFloat = 360
    static let contentComfortWidth: CGFloat = 340
    static var windowMinWidth: CGFloat { sidebarMaxWidth + detailWidth + contentComfortWidth }

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
        // 누르면 무엇을 언제 받았는지가 열린다.
        ToolbarItem(placement: .status) {
            DataStatusButton()
        }

        // 지금 보는 앱의 설계 캔버스. 없으면 만들어야 한다고 알린다.
        ToolbarItem(placement: .status) {
            DesignCanvasButton()
        }

        // 새로 온 피드백 · 진단 · 리뷰. 누르면 앱마다 무엇이 왔는지.
        ToolbarItem(placement: .primaryAction) {
            AttentionButton()
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
            .help("새 피드백·진단이 들어오면 알립니다. 앱 아이콘 뱃지는 이와 상관없이 새로 온 수를 보입니다")
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

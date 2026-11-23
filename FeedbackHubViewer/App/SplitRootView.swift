//
//  SplitRootView.swift
//  FeedbackHubViewer
//
//  왼쪽부터 기능 → 그 기능으로 본 앱 목록 → 그 앱의 화면. 할 일은 이미 모든 앱을
//  앱별로 묶은 화면이라 앱 목록 칸 없이 바로 넓게 연다.
//
//  The selected feedback opens as a panel on the right only while one is
//  selected **and 피드백 (or 할 일) is the open feature** — on 리뷰 · 통계 and
//  the rest a feedback detail has nothing to do with what is on screen, so the
//  feature gets the full width. Nothing sits there empty. The Mac's layout, and
//  the iPad's at a regular width (where rows push their detail instead).
//

import SwiftUI

struct SplitRootView: View {
    @EnvironmentObject private var store: FeedbackStore
    @State private var selection: Feedback.ID?
    /// 고른 피드백은 그대로 두고 오른쪽 상세 칸만 접은 상태. 다른 행을 고르면 다시 연다.
    @State private var isDetailCollapsed = false
    /// 피드백 상세가 없을 때 오른쪽에 고른 앱의 대시보드(`AppDashboardPanel`)를 둘까.
    @AppStorage("app-dashboard-shown") private var showsDashboard = true
    /// 동작 줄이기를 켠 사람에게는 상세가 미끄러지지 않고 바로 나타난다.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 홈(`AppGridHome`)에서는 사이드바를 걷는다 — 어딘가로 들어가면 편다. 그 사이에 손으로
    /// 접고 편 것은 다음에 홈을 드나들 때까지 그대로 둔다.
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    /// 홈에서 누른 카드의 자리 — 홈과 앱 화면이 이 점을 축으로 커지고 줄어든다.
    @State private var zoomAnchor: UnitPoint = .center
    /// 다가오기가 끝난 화면이 홈인가. `store.showsHome` 과 다른 동안이 "막 바뀐 순간" 이다 —
    /// 그때 새 화면은 살짝 작게(홈으로 올 때는 살짝 크게) · 투명하게 서 있다가 제자리로 온다.
    @State private var arrivedHome = true

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FeatureListView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: Self.sidebarMaxWidth)
        } detail: {
            // 홈 ↔ 앱 화면은 **그 자리에서 바로** 바뀌고, 새로 선 화면만 누른 카드 자리에서 다가온다.
            //
            // 예전에는 둘을 `.transition` 으로 바꿨다 — 나가는 화면을 애니메이션이 끝날 때까지
            // 살려 두는 방식이다. 그 화면 안에는 `NavigationStack` · 툴바 · AppKit 컨트롤
            // (세그먼트 · 진행 표시 · 글 상자)이 있고, 같은 순간 분할 칸은 사이드바를 펴느라 너비를
            // 다시 셈한다. 그 둘이 겹치면 AttributeGraph 가 "precondition failure: invalid type
            // ID: 0" 으로 앱을 죽였다. 지금은 화면을 넣고 빼는 데에는 애니메이션이 없고, 이미 선
            // 화면의 크기 · 투명도만 움직인다 — 그래프에서 빠지는 중인 것을 건드릴 일이 없다.
            Group {
                if store.showsHome {
                    home
                } else {
                    contentColumn
                }
            }
            .scaleEffect(arrivalScale, anchor: zoomAnchor)
            .opacity(hasArrived ? 1 : 0)
        }
        .onChange(of: store.showsHome) { _, isHome in
            // 사이드바는 애니메이션 없이 — 분할 칸의 너비 셈과 화면 바꾸기가 한 박자에 끝나게.
            columnVisibility = isHome ? .detailOnly : .all
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.34)) {
                arrivedHome = isHome
            }
        }
        // 사이드바에서 칸이나 앱을 고르면 홈에서 나간다. 같은 칸을 다시 누른 것은 줄의 단추가
        // 직접 끈다(`FeatureListView`).
        .onChange(of: store.projectSection) { store.showsHome = false }
        .onChange(of: store.focusedApp) { store.showsHome = false }
        // The app screen sits beside the app list here rather than on top of
        // it, so cross-screen links re-scope the column instead of pushing
        // (see `FeedbackStore.open(project:section:)`).
        .task { store.usesStackNavigation = false }
        .task(id: store.focusedApp) {
            if let app = store.focusedApp { store.selectedProject = app }
        }
        #if os(macOS)
        .toolbar { macToolbarContent }
        #endif
    }

    private var hasArrived: Bool { arrivedHome == store.showsHome }

    private var arrivalScale: CGFloat {
        guard !hasArrived, !reduceMotion else { return 1 }
        return store.showsHome ? 1.05 : 0.94
    }

    /// 첫 화면 — 모든 앱의 카드. 아이패드는 칸마다 제 툴바가 있어야 사이드바 단추가 선다.
    private var home: some View {
        #if os(macOS)
        AppGridHome(zoomAnchor: $zoomAnchor)
        #else
        NavigationStack {
            AppGridHome(zoomAnchor: $zoomAnchor)
                .navigationBarTitleDisplayMode(.inline)
                .hubToolbar()
        }
        #endif
    }

    /// 고른 기능의 앱 목록과 고른 앱의 화면. 기능은 사이드바가, 앱은 앱 목록이 정하고
    /// 둘 다 가게(`store`)에 적힌다.
    private var contentColumn: some View {
        HStack(spacing: 0) {
            // 앱 하나로 보는 중이면 앱 목록 칸은 걷는다 — 앱은 사이드바 맨 위에서 이미 골랐다.
            if store.projectSection.usesAppList && store.focusedApp == nil {
                AppListView(section: store.projectSection)
                    .frame(width: Self.appListWidth)
                Divider()
            }
            featureColumn
        }
    }

    private var featureColumn: some View {
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
            mainContent
                .frame(maxWidth: .infinity)
            if isShowingDetail.wrappedValue, let feedback = selectedFeedback {
                // 열고 닫을 때만 오른쪽에서 밀려 들어오고 나간다. 다른 행을 고를 때는
                // 바깥 틀이 그대로라 미끄러지지 않고 안의 내용만 바뀐다 — `.id` 는 안쪽에 둔다.
                HStack(spacing: 0) {
                    Divider()
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                        .id(feedback.id)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                isDetailCollapsed = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .help("상세 칸 닫기 (⌥⌘I)")
                            .keyboardShortcut("i", modifiers: [.command, .option])
                        }
                }
                .frame(width: Self.detailWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if showsDashboardPanel {
                HStack(spacing: 0) {
                    Divider()
                    AppDashboardPanel(project: dashboardProject) { showsDashboard = false }
                }
                .frame(width: Self.detailWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // 미끄러지는 동안 상세가 목록 위로 삐져나오지 않게.
        .clipped()
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isShowingDetail.wrappedValue)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsDashboardPanel)
        .onChange(of: selection) { isDetailCollapsed = false }
        #else
        mainContent
        #endif
    }

    /// "전체 앱"이면 가운데에 모든 앱 대시보드, 아니면 고른 앱의 칸. 전체 앱일 때만 맨 위에
    /// 대시보드 · 모아보기 전환이 선다.
    private var mainContent: some View {
        Group {
            if isAllAppsDashboard {
                AppDashboardPanel(project: nil)
            } else {
                projectStack
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isAllApps {
                Picker("전체 앱 보기", selection: $store.showsAllAppsDashboard) {
                    Text("대시보드").tag(true)
                    Text("\(store.projectSection.rawValue) 모아보기").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        // 사이드바에서 칸을 고르면 그 칸을 보러 온 것 — 대시보드는 칸과 상관없이 같으니 모아보기로.
        .onChange(of: store.projectSection) { store.showsAllAppsDashboard = false }
    }

    private var projectStack: some View {
        NavigationStack(path: $store.path) {
            ProjectSectionView(project: store.selectedProject, section: store.projectSection, selection: $selection)
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

    /// 창의 최소 너비 = 가장 넓은 기능 사이드바 + 앱 목록 + 상세 + 상세를 열어도 가운데
    /// 목록이 쓸 만한 너비(`FeedbackHubViewerApp`). 가운데 칸에 최소 너비를 박는 대신 여기서
    /// 받아 낸다.
    static let sidebarMaxWidth: CGFloat = 240
    static let appListWidth: CGFloat = 250
    static let detailWidth: CGFloat = 360
    static let contentComfortWidth: CGFloat = 320
    static var windowMinWidth: CGFloat { sidebarMaxWidth + appListWidth + detailWidth + contentComfortWidth }

    private var selectedFeedback: Feedback? {
        guard let id = selection else { return nil }
        return store.allFeedback.first(where: { $0.id == id })
    }

    /// 앱을 고르는 칸에서 "전체 앱"을 골랐나.
    private var isAllApps: Bool {
        store.projectSection.usesAppList && store.focusedApp == nil && store.selectedProject == nil
    }

    /// 가운데에 전체 대시보드를 세울까.
    private var isAllAppsDashboard: Bool {
        isAllApps && store.showsAllAppsDashboard
    }

    /// 오른쪽 대시보드를 둘까 — 앱 하나를 골랐고 접지 않았을 때. 전체 앱은 가운데가 대시보드다.
    private var showsDashboardPanel: Bool {
        showsDashboard && store.projectSection.usesAppList && dashboardProject != nil
    }

    /// 오른쪽 대시보드가 볼 앱. nil 이면 세우지 않는다.
    private var dashboardProject: String? {
        guard let project = store.selectedProject, project != Feedback.unclassifiedProject else { return nil }
        return project
    }

    /// Open while a row is selected, 피드백 is showing, and the user hasn't
    /// folded it away.
    private var isShowingDetail: Binding<Bool> {
        Binding(get: { selectedFeedback != nil && store.projectSection.showsFeedbackDetail
                        && !isDetailCollapsed && !isAllAppsDashboard },
                set: { isDetailCollapsed = !$0 })
    }

    #if os(macOS)
    /// The Mac spreads the hub controls across the window toolbar; the touch
    /// platforms fold the same set into `HubOverflowMenu`.
    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        // 어느 환경의 데이터인가 — 창이 몇 개든 늘 같은 자리에.
        ToolbarItem(placement: .navigation) {
            EnvironmentBadge()
        }

        // 모든 앱을 카드로 편 첫 화면으로.
        ToolbarItem(placement: .navigation) {
            Button {
                store.showsHome = true
            } label: {
                Label("홈", systemImage: "square.grid.2x2")
            }
            .help("모든 앱 한눈에 (⇧⌘H)")
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(store.showsHome)
        }

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

        // 오른쪽 앱 대시보드를 접고 편다. 접은 채로는 단추로만 다시 연다.
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showsDashboard) {
                Label("앱 대시보드", systemImage: "rectangle.righthalf.inset.filled")
            }
            .help(showsDashboard ? "오른쪽 앱 대시보드 접기" : "오른쪽 앱 대시보드 펴기")
        }

        // 알림 · 자동 갱신 스위치는 설정(⌘,)으로, 상세 접기는 상세 칸 머리로 옮겼다 —
        // 툴바에는 날마다 누르는 것만.
        ToolbarItemGroup(placement: .primaryAction) {
            // 이름까지 보인다 — 화면마다 받는 것이 달라서 "리뷰 새로고침" · "차트 순위 새로고침"
            // 처럼 무엇을 받는지가 단추에 적혀 있어야 한다. 전부는 ⇧⌘R · 데이터 상태 칸.
            RefreshButton()
                .labelStyle(.titleAndIcon)
        }
    }
    #endif
}

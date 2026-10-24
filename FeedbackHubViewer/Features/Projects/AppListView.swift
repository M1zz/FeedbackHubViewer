//
//  AppListView.swift
//  FeedbackHubViewer
//
//  고른 기능 하나로 본 앱 목록. 줄마다 그 기능이 그 앱에 대해 하는 한마디가 붙는다 —
//  피드백이면 건수와 안 읽음, 진단이면 최근 7일, 릴리즈면 건강 판정, 통계면 주 지표와
//  14일 모양. 그래서 "어느 앱을 열어 봐야 하나" 가 목록 한 장에서 읽힌다.
//
//  맨 위의 "전체 앱" 은 그 기능의 앱 모아보기(앱별 순위 · 묶음)다.
//
//  맥 · 아이패드에서는 기능 사이드바 옆의 칸(고르면 오른쪽이 바뀐다),
//  아이폰에서는 기능을 누르면 밀려 들어오는 화면(누르면 다시 민다).
//

import SwiftUI

struct AppListView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    /// 본 뒤 바뀐 앱의 "새" 뱃지가 따라 움직이게.
    @ObservedObject private var changes = SectionChanges.shared
    /// 마케팅 칸의 "올렸나요?" 뱃지.
    @ObservedObject private var marketing = MarketingStore.shared
    /// 질문 찾기 칸의 새 질문 뱃지.
    @ObservedObject private var leadStore = LeadStore.shared
    /// 맥 전용 앱처럼 키워드 칸이 못 찾은 앱의 아이콘.
    @ObservedObject private var icons = StoreIcons.shared
    /// App Store 와 손수 이을 앱(오른쪽 클릭 메뉴).
    @State private var linking: String?
    let section: FeedbackStore.ProjectSection
    /// 아이폰은 고르면 민다. 맥 · 아이패드는 `store.selectedProject` 만 바꾼다.
    var pushes = false

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)
        let traffic = section == .stats ? store.trafficByProject : [:]
        // 릴리즈는 빨강이 먼저 와야 그 기능의 목록이다. 나머지는 MAU 순 그대로 — 기능을
        // 바꿔도 앱 자리가 그대로여야 눈이 앱을 다시 찾지 않는다.
        let entries = section == .release
            ? store.redFirst(store.projectCounts, key: { $0.key })
            : store.projectCounts

        List {
            Section {
                row(project: nil, metrics: metrics, traffic: store.overallTraffic)
            }

            Section {
                ForEach(entries, id: \.key) { entry in
                    row(project: entry.key, metrics: metrics, traffic: traffic[entry.key] ?? .none)
                        .contextMenu { menu(for: entry.key) }
                        .swipeActions(edge: .trailing) {
                            Button {
                                store.hideProject(entry.key)
                            } label: {
                                Label("숨기기", systemImage: "eye.slash")
                            }
                            .tint(.gray)
                        }
                }
            } header: {
                Text("앱 \(entries.count)개")
            }

            if !store.hiddenProjectEntries.isEmpty {
                hiddenSection
            }
        }
        .hubSidebarListStyle()
        .modifier(PushedTitle(title: section.rawValue, isPushed: pushes))
        .task(id: entries.count) { await icons.resolve(entries.map(\.key), keywords: keywords) }
        .sheet(item: Binding(get: { linking.map(LinkTarget.init) }, set: { linking = $0?.id })) { target in
            StoreLinkSheet(project: target.id) { linking = nil }
                .environmentObject(store)
                .environmentObject(keywords)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(project: String?, metrics: SectionMetrics, traffic: FeedbackStore.Traffic) -> some View {
        let isSelected = !pushes && store.selectedProject == project
        let content = AppRow(
            name: project.map(store.displayName(for:)) ?? "전체 앱",
            iconURL: project.flatMap { icons.url(for: $0, keywords: keywords) },
            systemImage: project == nil ? "square.grid.2x2"
                : project == Feedback.unclassifiedProject ? "questionmark.folder" : "app.dashed",
            tint: project == nil ? .purple
                : project == Feedback.unclassifiedProject ? .secondary : .accentColor,
            detail: metrics.label(section, project: project),
            isAlarming: metrics.isAlarming(section, project: project),
            badge: metrics.badge(section, project: project),
            release: section == .release ? project.flatMap(store.releaseLevel(for:)) : nil,
            stats: section == .stats ? StatsGlance(traffic: traffic, cycle: project.flatMap(store.usageCycle(for:))) : nil,
            isSelected: isSelected)

        if pushes {
            NavigationLink(value: FeedbackStore.ProjectRoute(project: project, section: section)) { content }
        } else {
            Button { store.selectedProject = project } label: { content }
                .buttonStyle(.plain)
                .listRowBackground(Rectangle().fill(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear)))
        }
    }

    @ViewBuilder
    private func menu(for project: String) -> some View {
        if section == .feedback {
            Button {
                store.markAllRead(project: project)
            } label: {
                Label("모두 읽음으로 표시", systemImage: "envelope.open")
            }
        }
        Button {
            linking = project
        } label: {
            Label(keywords.trackId(for: project) == nil ? "App Store 링크로 잇기…" : "App Store 링크 바꾸기…",
                  systemImage: "link")
        }
        Button {
            store.hideProject(project)
        } label: {
            Label("이 앱 숨기기", systemImage: "eye.slash")
        }
    }

    /// 숨긴 앱을 되돌리는 자리. 숨기기가 이 목록에 있으니 되돌리기도 이 목록에 있어야 한다.
    private var hiddenSection: some View {
        Section {
            ForEach(store.hiddenProjectEntries, id: \.key) { entry in
                HStack(spacing: 8) {
                    Text(entry.displayName)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("다시 보기") { store.showProject(entry.key) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .font(.callout)
            }
            if store.hiddenProjectEntries.count > 1 {
                Button {
                    store.showAllProjects()
                } label: {
                    Label("모두 다시 보기", systemImage: "eye")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("숨긴 앱")
        } footer: {
            Text("이 기기에서만 가려집니다. 허브의 레코드는 그대로입니다.")
                .font(.caption)
        }
    }
}

/// 밀려 들어온 화면(아이폰)에서만 제목을 단다. 맥 · 아이패드에서는 이 칸이 옆 화면과 한 창에
/// 있어서, 여기서 제목을 달면 고른 앱 이름 대신 기능 이름이 창 제목을 차지한다.
private struct PushedTitle: ViewModifier {
    let title: String
    let isPushed: Bool

    func body(content: Content) -> some View {
        if isPushed {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } else {
            content
        }
    }
}

/// 통계 기능에서만 줄 오른쪽에 서는 것: 사용 주기에 맞는 주 지표와 14일 모양.
struct StatsGlance {
    let traffic: FeedbackStore.Traffic
    /// 이 앱의 사용 주기. 안 정했으면(또는 전체 앱이면) MAU.
    let cycle: UsageCycle?

    /// 매일 DAU(어제), 매주 WAU(7일), 가끔 · 안 정함 MAU.
    var metric: (name: String, value: Int) {
        switch cycle {
        case .daily: ("DAU", traffic.dauYesterday)
        case .weekly: ("WAU", traffic.activeInstalls7)
        case .occasional, nil: ("MAU", traffic.mau)
        }
    }
}

/// 앱 한 줄. 두 줄이고 말은 평범하게 — 이름, 그리고 이 기능이 이 앱에 대해 하는 한마디.
private struct AppRow: View {
    let name: String
    var iconURL: URL?
    let systemImage: String
    let tint: Color
    let detail: String
    let isAlarming: Bool
    let badge: SectionMetrics.Badge?
    let release: ReleaseHealth.Level?
    let stats: StatsGlance?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: iconURL, symbol: systemImage, tint: tint, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    ReleaseDot(level: release)
                }
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isAlarming ? Color.red : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let badge {
                CountBadge(count: badge.count, systemImage: badge.systemImage,
                           tint: badge.tint, name: badge.name)
            }
            if let stats, stats.traffic.hasUsageData {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(stats.metric.name) \(AppFormat.count(stats.metric.value))")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(stats.metric.value > 0 ? .primary : .secondary)
                    if stats.traffic.totalEvents > 0 {
                        Sparkline(points: stats.traffic.sparkline)
                            .frame(width: 52, height: 16)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 시트에 넘길 앱 키.
private struct LinkTarget: Identifiable {
    let id: String
}

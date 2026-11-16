//
//  AppDashboardPanel.swift
//  FeedbackHubViewer
//
//  맥의 오른쪽 칸 — 고른 앱 하나를 한눈에. 가운데에서 리뷰를 보든 통계를 보든, 오른쪽에는
//  그 앱의 모든 칸이 한 장씩 카드로 서 있다. 카드는 그 칸의 한마디(`SectionMetrics.label`)와
//  뱃지라, 칸을 옮겨 다니지 않고도 "이 앱은 지금 어떤가" 가 보인다. 누르면 그 칸으로 간다.
//
//  손볼 것(뱃지 · 경고)이 있는 카드가 맨 위에 모이고, 나머지는 기능 목록 차례 그대로.
//  앱 목록에서 "전체" 를 고르면 같은 카드가 모든 앱의 합으로 서고, 손볼 것이 많은 앱이 위에 붙는다.
//  피드백 상세가 열리면 그 자리를 내준다(`SplitRootView`).
//

import SwiftUI

struct AppDashboardPanel: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var icons = StoreIcons.shared
    /// nil 이면 전체 앱.
    let project: String?
    let onClose: () -> Void

    private struct Tile: Identifiable {
        let section: FeedbackStore.ProjectSection
        let label: String
        let badge: SectionMetrics.Badge?
        let isAlarming: Bool
        var id: String { section.rawValue }
        var needsLook: Bool { badge != nil || isAlarming }
    }

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases,
                                     design: design, charts: charts, news: news)
        let tiles = AppScopedSections.groups().flatMap(\.sections).flatMap(\.members).map { section in
            Tile(section: section, label: metrics.label(section, project: project),
                 badge: metrics.badge(section, project: project),
                 isAlarming: metrics.isAlarming(section, project: project))
        }
        let urgent = tiles.filter(\.needsLook)
        let rest = tiles.filter { !$0.needsLook }
        let busyApps = project == nil ? Self.busyApps(tiles: tiles, metrics: metrics) : []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !busyApps.isEmpty {
                    appsBlock(busyApps)
                }
                if !urgent.isEmpty {
                    block("손볼 것", tiles: urgent)
                } else {
                    Label("지금 손볼 것 없음", systemImage: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                }
                block("한눈에", tiles: rest)
            }
            .padding(14)
        }
        .background(.background)
        .task(id: project) {
            await icons.resolve(project.map { [$0] } ?? SectionMetrics.keywordProjects(store), keywords: keywords)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let project {
                AppIcon(url: icons.url(for: project, keywords: keywords), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName(for: project))
                        .font(.headline)
                        .lineLimit(1)
                    if let platform = store.platformTag(for: project) {
                        Text(platform)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("전체 앱")
                        .font(.headline)
                    Text("앱 \(SectionMetrics.keywordProjects(store).count)개")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("대시보드 닫기 (⌥⌘I)")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private func block(_ title: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(tiles) { tile in
                    Button {
                        store.open(project: project, section: tile.section)
                    } label: {
                        card(tile)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 전체일 때 — 손볼 것이 있는 앱. 칸마다 뱃지 수를 더한 것이 큰 앱부터 다섯.
    private struct BusyApp: Identifiable {
        let project: String
        let count: Int
        let names: [String]
        var id: String { project }
    }

    private static func busyApps(tiles: [Tile], metrics: SectionMetrics) -> [BusyApp] {
        let sections = tiles.map(\.section)
        return SectionMetrics.keywordProjects(metrics.store).compactMap { app in
            let hits = sections.compactMap { section -> (String, Int)? in
                guard let badge = metrics.badge(section, project: app) else { return nil }
                return (section.rawValue, badge.count)
            }
            let total = hits.reduce(0) { $0 + $1.1 }
            return total > 0 ? BusyApp(project: app, count: total, names: hits.map(\.0)) : nil
        }
        .sorted { ($0.count, $1.project) > ($1.count, $0.project) }
        .prefix(5)
        .map { $0 }
    }

    private func appsBlock(_ apps: [BusyApp]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("손볼 앱")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(apps) { app in
                    Button {
                        store.open(project: app.project, section: nil)
                    } label: {
                        HStack(spacing: 8) {
                            AppIcon(url: icons.url(for: app.project, keywords: keywords), size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(store.displayName(for: app.project))
                                    .font(.body)
                                    .lineLimit(1)
                                Text(app.names.joined(separator: " · "))
                                    .font(.hubCaption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("\(app.count)")
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.45)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ tile: Tile) -> some View {
        let isCurrent = store.projectSection == tile.section
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: tile.section.systemImage)
                    .foregroundStyle(tile.isAlarming ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                Text(tile.section.rawValue)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge = tile.badge {
                    CountBadge(count: badge.count, systemImage: badge.systemImage,
                               tint: badge.tint, name: badge.name)
                }
            }
            Text(tile.badge?.action ?? tile.label)
                .font(.hubCaption.monospacedDigit())
                .foregroundStyle(tile.isAlarming ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(isCurrent ? 0.9 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }
}

//
//  AppDashboardPanel.swift
//  FeedbackHubViewer
//
//  고른 앱 하나를 한눈에 — 맥의 오른쪽 칸. "전체 앱"이면 가운데 넓은 칸 전체가 이 대시보드다. 가운데에서 리뷰를 보든 통계를 보든, 오른쪽에는
//  그 앱의 모든 칸이 한 장씩 카드로 서 있다. 카드는 그 칸의 한마디(`SectionMetrics.label`)와
//  뱃지라, 칸을 옮겨 다니지 않고도 "이 앱은 지금 어떤가" 가 보인다. 누르면 그 칸으로 간다.
//
//  손볼 것(뱃지 · 경고)이 있는 카드가 맨 위에 모이고, 나머지는 기능 목록 차례 그대로.
//  앱 목록에서 "전체 앱"을 고르면 같은 카드가 모든 앱의 합으로 서고, 그 아래 모든 앱이 카드로
//  선다(손볼 것이 많은 앱부터). 카드 열 수는 칸 너비를 따른다 — 좁은 오른쪽 칸이면 두 줄.
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
    /// nil 이면 닫기 단추가 없다(가운데에 선 전체 대시보드).
    var onClose: (() -> Void)? = nil

    private struct Tile: Identifiable {
        let section: FeedbackStore.ProjectSection
        let label: String
        let badge: SectionMetrics.Badge?
        let isAlarming: Bool
        var id: String { section.rawValue }
        var needsLook: Bool { badge != nil || isAlarming }
    }

    var body: some View {
        // 앱 하나면 브리핑(`AppBriefing`) — 문제부터, 그 안의 것과 함께. 칸을 다 세우는 아래 모양은
        // 전체 앱일 때만 쓴다.
        if let project {
            AppBriefing(project: project, onClose: onClose)
        } else {
            overview
        }
    }

    private var overview: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases,
                                     design: design, charts: charts, news: news)
        let tiles = AppScopedSections.groups().flatMap(\.sections).flatMap(\.members).map { section in
            Tile(section: section, label: metrics.label(section, project: project),
                 badge: metrics.badge(section, project: project),
                 isAlarming: metrics.isAlarming(section, project: project))
        }
        let urgent = tiles.filter(\.needsLook)
        let rest = tiles.filter { !$0.needsLook }
        let apps = project == nil ? Self.apps(tiles: tiles, metrics: metrics) : []

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !urgent.isEmpty {
                    block("손볼 것", tiles: urgent)
                } else {
                    Label("지금 손볼 것 없음", systemImage: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                }
                block("한눈에", tiles: rest)
                if !apps.isEmpty {
                    appsBlock(apps)
                }
            }
            .padding(project == nil ? 20 : 14)
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
            if let onClose {
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
    }

    private func block(_ title: String, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
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

    /// 전체일 때 — 모든 앱. 칸마다 뱃지 수를 더한 것이 큰 앱부터, 같으면 앱 목록 차례(MAU).
    private struct AppTile: Identifiable {
        let project: String
        let count: Int
        let names: [String]
        var id: String { project }
    }

    private static func apps(tiles: [Tile], metrics: SectionMetrics) -> [AppTile] {
        let sections = tiles.map(\.section)
        return SectionMetrics.keywordProjects(metrics.store).enumerated().map { index, app in
            let hits = sections.compactMap { section -> (String, Int)? in
                guard let badge = metrics.badge(section, project: app) else { return nil }
                return (section.rawValue, badge.count)
            }
            return (index, AppTile(project: app, count: hits.reduce(0) { $0 + $1.1 }, names: hits.map(\.0)))
        }
        .sorted { ($0.1.count, -$0.0) > ($1.1.count, -$1.0) }
        .map(\.1)
    }

    private func appsBlock(_ apps: [AppTile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("앱 \(apps.count)개")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                ForEach(apps) { app in
                    Button {
                        store.open(project: app.project, section: nil)
                    } label: {
                        HStack(spacing: 8) {
                            AppIcon(url: icons.url(for: app.project, keywords: keywords), size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(store.displayName(for: app.project))
                                    .font(.body)
                                    .lineLimit(1)
                                Text(app.names.isEmpty ? "손볼 것 없음" : app.names.joined(separator: " · "))
                                    .font(.hubCaption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if app.count > 0 {
                                Text("\(app.count)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.45)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func card(_ tile: Tile) -> some View {
        let isCurrent = project != nil && store.projectSection == tile.section
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

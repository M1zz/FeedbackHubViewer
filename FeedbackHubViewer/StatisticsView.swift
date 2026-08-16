//
//  StatisticsView.swift
//  FeedbackHubViewer
//
//  A statistics dashboard across all projects: headline tiles, a daily trend,
//  and breakdowns by rating, project, feedback type, and app version.
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var store: FeedbackStore

    #if os(macOS)
    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    private let sectionSpacing: CGFloat = 20
    private let contentPadding: CGFloat = 16
    private let trendHeight: CGFloat = 180
    private let breakdownHeight: CGFloat = 160
    #else
    // Two even columns beat an adaptive grid on a phone: four tiles land as a
    // tidy 2×2 instead of 3 + 1 orphan.
    private let tileColumns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
    private let sectionSpacing: CGFloat = 14
    private let contentPadding: CGFloat = 12
    private let trendHeight: CGFloat = 150
    private let breakdownHeight: CGFloat = 132
    #endif

    var body: some View {
        Group {
            if store.errorMessage != nil {
                ContentUnavailableView {
                    Label("불러올 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.errorMessage ?? "")
                }
            } else if store.allFeedback.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "표시할 통계가 없습니다",
                    systemImage: "chart.bar",
                    description: Text(store.noticeMessage ?? "아직 수집된 피드백이 없습니다.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        scopePicker
                        tiles
                        trendCard
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) { ratingCard; typeCard }
                            VStack(spacing: sectionSpacing) { ratingCard; typeCard }
                        }
                        projectCard
                        if !store.stats.versionCounts.isEmpty { versionCard }
                    }
                    .padding(contentPadding)
                }
            }
        }
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty {
                ProgressView("불러오는 중…")
            }
        }
        .navigationTitle("통계")
        .hubNavigationSubtitle(subtitle)
    }

    private var subtitle: String {
        if let key = store.selectedProject {
            return "프로젝트: \(store.displayName(for: key)) · \(store.scopedFeedback.count)건"
        }
        return "전체 \(store.allFeedback.count)건 / \(store.availableProjects.count)개 프로젝트"
    }

    // MARK: - Project scope

    private var scopePicker: some View {
        HStack(spacing: 8) {
            Picker("프로젝트", selection: $store.selectedProject) {
                Text("전체 프로젝트").tag(String?.none)
                ForEach(store.projectCounts, id: \.key) { entry in
                    Text(store.displayName(for: entry.key)).tag(String?.some(entry.key))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer(minLength: 4)
            EnvironmentBadge()
        }
    }

    // MARK: - Headline tiles

    private var tiles: some View {
        let s = store.stats
        return LazyVGrid(columns: tileColumns, spacing: 10) {
            StatTile(title: "전체 피드백", value: "\(s.total)", unit: "건",
                     systemImage: "tray.full", tint: .accentColor)
            StatTile(title: "평균 별점",
                     value: s.averageRating.map { String(format: "%.2f", $0) } ?? "—",
                     unit: s.averageRating != nil ? "/ 5" : "",
                     systemImage: "star.fill", tint: .yellow)
            StatTile(title: "최근 7일", value: "\(s.last7Days)", unit: "건",
                     systemImage: "clock", tint: .blue)
            StatTile(title: "프로젝트", value: "\(store.availableProjects.count)", unit: "개",
                     systemImage: "square.grid.2x2", tint: .purple)
        }
    }

    // MARK: - Cards

    private var trendCard: some View {
        let daily = store.dailyCounts(days: 30)
        return Card(title: "최근 30일 추이", systemImage: "calendar") {
            Chart(daily, id: \.date) { entry in
                BarMark(
                    x: .value("날짜", entry.date, unit: .day),
                    y: .value("건수", entry.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: trendHeight)
        }
    }

    private var ratingCard: some View {
        Card(title: "별점 분포", systemImage: "star.leadinghalf.filled") {
            if store.stats.averageRating == nil {
                emptyNote("별점 데이터가 없습니다.")
            } else {
                Chart(store.stats.ratingCounts, id: \.rating) { entry in
                    BarMark(
                        x: .value("건수", entry.count),
                        y: .value("별점", "\(entry.rating)★")
                    )
                    .foregroundStyle(.yellow.gradient)
                    .annotation(position: .trailing) {
                        Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: breakdownHeight)
            }
        }
    }

    private var typeCard: some View {
        let types = store.typeCounts
        return Card(title: "유형별", systemImage: "tag") {
            if types.count <= 1 && types.first?.type == "기타" {
                emptyNote("유형 데이터가 없습니다.")
            } else {
                Chart(types, id: \.type) { entry in
                    BarMark(
                        x: .value("건수", entry.count),
                        y: .value("유형", entry.type)
                    )
                    .foregroundStyle(Color.teal.gradient)
                    .annotation(position: .trailing) {
                        Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: breakdownHeight)
            }
        }
    }

    private var projectCard: some View {
        let projects = store.projectSummaries
        return Card(title: "프로젝트별 건수", systemImage: "square.grid.2x2") {
            Chart(projects) { p in
                BarMark(
                    x: .value("건수", p.count),
                    y: .value("프로젝트", p.displayName)
                )
                .foregroundStyle(p.isUnclassified ? Color.gray.gradient : Color.accentColor.gradient)
                .annotation(position: .trailing) {
                    Text("\(p.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: max(110, CGFloat(projects.count) * 32))
        }
    }

    private var versionCard: some View {
        let versions = Array(store.stats.versionCounts.prefix(12))
        return Card(title: "버전별 건수", systemImage: "app.badge") {
            Chart(versions, id: \.version) { entry in
                BarMark(
                    x: .value("버전", "v\(entry.version)"),
                    y: .value("건수", entry.count)
                )
                .foregroundStyle(Color.indigo.gradient)
            }
            .frame(height: breakdownHeight)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: breakdownHeight * 0.6)
    }
}

// MARK: - Building blocks

private struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    #if os(macOS)
    private let tilePadding: CGFloat = 14
    private let valueFont: Font = .system(.title, design: .rounded).weight(.semibold)
    #else
    private let tilePadding: CGFloat = 10
    private let valueFont: Font = .system(.title2, design: .rounded).weight(.semibold)
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tilePadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    #if os(macOS)
    private let cardPadding: CGFloat = 16
    #else
    private let cardPadding: CGFloat = 12
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

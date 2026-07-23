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
                    VStack(alignment: .leading, spacing: 20) {
                        scopePicker
                        tiles
                        trendCard
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) { ratingCard; typeCard }
                            VStack(spacing: 16) { ratingCard; typeCard }
                        }
                        projectCard
                        if !store.stats.versionCounts.isEmpty { versionCard }
                    }
                    .padding(16)
                }
            }
        }
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty {
                ProgressView("불러오는 중…")
            }
        }
        .navigationTitle("통계")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        if let key = store.selectedProject {
            return "프로젝트: \(store.displayName(for: key)) · \(store.scopedFeedback.count)건"
        }
        return "전체 \(store.allFeedback.count)건 / \(store.availableProjects.count)개 프로젝트"
    }

    // MARK: - Project scope

    private var scopePicker: some View {
        Picker("프로젝트", selection: $store.selectedProject) {
            Text("전체 프로젝트").tag(String?.none)
            ForEach(store.projectCounts, id: \.key) { entry in
                Text(store.displayName(for: entry.key)).tag(String?.some(entry.key))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    // MARK: - Headline tiles

    private var tiles: some View {
        let s = store.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
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
            .frame(height: 180)
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
                .frame(height: 160)
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
                .frame(height: 160)
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
            .frame(height: max(120, CGFloat(projects.count) * 34))
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
            .frame(height: 160)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Building blocks

private struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

private struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

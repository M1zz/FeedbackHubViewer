//
//  ProjectOverviewView.swift
//  FeedbackHubViewer
//
//  A grid of project cards. Each card summarizes one LeeoKit project's
//  feedback — total count (badge), average rating, and how many arrived in the
//  last 7 days. Tapping a card filters to that project and switches to the
//  list view.
//

import SwiftUI

struct ProjectOverviewView: View {
    @EnvironmentObject private var store: FeedbackStore

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        Group {
            if store.errorMessage != nil {
                ContentUnavailableView {
                    Label("불러올 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.errorMessage ?? "")
                }
            } else if store.projectSummaries.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "표시할 프로젝트가 없습니다",
                    systemImage: "square.grid.2x2",
                    description: Text(store.noticeMessage ?? "아직 수집된 피드백이 없습니다.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.projectSummaries) { summary in
                            ProjectCard(summary: summary) {
                                store.selectedProject = summary.project
                                store.viewMode = .list
                            }
                        }
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
        .navigationTitle("프로젝트 개요")
        .navigationSubtitle("\(store.projectSummaries.count)개 프로젝트 / 전체 \(store.allFeedback.count)건")
    }
}

private struct ProjectCard: View {
    let summary: FeedbackStore.ProjectSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: summary.isUnclassified ? "questionmark.folder" : "app.dashed")
                        .font(.title3)
                        .foregroundStyle(summary.isUnclassified ? Color.secondary : Color.accentColor)
                    Text(summary.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    CountBadge(count: summary.count)
                }

                Divider()

                HStack(spacing: 16) {
                    Metric(systemImage: "star.fill",
                           tint: .yellow,
                           value: summary.averageRating.map { String(format: "%.1f", $0) } ?? "—",
                           label: "평균")
                    Metric(systemImage: "clock",
                           tint: .blue,
                           value: "\(summary.last7Days)",
                           label: "최근 7일")
                }

                if let latest = summary.latest {
                    Text("마지막: \(latest.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("\(summary.displayName) 피드백 \(summary.count)건 보기")
    }
}

private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor, in: Capsule())
    }
}

private struct Metric: View {
    let systemImage: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.bold().monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

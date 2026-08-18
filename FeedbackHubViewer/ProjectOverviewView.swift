//
//  ProjectOverviewView.swift
//  FeedbackHubViewer
//
//  A grid of project cards. Each card summarizes one LeeoKit project's
//  feedback — total count (badge), unread count, average rating, and how many
//  arrived in the last 7 days. Tapping a card pushes that project's feedback
//  list; a row in the list pushes the feedback itself.
//

import SwiftUI

struct ProjectOverviewView: View {
    @EnvironmentObject private var store: FeedbackStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    #if os(macOS)
    private let contentSpacing: CGFloat = 16
    private let contentPadding: CGFloat = 16
    #else
    private let contentSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 12
    #endif

    /// Full-width cards on a phone, a grid everywhere else. Two-up cards on a
    /// phone are ~190pt wide, which is not enough for an app name plus its
    /// badges — names ended up broken mid-word ("ClipKeyb / oard").
    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]
        #else
        isCompact
            ? [GridItem(.flexible(), spacing: 10)]
            : [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 10)]
        #endif
    }

    /// The compact layout has no sidebar, so the overview carries the headline
    /// numbers and a preview of the newest feedback itself.
    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned above the content so the environment and refresh time stay
            // visible even when the body is an error or empty state.
            if isCompact {
                StatusRow()
                    .padding(.horizontal, contentPadding)
                    .padding(.bottom, 8)
            }
            content
        }
        .navigationTitle("프로젝트 개요")
        .hubNavigationSubtitle("\(store.projectSummaries.count)개 프로젝트 / 전체 \(store.allFeedback.count)건")
    }

    @ViewBuilder
    private var content: some View {
        Group {
            // An error only takes the screen when there is nothing to show;
            // with a cache on disk the last known numbers stay up.
            if store.errorMessage != nil && !store.hasContent {
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
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        if isCompact {
                            HeadlineStrip()
                        }

                        LazyVGrid(columns: columns, spacing: contentSpacing) {
                            ForEach(store.projectSummaries) { summary in
                                ProjectCard(summary: summary)
                            }
                        }

                        if isCompact {
                            RecentFeedbackSection()
                        }
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
    }
}

/// The context line the Mac keeps in its toolbar and sidebar: which CloudKit
/// environment is being read, which record type resolved, and when the data
/// last came in.
private struct StatusRow: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        HStack(spacing: 8) {
            EnvironmentBadge()
            if let type = store.resolvedRecordType {
                Text(type)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if store.isRefreshing {
                ProgressView().controlSize(.mini)
            } else if let updated = store.lastUpdated {
                Text("업데이트 \(AppFormat.time(updated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// One dense row of the numbers the Mac shows in its sidebar: total, average
/// rating, last 7 days, project count, and which CloudKit environment is being
/// read.
private struct HeadlineStrip: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        let stats = store.stats
        HStack(spacing: 0) {
            cell(value: "\(stats.total)", unit: "건", label: "전체", tint: .accentColor)
            divider
            cell(value: stats.averageRating.map { String(format: "%.1f", $0) } ?? "—",
                 unit: stats.averageRating == nil ? "" : "점", label: "평균", tint: .yellow)
            divider
            cell(value: "\(stats.last7Days)", unit: "건", label: "7일", tint: .blue)
            divider
            // One slot, three things worth knowing — in the order they matter:
            // what hasn't been opened, what hasn't been decided, then the shape
            // of the hub when both are clear.
            if store.scopedUnreadCount > 0 {
                cell(value: "\(store.scopedUnreadCount)", unit: "건", label: "안 읽음", tint: .red)
            } else if store.scopedPendingCount > 0 {
                cell(value: "\(store.scopedPendingCount)", unit: "건", label: "확인 필요", tint: .orange)
            } else {
                cell(value: "\(store.availableProjects.count)", unit: "개", label: "프로젝트", tint: .purple)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }

    private var divider: some View {
        Divider().frame(height: 26)
    }

    private func cell(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// The newest feedback, so the overview screen isn't mostly empty space on a
/// phone. A row opens that feedback; "전체 보기" pushes the whole list.
private struct RecentFeedbackSection: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        let recent = store.recentFeedback(limit: 5)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("최근 피드백", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    NavigationLink(value: FeedbackStore.ListRoute(project: store.selectedProject)) {
                        Text("전체 보기").font(.callout)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, feedback in
                        NavigationLink(value: feedback) {
                            RecentRow(feedback: feedback,
                                      projectLabel: store.displayName(for: feedback.projectKey),
                                      isUnread: store.isUnread(feedback),
                                      status: store.status(of: feedback))
                        }
                        .buttonStyle(.plain)
                        if index < recent.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
            }
        }
    }
}

private struct RecentRow: View {
    let feedback: Feedback
    let projectLabel: String
    let isUnread: Bool
    let status: FeedbackStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            UnreadDot(isUnread: isUnread)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(projectLabel)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    if let rating = feedback.rating {
                        StarRatingView(rating: rating)
                    }
                    StatusChip(status: status, showsLabel: false)
                    Spacer(minLength: 4)
                    Text(feedback.createdAtRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(feedback.snippet)
                    .font(.callout)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .foregroundStyle(status.isHandled ? .secondary : .primary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var store: FeedbackStore
    let summary: FeedbackStore.ProjectSummary

    #if os(macOS)
    private let cardPadding: CGFloat = 14
    private let cardMinHeight: CGFloat = 130
    private let innerSpacing: CGFloat = 12
    #else
    private let cardPadding: CGFloat = 11
    private let cardMinHeight: CGFloat = 108
    private let innerSpacing: CGFloat = 8
    #endif

    var body: some View {
        NavigationLink(value: FeedbackStore.ListRoute(project: summary.project)) {
            VStack(alignment: .leading, spacing: innerSpacing) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: summary.isUnclassified ? "questionmark.folder" : "app.dashed")
                        .font(.subheadline)
                        .foregroundStyle(summary.isUnclassified ? Color.secondary : Color.accentColor)
                    // A bundle id can be long ("com.devkoan.CalendarSnap") and
                    // the tail is what tells projects apart, so let it wrap
                    // and shrink rather than truncate.
                    Text(summary.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 2)
                    // Unread first: it is the stronger call to action. Once
                    // everything has been opened, what is left undecided takes
                    // the slot.
                    if summary.unreadCount > 0 {
                        UnreadBadge(count: summary.unreadCount)
                    } else if summary.pendingCount > 0 {
                        PendingBadge(count: summary.pendingCount)
                    }
                    CountBadge(count: summary.count)
                }

                Divider()

                // Side by side when the card is wide enough (Mac, iPad), stacked
                // when it isn't (two-up grid on an iPhone).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { metrics }
                    VStack(alignment: .leading, spacing: 8) { metrics }
                }

                if let latest = summary.latest {
                    Text(latestLabel(latest))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if summary.unreadCount > 0 {
                Button {
                    store.markAllRead(project: summary.project)
                } label: {
                    Label("이 프로젝트 모두 읽음으로 표시", systemImage: "envelope.open")
                }
            }
            Button {
                store.hideProject(summary.project)
            } label: {
                Label("이 프로젝트 숨기기", systemImage: "eye.slash")
            }
        }
        .help("\(summary.displayName) 피드백 \(summary.count)건 보기")
        .accessibilityLabel("\(summary.displayName), 피드백 \(summary.count)건, 안 읽음 \(summary.unreadCount)건, 확인 필요 \(summary.pendingCount)건, 최근 7일 \(summary.last7Days)건")
    }

    /// A full timestamp has room on a Mac card; a phone card gets "3일 전".
    private func latestLabel(_ date: Date) -> String {
        #if os(macOS)
        return "마지막: \(AppFormat.dateTime(date))"
        #else
        return "마지막 \(AppFormat.relative(date))"
        #endif
    }

    @ViewBuilder
    private var metrics: some View {
        Metric(systemImage: "star.fill",
               tint: .yellow,
               value: summary.averageRating.map { String(format: "%.1f", $0) } ?? "—",
               label: "평균")
        Metric(systemImage: "clock",
               tint: .blue,
               value: "\(summary.last7Days)",
               label: "최근 7일")
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

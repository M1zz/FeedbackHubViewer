//
//  ProjectListView.swift
//  FeedbackHubViewer
//
//  The top level of the app on a phone: which project are we looking at? One
//  card per LeeoKit project plus a 전체 프로젝트 card, each carrying the numbers
//  that decide whether it is worth opening — feedback count, unread, average
//  rating, last 7 days, this week's diagnostics. Busiest app first: the order
//  is this week's usage traffic (see `FeedbackStore.trafficByProject`), not the
//  feedback count. Tapping one pushes that project's screen
//  (`ProjectSectionView`), where 피드백 · 통계 · 진단 live.
//
//  On a Mac / iPad the same choice is the sidebar (`SidebarView`).
//

import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var store: FeedbackStore

    #if os(macOS)
    private let contentSpacing: CGFloat = 16
    private let contentPadding: CGFloat = 16
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 16)]
    #else
    private let contentSpacing: CGFloat = 14
    private let contentPadding: CGFloat = 14
    // Full-width cards: two-up cards are ~190pt wide on a phone, which is not
    // enough for an app name plus four labelled numbers.
    private let columns = [GridItem(.flexible(), spacing: 14)]
    #endif

    var body: some View {
        VStack(spacing: 0) {
            StatusRow()
                .padding(.horizontal, contentPadding)
                .padding(.bottom, 8)
            content
        }
        // The title stays (it is what the back button on the next screen says)
        // but never as a large title: the cards already say "프로젝트", and the
        // large title plus its subtitle was eating the first card's worth of
        // screen before anything useful appeared.
        .navigationTitle("프로젝트")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                    LazyVGrid(columns: columns, spacing: contentSpacing) {
                        AllProjectsCard()
                        ForEach(store.projectSummaries) { summary in
                            ProjectCard(summary: summary)
                        }
                    }
                    .padding(contentPadding)

                    HiddenProjectsSection()
                        .padding(.horizontal, contentPadding)
                        .padding(.bottom, contentPadding)
                }
            }
        }
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty {
                // The first launch with no cache is the one read that takes
                // real time, so this is where the step and the count earn
                // their place.
                ProgressView(store.refreshProgress?.text ?? "불러오는 중…")
                    .monospacedDigit()
            }
        }
    }
}

/// The context line: which CloudKit environment is being read, which record
/// type resolved, and when the data last came in.
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
                // Which step, and how far into it — the caption has room for
                // that much of `RefreshProgress` and no more.
                if let progress = store.refreshProgress {
                    Text(progress.shortText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            } else if let updated = store.lastUpdated {
                Text("업데이트 \(AppFormat.time(updated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// What every project card shows, in one body: who it is, the four numbers
/// that decide whether it is worth opening, and the context line under them.
///
/// The 전체 프로젝트 card and a single project's card differ only in where their
/// numbers come from and what a long press offers — not in how they look — so
/// the look lives here and the two entrances below supply the rest.
private struct ProjectCardBody: View {
    let systemImage: String
    let tint: Color
    let name: String
    var subtitle: String? = nil
    var iconURL: URL? = nil

    let traffic: FeedbackStore.Traffic
    let feedbackCount: Int
    let unreadCount: Int
    /// Only a real project shows this; 전체 has its own 진단 screen for it.
    var crashes7: Int = 0
    let detail: String

    var body: some View {
        CardFrame {
            CardTitle(systemImage: systemImage, tint: tint, name: name,
                      subtitle: subtitle, iconURL: iconURL)

            Divider()

            // 목록의 정렬 기준이 7일 사용량이라, 그 숫자가 여기서 제일 먼저 보인다.
            MetricRow(items: [
                .init(value: "\(traffic.events7)", unit: "건", label: "7일 사용", tint: .accentColor),
                .init(value: "\(traffic.installs)", unit: "개", label: "설치", tint: .primary),
                .init(value: "\(feedbackCount)", unit: "건", label: "피드백", tint: .primary),
                .init(value: "\(unreadCount)", unit: "건", label: "안 읽음",
                      tint: unreadCount > 0 ? .red : .secondary)
            ])

            if crashes7 > 0 {
                Label("최근 7일 진단 \(crashes7)건", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }

            DetailLine(text: detail, traffic: traffic)
        }
    }

    /// 큰 숫자 네 개 밑에 붙는 보조 줄 — 있으면 도움이 되지만 크게 볼 필요는 없는 값들.
    /// Both cards build it the same way; only 전체 has no "마지막" to add.
    static func detailText(traffic: FeedbackStore.Traffic,
                           averageRating: Double?,
                           last7Days: Int,
                           latest: Date? = nil) -> String {
        var parts: [String] = []
        if traffic.activeInstalls7 > 0 { parts.append("7일 활성 \(traffic.activeInstalls7)개") }
        if let averageRating { parts.append(String(format: "평균 별점 %.1f", averageRating)) }
        if last7Days > 0 { parts.append("7일 피드백 \(last7Days)건") }
        if let latest { parts.append("마지막 \(AppFormat.relative(latest))") }
        return parts.joined(separator: " · ")
    }
}

/// Everything at once — the way into cross-project 피드백 · 통계 · 진단.
private struct AllProjectsCard: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        let stats = store.overallStats
        let traffic = store.overallTraffic

        NavigationLink(value: FeedbackStore.ProjectRoute(project: nil)) {
            ProjectCardBody(systemImage: "square.grid.3x3",
                            tint: .purple,
                            name: "전체 프로젝트",
                            subtitle: "모든 앱을 한 번에",
                            traffic: traffic,
                            feedbackCount: store.allFeedback.count,
                            unreadCount: store.unreadCount,
                            detail: ProjectCardBody.detailText(traffic: traffic,
                                                               averageRating: stats.averageRating,
                                                               last7Days: stats.last7Days))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("전체 프로젝트, 최근 7일 사용 \(traffic.events7)건, 피드백 \(store.allFeedback.count)건, 안 읽음 \(store.unreadCount)건")
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var store: FeedbackStore
    /// Only for the app icon — see `AppIcon`.
    @EnvironmentObject private var keywords: KeywordStore
    let summary: FeedbackStore.ProjectSummary

    var body: some View {
        let traffic = store.traffic(for: summary.project)

        NavigationLink(value: FeedbackStore.ProjectRoute(project: summary.project)) {
            ProjectCardBody(systemImage: summary.isUnclassified ? "questionmark.folder" : "app.dashed",
                            tint: summary.isUnclassified ? .secondary : .accentColor,
                            name: summary.displayName,
                            iconURL: keywords.storeApp(for: summary.project)?.iconURL,
                            traffic: traffic,
                            feedbackCount: summary.count,
                            unreadCount: summary.unreadCount,
                            crashes7: store.crashSummary(for: summary.project).last7Days,
                            detail: ProjectCardBody.detailText(traffic: traffic,
                                                               averageRating: summary.averageRating,
                                                               last7Days: summary.last7Days,
                                                               latest: summary.latest))
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
        .help("\(summary.displayName) 열기")
        .accessibilityLabel("\(summary.displayName), 최근 7일 사용 \(traffic.events7)건, 피드백 \(summary.count)건, 안 읽음 \(summary.unreadCount)건")
    }
}

/// Hiding a project is reachable from the cards; getting it back has to be
/// reachable from the same screen, because the phone has no sidebar.
private struct HiddenProjectsSection: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        if !store.hiddenProjectEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("숨긴 프로젝트", systemImage: "eye.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.hiddenProjectEntries.count > 1 {
                        Button("모두 다시 보기") { store.showAllProjects() }
                            .font(.caption)
                    }
                }
                ForEach(store.hiddenProjectEntries, id: \.key) { entry in
                    HStack(spacing: 8) {
                        Text(entry.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("\(entry.records)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Button("다시 보기") { store.showProject(entry.key) }
                            .font(.caption)
                    }
                }
                Text("이 기기에서만 가려집니다. 허브의 레코드는 그대로입니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}

// MARK: - Building blocks

/// 큰 숫자들 아래의 한 줄: 나머지 맥락과 14일 사용 그래프. 여기 있는 값은 "알면 좋은" 것들이고,
/// 결정을 만드는 숫자는 위의 큰 네 칸에 있다.
private struct DetailLine: View {
    let text: String
    let traffic: FeedbackStore.Traffic

    var body: some View {
        if !text.isEmpty || traffic.totalEvents > 0 {
            HStack(spacing: 8) {
                Text(text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if traffic.totalEvents > 0 {
                    Sparkline(points: traffic.sparkline)
                        .frame(width: 74, height: 26)
                }
            }
        }
    }
}

/// A card's first line: what it is, and one plain sentence under the name.
/// The chevron is there so a card reads as something you can open.
private struct CardTitle: View {
    let systemImage: String
    let tint: Color
    let name: String
    var subtitle: String? = nil
    var iconURL: URL? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIcon(url: iconURL, symbol: systemImage, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                // A bundle id can be long ("com.devkoan.CalendarSnap") and the
                // tail is what tells projects apart, so let it wrap and shrink
                // rather than truncate.
                Text(name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Numbers with their names under them. Every count on a card goes through
/// here: a bare coloured badge tells you a digit, not what it counts.
private struct MetricRow: View {
    struct Item: Identifiable {
        var id: String { label }
        let value: String
        let unit: String
        let label: String
        let tint: Color
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(.figure(.title2))
                            .foregroundStyle(item.tint)
                        if !item.unit.isEmpty {
                            Text(item.unit)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

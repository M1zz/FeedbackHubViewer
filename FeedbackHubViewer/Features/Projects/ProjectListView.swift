//
//  ProjectListView.swift
//  FeedbackHubViewer
//
//  The top level of the app on a phone: which project are we looking at? One
//  card per LeeoKit project plus a 전체 프로젝트 card.
//
//  카드의 큰 활자는 **변화**다. "7일 사용 5,000건"은 그 자체로 아무 결정도 만들지
//  못한다 — 5,000이 많은지 적은지는 이 앱의 지난주를 알아야 아는 것이고, 그걸
//  아는 쪽은 화면이다. 그래서 어제·지난주와 견준 결과가 앞에 서고, 절대값(설치·
//  피드백 수)은 밑줄로 내려간다. 변화 넷 아래에는 **성장 상한**이 한 줄 붙는다 —
//  그것만은 변화가 아니라 위치이기 때문에(지금 자리가 이 앱의 평형에서 몇 %인가)
//  화살표가 아니라 막대로 그린다. 손봐야 할 것 — 안 읽은 피드백, 확인이 필요한
//  피드백 — 은 제목 줄의 뱃지로 붙는다. 숫자 칸에 섞여 있으면 "읽을 것"과 "구경할
//  것"이 같은 무게로 보인다. Busiest app first: the order
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
    /// 안 읽음과 다른 숫자다: 읽었어도 반영/반영 안 함을 정하기 전까지는 여기 남는다.
    let pendingCount: Int
    /// 이 앱의 주간 성장 상한. 못 재면(이탈이 관측되지 않았거나 과거가 없으면) nil이고,
    /// 그때는 줄 자체가 없다 — 0%로 그리면 "상한에 한참 못 미친다"는 없는 말이 된다.
    var capacity: CarryingCapacity? = nil
    /// Only a real project shows this; 전체 has its own 진단 screen for it.
    var crashes7: Int = 0
    let detail: String

    var body: some View {
        CardFrame {
            CardTitle(systemImage: systemImage, tint: tint, name: name,
                      subtitle: subtitle, iconURL: iconURL,
                      unreadCount: unreadCount, pendingCount: pendingCount)

            Divider()

            if traffic.hasChanges {
                // 2×2로 고정한다. 넷을 한 줄에 놓으면 밑줄("1,204건 · 지난주
                // 1,310건")이 잘리는데, 그 줄이 잘리면 변화율만 남아 무엇에서
                // 무엇으로 간 변화인지 알 수 없게 된다 — 카드 폭이 넉넉한
                // 아이패드에서도 두 줄이 읽기 쉬운 이유가 그것이다.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) { yesterdayFigure; weekFigure }
                    HStack(alignment: .top, spacing: 10) { activeFigure; newInstallFigure }
                }
            } else {
                Text("아직 사용 기록이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let capacity, capacity.fill != nil {
                CapacityGlance(capacity: capacity)
            }

            if crashes7 > 0 {
                Label("최근 7일 진단 \(crashes7)건", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }

            DetailLine(text: detail, traffic: traffic)
        }
    }

    /// 카드 한 장을 한 문장으로. 눈으로는 화살표와 색이 방향을 말하지만, 음성
    /// 안내에는 그 방향이 말로 있어야 한다.
    static func accessibilitySummary(traffic: FeedbackStore.Traffic,
                                     capacity: CarryingCapacity? = nil,
                                     feedbackCount: Int,
                                     unreadCount: Int,
                                     pendingCount: Int) -> String {
        var parts: [String] = []
        if traffic.hasChanges {
            parts.append("7일 사용 \(traffic.events7)건, 지난주 \(traffic.previousEvents7)건")
            parts.append("7일 사용자 \(traffic.activeInstalls7)명, 지난주 \(traffic.previousActiveInstalls7)명")
        } else {
            parts.append("사용 기록 없음")
        }
        if let capacity, let fill = capacity.fill, let ceiling = capacity.capacity {
            parts.append("성장 상한 \(Int(ceiling.rounded()))명 중 \(Int((fill * 100).rounded()))퍼센트")
        }
        parts.append("피드백 \(feedbackCount)건")
        if unreadCount > 0 { parts.append("안 읽음 \(unreadCount)건") }
        if pendingCount > 0 { parts.append("확인 필요 \(pendingCount)건") }
        return parts.joined(separator: ", ")
    }

    /// 어제와 그제. 오늘을 안 세는 이유는 `Traffic.eventsYesterday`에 있다.
    private var yesterdayFigure: some View {
        TrendFigure(title: "어제 사용", current: traffic.eventsYesterday,
                    previous: traffic.eventsDayBefore, unit: "건", previousLabel: "그제")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekFigure: some View {
        TrendFigure(title: "7일 사용", current: traffic.events7,
                    previous: traffic.previousEvents7, unit: "건")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeFigure: some View {
        TrendFigure(title: "7일 사용자", current: traffic.activeInstalls7,
                    previous: traffic.previousActiveInstalls7, unit: "명")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newInstallFigure: some View {
        TrendFigure(title: "7일 신규", current: traffic.newInstalls7,
                    previous: traffic.previousNewInstalls7, unit: "대")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 변화 칸 밑에 붙는 보조 줄 — 절대값이 사는 자리다. 변화만 있고 원본이 없으면
    /// "+300%"가 3건에서 12건인지 3천에서 1만2천인지 알 수 없다.
    /// Both cards build it the same way; only 전체 has no "마지막" to add.
    static func detailText(traffic: FeedbackStore.Traffic,
                           feedbackCount: Int,
                           averageRating: Double?,
                           last7Days: Int,
                           latest: Date? = nil) -> String {
        var parts: [String] = []
        if traffic.installs > 0 { parts.append("설치 \(AppFormat.count(traffic.installs))대") }
        if feedbackCount > 0 { parts.append("피드백 \(AppFormat.count(feedbackCount))건") }
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
                            pendingCount: store.pendingCount,
                            capacity: store.carryingCapacity(for: nil, period: .week),
                            detail: ProjectCardBody.detailText(traffic: traffic,
                                                               feedbackCount: store.allFeedback.count,
                                                               averageRating: stats.averageRating,
                                                               last7Days: stats.last7Days))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("전체 프로젝트, " + ProjectCardBody.accessibilitySummary(
            traffic: traffic, capacity: store.carryingCapacity(for: nil, period: .week),
            feedbackCount: store.allFeedback.count,
            unreadCount: store.unreadCount, pendingCount: store.pendingCount))
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
                            pendingCount: summary.pendingCount,
                            capacity: store.carryingCapacity(for: summary.project, period: .week),
                            crashes7: store.crashSummary(for: summary.project).last7Days,
                            detail: ProjectCardBody.detailText(traffic: traffic,
                                                               feedbackCount: summary.count,
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
        .accessibilityLabel("\(summary.displayName), " + ProjectCardBody.accessibilitySummary(
            traffic: traffic, capacity: store.carryingCapacity(for: summary.project, period: .week),
            feedbackCount: summary.count,
            unreadCount: summary.unreadCount, pendingCount: summary.pendingCount))
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

/// 성장 상한 대비 지금 자리, 한 줄로.
///
/// 위의 네 칸과 성격이 다른 값이라 모양도 다르다: 저쪽은 **변화**(어제보다, 지난주보다)이고
/// 이쪽은 **위치**다 — 지금의 유입과 이탈이 이어질 때 활동 사용자가 멈추는 자리에서 얼마나
/// 왔는가. 화살표를 붙이면 오른 것처럼 읽히므로 막대로 그린다. 계산 근거와 한계는
/// `CarryingCapacity`(그리고 통계 화면의 같은 이름 카드)에 있다.
private struct CapacityGlance: View {
    let capacity: CarryingCapacity

    var body: some View {
        if let fill = capacity.fill, let ceiling = capacity.capacity {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("성장 상한 (\(capacity.period.activityName))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(Self.readout(capacity, fill: fill, ceiling: ceiling))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                // 넘어선 상태도 있다(유입이 몰렸거나 이탈이 잠시 멈춘 주). 막대는
                // 100%에서 멈추고, 숫자가 사실을 말한다 — 통계 화면의 같은 규칙.
                MeterBar(ratio: fill, height: 5, tint: fill >= 1 ? .orange : .accentColor)
            }
            .help(fill > 1
                  ? "지금의 유입과 이탈이 이어지면 주간 활동 사용자는 \(AppFormat.count(Int(ceiling.rounded())))명으로 내려앉습니다. 지금 \(AppFormat.count(capacity.currentActive))명은 그 자리보다 위예요 — 최근에 유입이 몰렸거나 이탈이 잠시 멈춘 것입니다."
                  : "지금의 유입과 이탈이 이어지면 주간 활동 사용자가 \(AppFormat.count(Int(ceiling.rounded())))명에서 멈춥니다. 지금은 그 \(Self.percent(fill)) 자리예요.")
        }
    }

    /// 상한 아래면 "몇 %까지 왔는가", 넘었으면 "넘어섬".
    ///
    /// 넘어선 상태에서 "248%"라고 적으면 좋은 소식처럼 읽히는데, 실은 반대다 —
    /// 지금의 유입과 이탈로는 이 수를 못 떠받친다는 뜻이라 앞으로 내려간다.
    /// 막대도 100%에서 멎어 있어 퍼센트만 커지면 눈으로 잴 수도 없다.
    private static func readout(_ capacity: CarryingCapacity,
                                fill: Double, ceiling: Double) -> String {
        let now = AppFormat.count(capacity.currentActive)
        let top = AppFormat.count(Int(ceiling.rounded()))
        return fill > 1 ? "지금 \(now)명 · 상한 \(top)명 넘어섬"
                        : "지금 \(now)명 · 상한 \(top)명 (\(percent(fill)))"
    }

    private static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", (ratio * 100).rounded())
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
    /// 안 읽은 피드백과 확인이 필요한 피드백. 0이면 뱃지 자체가 없다.
    var unreadCount: Int = 0
    var pendingCount: Int = 0

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
            CountBadge(count: unreadCount, systemImage: "envelope.badge.fill",
                       tint: .red, name: "안 읽은 피드백")
            CountBadge(count: pendingCount, systemImage: "checkmark.circle.fill",
                       tint: .orange, name: "확인이 필요한 피드백")
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

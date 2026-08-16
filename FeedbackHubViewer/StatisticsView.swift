//
//  StatisticsView.swift
//  FeedbackHubViewer
//
//  The 통계 pane. It shows the usage statistics the apps themselves report into
//  the hub (UsageSnapshot / UsageEvent — see `Usage.swift`), computed the way
//  the apps' own statistics screens compute them, plus a feedback summary at
//  the end. Event names and `metrics` keys are shown as the app sent them; the
//  viewer doesn't translate another app's vocabulary.
//
//  On iOS it opens on a per-project list and pushes `StatisticsDashboard` for
//  the project that is tapped. On macOS the dashboard is the pane and the
//  project is picked from a menu.
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        #if os(macOS)
        StatisticsDashboard(project: store.selectedProject, showsScopePicker: true)
        #else
        ProjectStatsListView()
        #endif
    }
}

// MARK: - Per-project list (iOS)

#if os(iOS)
/// The statistics root on iOS: one row per project with its headline usage
/// numbers and how they moved against the previous week.
struct ProjectStatsListView: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        Group {
            if store.errorMessage != nil && store.allFeedback.isEmpty && !store.hasUsageData {
                ContentUnavailableView {
                    Label("불러올 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.errorMessage ?? "")
                }
            } else if store.allProjectKeys.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "표시할 통계가 없습니다",
                    systemImage: "chart.bar",
                    description: Text(store.noticeMessage ?? "아직 수집된 데이터가 없습니다.")
                )
            } else {
                List {
                    if let notice = store.usageNotice {
                        Section {
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        ProjectStatsRow(project: nil)
                    }

                    Section("프로젝트별") {
                        ForEach(store.allProjectKeys, id: \.self) { key in
                            ProjectStatsRow(project: key)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty && !store.hasUsageData {
                ProgressView("불러오는 중…")
            }
        }
        .navigationTitle("통계")
        .hubNavigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let usage = store.overallUsage
        guard usage.installs > 0 else {
            return "앱이 보낸 사용 통계 없음 · \(store.allProjectKeys.count)개 프로젝트"
        }
        return "설치 \(usage.installs) · 7일 활성 \(usage.active7) · \(store.allProjectKeys.count)개 프로젝트"
    }
}

/// One project's line: the numbers the app reports, and the week-over-week
/// movement. Projects that report no usage fall back to their feedback counts,
/// so a feedback-only app still has a row.
private struct ProjectStatsRow: View {
    @EnvironmentObject private var store: FeedbackStore
    /// nil == 전체 프로젝트.
    let project: String?

    var body: some View {
        let usage = store.usage(for: project)
        let unread = unreadCount

        NavigationLink(value: FeedbackStore.StatsRoute(project: project)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(iconTint)
                    Text(usage.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if unread > 0 { UnreadBadge(count: unread) }
                    Spacer(minLength: 4)
                    Text(usage.installs > 0 ? "설치 \(usage.installs)" : "피드백 \(feedbackCount)건")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if usage.hasUsageData {
                    HStack(spacing: 10) {
                        MetricDelta(title: "활동 사용자 (7일)",
                                    value: "\(usage.activeInstalls7)",
                                    delta: delta(usage.activeInstallsDelta,
                                                 hasBaseline: usage.previousActiveInstalls7 > 0 || usage.activeInstalls7 > 0),
                                    tint: tint(usage.activeInstallsDelta, upIsGood: true))
                        MetricDelta(title: "사용 건수 (7일)",
                                    value: "\(usage.events7)",
                                    delta: delta(usage.eventsDelta,
                                                 hasBaseline: usage.previousEvents7 > 0 || usage.events7 > 0),
                                    tint: tint(usage.eventsDelta, upIsGood: true))
                        MetricDelta(title: "신규 설치 (7일)",
                                    value: "\(usage.new7)",
                                    delta: delta(usage.newDelta,
                                                 hasBaseline: usage.previousNew7 > 0 || usage.new7 > 0),
                                    tint: tint(usage.newDelta, upIsGood: true))

                        Spacer(minLength: 0)

                        Sparkline(points: usage.sparkline)
                            .frame(width: 68, height: 26)
                    }
                } else {
                    // Feedback-only project: say so instead of showing zeroes
                    // that look like a collapse in usage.
                    Text("이 앱은 아직 사용 통계를 보내지 않습니다 · 피드백 \(feedbackCount)건")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel(accessibilityLabel(usage))
    }

    private var feedbackCount: Int {
        guard let project else { return store.allFeedback.count }
        return store.allFeedback.filter { $0.projectKey == project }.count
    }

    private var unreadCount: Int {
        guard let project else { return store.unreadCount }
        return store.allFeedback.filter { $0.projectKey == project && store.isUnread($0) }.count
    }

    private var icon: String {
        if project == nil { return "square.grid.3x3" }
        return project == Feedback.unclassifiedProject ? "questionmark.folder" : "app.dashed"
    }

    private var iconTint: Color {
        if project == nil { return .purple }
        return project == Feedback.unclassifiedProject ? .secondary : .accentColor
    }

    /// "+5" / "-2" / "±0", or nil when there is nothing to compare against.
    private func delta(_ value: Int, hasBaseline: Bool) -> String? {
        guard hasBaseline else { return nil }
        if value == 0 { return "±0" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func tint(_ value: Int, upIsGood: Bool) -> Color {
        if value == 0 { return .secondary }
        let good = upIsGood ? value > 0 : value < 0
        return good ? .green : .red
    }

    private func accessibilityLabel(_ usage: FeedbackStore.ProjectUsage) -> String {
        guard usage.hasUsageData else {
            return "\(usage.displayName), 피드백 \(feedbackCount)건, 사용 통계 없음"
        }
        return "\(usage.displayName), 설치 \(usage.installs), 최근 7일 활동 사용자 \(usage.activeInstalls7), 지난주 대비 \(usage.activeInstallsDelta)"
    }
}

/// A headline number with the arrow showing which way it moved.
private struct MetricDelta: View {
    let title: String
    let value: String
    /// Already-formatted change, or nil when there is nothing to compare.
    let delta: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let delta {
                    HStack(spacing: 1) {
                        Image(systemName: DeltaArrow.symbol(for: delta))
                            .font(.system(size: 9, weight: .bold))
                        Text(delta)
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(tint)
                }
            }
            .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A 14-day event sparkline. Deliberately axis-free: it shows the shape of the
/// last two weeks, not exact values.
private struct Sparkline: View {
    let points: [FeedbackStore.DayCount]

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("날짜", point.date, unit: .day),
                     y: .value("건수", point.count))
                .foregroundStyle(Color.accentColor.opacity(0.18))
            LineMark(x: .value("날짜", point.date, unit: .day),
                     y: .value("건수", point.count))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...max(1, points.map(\.count).max() ?? 1))
        .accessibilityHidden(true)
    }
}
#endif

enum DeltaArrow {
    static func symbol(for delta: String) -> String {
        if delta.hasPrefix("+") { return "arrow.up.right" }
        if delta.hasPrefix("-") { return "arrow.down.right" }
        return "minus"
    }
}

// MARK: - Dashboard

struct StatisticsDashboard: View {
    @EnvironmentObject private var store: FeedbackStore
    /// The scope this screen was opened with (nil == 전체 프로젝트).
    let project: String?
    /// macOS picks the project from a menu on the dashboard itself; on iOS the
    /// project was already chosen in the list that pushed this screen.
    var showsScopePicker = false

    @State private var trendUnit: FeedbackStore.TrendUnit = .day

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

    /// The scope the numbers are computed for. On macOS the menu drives it.
    private var scope: String? { showsScopePicker ? store.selectedProject : project }

    var body: some View {
        Group {
            if store.errorMessage != nil && store.allFeedback.isEmpty && !store.hasUsageData {
                ContentUnavailableView {
                    Label("불러올 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(store.errorMessage ?? "")
                }
            } else if store.allProjectKeys.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "표시할 통계가 없습니다",
                    systemImage: "chart.bar",
                    description: Text(store.noticeMessage ?? "아직 수집된 데이터가 없습니다.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        if showsScopePicker { scopePicker }
                        if let notice = store.usageNotice { usageNotice(notice) }

                        if usage.hasUsageData {
                            userTiles
                            weekOverWeek
                            trendCard
                            feedbackLink
                            eventCard
                            metricsCard
                            flagCard
                            distributionCards
                        } else {
                            noUsageCard
                            feedbackLink
                        }

                        feedbackCard
                    }
                    .padding(contentPadding)
                }
            }
        }
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty && !store.hasUsageData {
                ProgressView("불러오는 중…")
            }
        }
        .navigationTitle(title)
        .hubNavigationSubtitle(subtitle)
    }

    private var usage: FeedbackStore.ProjectUsage { store.usage(for: scope) }

    private var title: String {
        // The Mac pane keeps its own name; the pushed iOS screen is named after
        // the project it was opened for.
        guard !showsScopePicker, let key = scope else { return "통계" }
        return store.displayName(for: key)
    }

    private var subtitle: String {
        let usage = usage
        if usage.hasUsageData {
            return "설치 \(usage.installs) · 7일 활성 \(usage.active7) · 이벤트 \(usage.totalEvents)"
        }
        if let key = scope {
            return "프로젝트: \(store.displayName(for: key)) · 피드백 \(store.scopedFeedback.count)건"
        }
        return "전체 피드백 \(store.allFeedback.count)건 / \(store.allProjectKeys.count)개 프로젝트"
    }

    // MARK: - Scope

    private var scopePicker: some View {
        HStack(spacing: 8) {
            Picker("프로젝트", selection: $store.selectedProject) {
                Text("전체 프로젝트").tag(String?.none)
                ForEach(store.allProjectKeys, id: \.self) { key in
                    Text(store.displayName(for: key)).tag(String?.some(key))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer(minLength: 4)
            EnvironmentBadge()
        }
    }

    private func usageNotice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var noUsageCard: some View {
        Card(title: "사용 통계", systemImage: "chart.bar.xaxis") {
            Text("이 프로젝트는 아직 UsageSnapshot / UsageEvent 를 보내지 않았습니다. 앱이 LeeoKit의 사용 통계 전송을 켜고 스키마가 이 환경에 배포되면 여기에 그대로 표시됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 사용자

    private var userTiles: some View {
        LazyVGrid(columns: tileColumns, spacing: 10) {
            StatTile(title: "설치 (사용 중인 기기)", value: "\(usage.installs)", unit: "곳",
                     systemImage: "iphone", tint: .accentColor)
            StatTile(title: "최근 7일 활성", value: "\(usage.active7)", unit: "곳",
                     systemImage: "bolt.fill", tint: .blue)
            StatTile(title: "최근 30일 활성", value: "\(usage.active30)", unit: "곳",
                     systemImage: "calendar", tint: .teal)
            StatTile(title: "최근 7일 신규", value: "\(usage.new7)", unit: "곳",
                     systemImage: "sparkles", tint: .green)
            StatTile(title: "누적 실행", value: "\(usage.totalLaunches)", unit: "회",
                     systemImage: "play.circle", tint: .indigo)
            StatTile(title: "누적 주요 행동", value: "\(usage.totalSignificantEvents)", unit: "회",
                     systemImage: "hand.tap", tint: .orange)
        }
    }

    /// This week against the one before it, from the event stream.
    private var weekOverWeek: some View {
        Card(title: "지난주 대비", systemImage: "arrow.up.arrow.down") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { weekOverWeekItems }
                VStack(alignment: .leading, spacing: 12) { weekOverWeekItems }
            }
        }
    }

    @ViewBuilder
    private var weekOverWeekItems: some View {
        ComparisonRow(title: "활동한 사용자",
                      recent: "\(usage.activeInstalls7)곳",
                      previous: "지난주 \(usage.previousActiveInstalls7)곳",
                      delta: signed(usage.activeInstallsDelta),
                      tint: deltaTint(usage.activeInstallsDelta))
        ComparisonRow(title: "사용 건수",
                      recent: "\(usage.events7)건",
                      previous: "지난주 \(usage.previousEvents7)건",
                      delta: signed(usage.eventsDelta),
                      tint: deltaTint(usage.eventsDelta))
        ComparisonRow(title: "신규 설치",
                      recent: "\(usage.new7)곳",
                      previous: "지난주 \(usage.previousNew7)곳",
                      delta: signed(usage.newDelta),
                      tint: deltaTint(usage.newDelta))
    }

    private func signed(_ value: Int) -> String {
        if value == 0 { return "±0" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func deltaTint(_ value: Int) -> Color {
        if value == 0 { return .secondary }
        return value > 0 ? .green : .red
    }

    // MARK: - 기간별 추이

    private var trendCard: some View {
        let points = store.trend(for: scope, unit: trendUnit)
        return Card(title: "기간별 추이", systemImage: "chart.xyaxis.line") {
            Picker("단위", selection: $trendUnit) {
                ForEach(FeedbackStore.TrendUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if points.isEmpty {
                emptyNote("아직 기록된 이벤트가 없습니다.")
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("기간", point.date, unit: trendUnit.component),
                                y: .value("사용 건수", point.events))
                            .foregroundStyle(Color.accentColor.opacity(0.35))
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("기간", point.date, unit: trendUnit.component),
                                 y: .value("활동한 사용자", point.activeInstalls),
                                 series: .value("계열", "활동한 사용자"))
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.monotone)
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("기간", point.date, unit: trendUnit.component),
                                 y: .value("신규 설치", point.newInstalls),
                                 series: .value("계열", "신규 설치"))
                            .foregroundStyle(Color.green)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: trendHeight)

                HStack(spacing: 12) {
                    legendDot(Color.accentColor.opacity(0.5), "사용 건수")
                    legendDot(.blue, "활동한 사용자")
                    legendDot(.green, "신규 설치")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("발생 시각(occurredAt) 기준입니다. 키보드처럼 나중에 소급 전송된 활동도 실제 사용일에 표시됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: - 이벤트 · 지표

    private var eventCard: some View {
        let events = store.eventStats(for: scope)
        return Card(title: "앱 사용 내용 (이벤트)", systemImage: "list.bullet.rectangle") {
            if events.isEmpty {
                emptyNote("아직 기록된 이벤트가 없습니다.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let last = event.lastAt {
                                    Text("마지막 \(AppFormat.relative(last))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text("\(event.count)건")
                                .font(.callout.monospacedDigit().weight(.semibold))
                            Text("설치 \(event.installs)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        if index < events.count - 1 { Divider() }
                    }
                }
                Text("이름은 앱이 보낸 그대로입니다. 콜론 뒤는 슬라이스(예: paywall_view:memo).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var metricsCard: some View {
        let metrics = store.metricAverages(for: scope)
        return Card(title: "설치당 평균 지표", systemImage: "number") {
            if metrics.isEmpty {
                emptyNote("앱이 보낸 지표가 없습니다.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        HStack {
                            Text(metric.key)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Self.format(metric.average))
                                .font(.callout.monospacedDigit().weight(.semibold))
                            Text("합계 \(Self.format(metric.total))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        if index < metrics.count - 1 { Divider() }
                    }
                }
                Text("앱이 스냅샷의 metrics 로 보낸 값 그대로입니다 (그 값을 보낸 설치 기준 평균).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var flagCard: some View {
        let shares = store.flagShares(for: scope)
        if !shares.isEmpty {
            Card(title: "사용자 비율", systemImage: "person.2") {
                VStack(spacing: 8) {
                    ForEach(shares) { share in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(share.key)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(Int((share.ratio * 100).rounded()))% (\(share.count))")
                                    .font(.callout.monospacedDigit().weight(.semibold))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.12))
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: max(2, geo.size.width * share.ratio))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
    }

    private var distributionCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { distributionItems }
            VStack(spacing: sectionSpacing) { distributionItems }
        }
    }

    @ViewBuilder
    private var distributionItems: some View {
        distributionCard(title: "앱 버전", systemImage: "app.badge", field: \.appVersion)
        distributionCard(title: "플랫폼 · OS", systemImage: "desktopcomputer", field: \.platform, second: \.osVersion)
    }

    private func distributionCard(title: String,
                                  systemImage: String,
                                  field: KeyPath<UsageSnapshot, String>,
                                  second: KeyPath<UsageSnapshot, String>? = nil) -> some View {
        Card(title: title, systemImage: systemImage) {
            distributionRows(store.distribution(for: scope, by: field))
            if let second {
                Divider()
                distributionRows(store.distribution(for: scope, by: second))
            }
        }
    }

    @ViewBuilder
    private func distributionRows(_ buckets: [FeedbackStore.DistributionBucket]) -> some View {
        if buckets.isEmpty {
            emptyNote("데이터 없음")
        } else {
            VStack(spacing: 4) {
                ForEach(buckets.prefix(12)) { bucket in
                    HStack {
                        Text(bucket.key)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(bucket.count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 피드백

    /// Straight from the numbers into the feedback they came from.
    private var feedbackLink: some View {
        NavigationLink(value: FeedbackStore.ListRoute(project: scope)) {
            HStack {
                Label("피드백 목록 보기", systemImage: "list.bullet")
                    .font(.callout.weight(.medium))
                Spacer()
                if scopedUnread > 0 {
                    UnreadBadge(count: scopedUnread)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var scopedUnread: Int {
        let items = scope.map { key in store.allFeedback.filter { $0.projectKey == key } } ?? store.allFeedback
        return items.filter { store.isUnread($0) }.count
    }

    private var feedbackCard: some View {
        let items = scope.map { key in store.allFeedback.filter { $0.projectKey == key } } ?? store.allFeedback
        let ratings = items.compactMap(\.rating)
        let average = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        var ratingBuckets: [Int: Int] = [:]
        for r in ratings { ratingBuckets[r, default: 0] += 1 }
        let ratingCounts = (1...5).reversed().map { (rating: $0, count: ratingBuckets[$0] ?? 0) }
        var typeBuckets: [String: Int] = [:]
        for item in items {
            let key = item.feedbackType?.trimmingCharacters(in: .whitespaces)
            typeBuckets[(key?.isEmpty == false ? key! : "기타"), default: 0] += 1
        }
        let types = typeBuckets.map { (type: $0.key, count: $0.value) }.sorted { $0.count > $1.count }

        return Card(title: "피드백", systemImage: "text.bubble") {
            HStack(spacing: 16) {
                ComparisonRow(title: "접수", recent: "\(items.count)건",
                              previous: "안 읽음 \(scopedUnread)건", delta: nil, tint: .secondary)
                ComparisonRow(title: "평균 별점",
                              recent: average.map { String(format: "%.2f", $0) } ?? "—",
                              previous: ratings.isEmpty ? "별점 없음" : "\(ratings.count)건 기준",
                              delta: nil, tint: .secondary)
            }

            if !ratings.isEmpty {
                Chart(ratingCounts, id: \.rating) { entry in
                    BarMark(x: .value("건수", entry.count),
                            y: .value("별점", "\(entry.rating)★"))
                        .foregroundStyle(.yellow.gradient)
                        .annotation(position: .trailing) {
                            Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: breakdownHeight)
            }

            if types.count > 1 || types.first?.type != "기타" {
                Chart(types, id: \.type) { entry in
                    BarMark(x: .value("건수", entry.count),
                            y: .value("유형", entry.type))
                        .foregroundStyle(Color.teal.gradient)
                        .annotation(position: .trailing) {
                            Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: max(70, CGFloat(types.count) * 28))
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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

/// "이번 주 값 · 지난주 값 · 변화" for one metric.
private struct ComparisonRow: View {
    let title: String
    let recent: String
    let previous: String
    /// Already-formatted change, or nil when there is nothing to compare.
    let delta: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(recent)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                if let delta {
                    HStack(spacing: 1) {
                        Image(systemName: DeltaArrow.symbol(for: delta))
                            .font(.system(size: 10, weight: .bold))
                        Text(delta).font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(tint)
                }
            }
            Text(previous)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

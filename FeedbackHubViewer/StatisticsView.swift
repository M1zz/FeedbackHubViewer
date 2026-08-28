//
//  StatisticsView.swift
//  FeedbackHubViewer
//
//  The 통계 section of a project screen — usage only. Diagnostics used to have
//  a card here too; they are their own section now (`CrashListView`), and a
//  screen that repeats the neighbouring section is a screen you have to read
//  twice to know where anything lives. It shows the usage statistics the apps
//  themselves report into the hub (UsageSnapshot / UsageEvent — see
//  `Usage.swift`), computed the way the apps' own statistics screens compute
//  them, plus a feedback summary at the end. Event names and `metrics` keys are
//  shown as the app sent them; the viewer doesn't translate another app's
//  vocabulary.
//
//  The project it describes is chosen one level up (`ProjectSectionView`), so
//  this screen has no scope picker and no title of its own.
//

import SwiftUI
import Charts

/// A 14-day event sparkline. Deliberately axis-free: it shows the shape of
/// the last two weeks, not exact values. Used by the project cards and the
/// dashboard alike.
struct Sparkline: View {
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
    /// The scope this section was opened with (nil == 전체 프로젝트).
    let project: String?

    @State private var trendUnit: FeedbackStore.TrendUnit = .day
    /// How many individual events the 사용 내역 card is showing.
    @State private var eventLogLimit = 20

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

    /// The scope the numbers are computed for.
    private var scope: String? { project }

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
                        if let notice = store.usageNotice { usageNotice(notice) }

                        if usage.hasUsageData {
                            userTiles
                            specCards
                            weekOverWeek
                            trendCard
                            eventCard
                            eventLogCard
                            metricsCard
                            flagCard
                            distributionCards
                        } else {
                            noUsageCard
                            specCards
                        }

                        feedbackCard
                        specGapCard
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
    }

    private var usage: FeedbackStore.ProjectUsage { store.usage(for: scope) }

    // MARK: - 앱별 스펙

    /// 이 프로젝트의 통계 스펙 — 앱이 자기 화면에서 쓰는 어휘와 해석(`Specs/*.json`).
    /// 전체 프로젝트 범위에서는 앱마다 뜻이 달라 합칠 수 없으므로 쓰지 않는다.
    private var spec: ProjectStatsSpec? {
        guard let scope else { return nil }
        return ProjectStatsSpecCatalog.spec(for: scope)
    }

    private var scopedMetrics: [[String: Double]] {
        store.snapshots(for: scope).map(\.metrics)
    }

    /// 앱 자신의 통계 화면이 보여주는 것과 같은 카드들.
    @ViewBuilder
    private var specCards: some View {
        if let spec {
            // 퍼널만 입력이 다르다: 설치에 남은 상태(`metrics`)가 아니라 일어난 일
            // (이벤트 집계)을 읽는다. 이름별로 이미 접혀 있는 값이라 원본을 훑지 않는다.
            ForEach(spec.insights(for: scopedMetrics)
                    + spec.funnelInsights(for: store.eventTallies(for: scope))) { insight in
                switch insight {
                case .tiles(let title, let note, let items):
                    Card(title: title, systemImage: "star.circle") {
                        LazyVGrid(columns: tileColumns, spacing: 10) {
                            ForEach(items) { item in
                                SpecTile(label: item.label, value: item.value, hint: item.hint)
                            }
                        }
                        if let note { footnote(note) }
                    }
                case .bars(let title, let note, let rows):
                    Card(title: title, systemImage: "chart.bar") {
                        VStack(spacing: 8) {
                            ForEach(rows) { row in
                                SpecBar(label: row.label, value: row.value,
                                        ratio: row.ratio, hint: row.hint)
                            }
                        }
                        if let note { footnote(note) }
                    }
                case .funnel(let title, let note, let steps):
                    Card(title: title, systemImage: "arrow.down.right.circle") {
                        VStack(spacing: 8) {
                            ForEach(steps) { step in
                                SpecFunnelStep(step: step)
                            }
                        }
                        if let note { footnote(note) }
                        if steps.contains(where: \.exceedsPrevious) {
                            footnote("주황 칸은 앞 단계보다 수가 많아요. 퍼널이 성립하려면 각 칸이 앞 칸에 포함돼야 하는데, 이벤트 이름만으로는 '앞을 거쳐서 왔다'를 강제할 수 없어요 — 그 자리는 다른 경로로도 닿습니다. 경로를 구분하려면 앱이 이벤트에 슬라이스를 붙여 보내야 해요.")
                        }
                        if steps.contains(where: \.isMissing) {
                            footnote("회색 칸은 그 이벤트가 이 앱에서 **한 번도 도착한 적이 없다**는 뜻이에요. 아무도 거기까지 못 간 게 아니라 앱이 그 이벤트를 아직 안 보내는 거라, 스펙이 아니라 앱을 고쳐야 답이 나옵니다.")
                        }
                    }
                }
            }
        }
    }

    /// 스펙이 아직 이름을 붙이지 않은 지표·이벤트. 앱이 새 값을 보내기 시작했다는 뜻이고,
    /// 여기 뜨면 그 앱 리포의 `docs/usage-spec.json`에 라벨을 더할 차례다.
    @ViewBuilder
    private var specGapCard: some View {
        if let spec {
            let metrics = spec.unknownMetricKeys(in: scopedMetrics)
            // 이름별로 이미 접혀 있는 집계에서 뽑는다: 이벤트 원본을 매번 훑으면
            // 이 카드 하나 때문에 전체 레코드를 프레임마다 다시 읽게 된다.
            let events = spec.unknownEventNames(in: store.eventStats(for: scope).map(\.name))
            if !metrics.isEmpty || !events.isEmpty {
                Card(title: "스펙에 없는 지표", systemImage: "questionmark.circle") {
                    if !metrics.isEmpty {
                        Text("지표: " + metrics.joined(separator: ", "))
                            .font(.callout.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !events.isEmpty {
                        Text("이벤트: " + events.joined(separator: ", "))
                            .font(.callout.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    footnote("이 앱이 보내기 시작했는데 스펙에는 아직 이름이 없는 값이에요. 값은 위 카드에 키 원문 그대로 나옵니다. \(spec.appName ?? spec.appId) 리포의 docs/usage-spec.json에 라벨을 적고 scripts/sync-stats-specs.sh를 돌리면 사라져요.")
                }
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
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

                FlowLayout(spacing: 12, lineSpacing: 4) {
                    legendDot(Color.accentColor.opacity(0.5), "사용 건수")
                    legendDot(.blue, "활동한 사용자")
                    legendDot(.green, "신규 설치")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        VStack(alignment: .leading, spacing: 2) {
                            // The name wraps instead of truncating: the slice
                            // after the colon is the interesting half, so
                            // cutting the middle loses the answer.
                            Text(spec?.label(forEvent: event.name) ?? event.name)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text("\(event.count)건")
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                Text("설치 \(event.installs)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                if let last = event.lastAt {
                                    Text("마지막 \(AppFormat.relative(last))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The events themselves, one line each. "최근 7일 사용 50건" is a number you
    /// cannot check anywhere else: the card above counts them by name, the
    /// chart draws them by day, and neither lets you look at the 50.
    private var eventLogCard: some View {
        let all = store.eventLog(for: scope)
        let shown = Array(all.prefix(eventLogLimit))

        return Card(title: "사용 내역", systemImage: "clock.arrow.circlepath") {
            if all.isEmpty {
                emptyNote("아직 기록된 이벤트가 없습니다.")
            } else {
                Text("최근 7일 \(usage.events7)건 · 전체 \(all.count)건")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                        eventLogRow(event)
                        if index < shown.count - 1 { Divider() }
                    }
                }

                if all.count > shown.count {
                    Button {
                        eventLogLimit += 50
                    } label: {
                        Label("더 보기 (남은 \(all.count - shown.count)건)", systemImage: "chevron.down")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                } else if eventLogLimit > 20 {
                    Button {
                        eventLogLimit = 20
                    } label: {
                        Label("접기", systemImage: "chevron.up")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                }

                Text("발생 시각(occurredAt) 기준 최신순입니다. 설치 ID는 앱이 보낸 익명 식별자의 앞부분이라, 같은 값이면 같은 기기입니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func eventLogRow(_ event: UsageEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(spec?.label(forEvent: event.name) ?? event.name)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(AppFormat.dateTime(event.occurredAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if scope == nil {
                    Text(store.displayName(for: event.projectKey))
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("설치 \(Self.shortInstall(event.installID)) · v\(event.appVersion) · \(event.platform)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// Enough of the anonymous install id to tell installs apart, not so much
    /// that it takes the row.
    private static func shortInstall(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "—" }
        return String(id.prefix(8))
    }

    private var metricsCard: some View {
        let metrics = store.metricAverages(for: scope)
        return Card(title: "설치당 평균 지표", systemImage: "number") {
            if metrics.isEmpty {
                emptyNote("앱이 보낸 지표가 없습니다.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(spec?.label(forMetric: metric.key) ?? metric.key)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text(Self.format(metric.average))
                                .font(.callout.monospacedDigit().weight(.semibold))
                            Text("합계 \(Self.format(metric.total))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .layoutPriority(-1)
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
                            HStack(alignment: .firstTextBaseline) {
                                Text(spec?.label(forMetric: share.key) ?? share.key)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
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
                    HStack(alignment: .firstTextBaseline) {
                        Text(bucket.key)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
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
                // Headroom for the trailing count, which is drawn outside the
                // bar and would otherwise be clipped at the plot edge.
                .chartXScale(domain: 0...Self.annotationHeadroom(ratingCounts.map(\.count).max() ?? 0))
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
                .chartXScale(domain: 0...Self.annotationHeadroom(types.map(\.count).max() ?? 0))
                .frame(height: max(90, CGFloat(types.count) * 30))
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

    /// Upper bound for a bar chart whose bars carry a trailing label: about
    /// 18% past the longest bar so the label has room inside the plot.
    private static func annotationHeadroom(_ maximum: Int) -> Double {
        max(1, Double(maximum) * 1.18)
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

/// 스펙이 만든 숫자 하나.
private struct SpecTile: View {
    let label: String
    let value: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 스펙이 만든 막대 한 줄 — 분포·비중·무리 크기가 전부 이 모양이다.
/// 퍼널 한 칸. 막대 길이는 첫 단계 대비이고, 오른쪽 작은 숫자는 바로 앞 단계 대비다 —
/// 어디서 새는지는 전체 전환율이 아니라 단계 사이의 낙차가 말해 준다.
private struct SpecFunnelStep: View {
    let step: ProjectStatsSpec.Insight.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.label)
                    .font(.callout)
                    .foregroundStyle(step.isMissing ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if step.isMissing {
                    Text("보내지 않음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(step.count)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                    if step.exceedsPrevious {
                        // 전환율인 척하지 않는다: 앞 단계를 거치지 않고도 닿는
                        // 자리라는 뜻이고, 퍼센트로 적으면 거짓말이 된다.
                        Label("앞 단계 밖에서도 옴", systemImage: "arrow.turn.up.right")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let previous = step.fromPrevious {
                        Text(Self.percent(previous))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(step.isMissing ? Color.secondary.opacity(0.25) : Color.accentColor)
                        .frame(width: max(2, geo.size.width * min(1, max(0, step.ratio))))
                }
            }
            .frame(height: 6)
            if let hint = step.hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func percent(_ ratio: Double) -> String {
        "→ " + String(format: "%.0f%%", (ratio * 100).rounded())
    }
}

private struct SpecBar: View {
    let label: String
    let value: String
    let ratio: Double
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(value)
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * min(1, max(0, ratio))))
                }
            }
            .frame(height: 6)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

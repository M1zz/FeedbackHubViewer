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
                            activeUsersCard
                            specCards
                            weekOverWeek
                            CarryingCapacityCard(project: scope)
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
                ProgressView(store.refreshProgress?.text ?? "불러오는 중…")
                    .monospacedDigit()
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
            .cardSurface(radius: 10, bordered: false)
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

    // MARK: - 활성 사용자 (DAU · WAU · MAU)

    /// 같은 것을 세 가지 창으로 잰 한 장.
    ///
    /// 셋을 함께 놓는 이유는 하나만으로는 답이 안 나오기 때문이다. DAU는 오늘
    /// 하루의 사정(주말, 배포, 푸시 한 번)에 그대로 흔들리고, MAU는 이미 떠난
    /// 사람도 30일 동안 안고 있어 늦게 떨어진다. 방향은 셋을 겹쳐 봐야 보이고,
    /// "얼마나 자주 오는가"는 둘의 비(고착도)에서만 나온다.
    private var activeUsersCard: some View {
        let active = store.activeUsers(for: scope)
        return Card(title: "활성 사용자 (DAU · WAU · MAU)", systemImage: "person.3") {
            if active.isEmpty {
                emptyNote("최근 30일 안에 도착한 이벤트가 없습니다.")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { activeUsersFigures(active) }
                    VStack(alignment: .leading, spacing: 12) { activeUsersFigures(active) }
                }
                stickinessRow(active)
                activeUsersChart(active)
                footnote("각 창 안에서 이벤트를 보낸 서로 다른 설치를 셉니다. 창이 서로 겹치므로 세 숫자를 더하면 안 돼요 — 오늘 쓴 사람은 주간·월간에도 들어 있습니다. 오늘은 아직 지나지 않은 하루라 DAU는 하루가 끝날 때까지 계속 올라가고, 그래서 어제와 견주는 화살표는 늦은 시각일수록 정확해집니다. 위 '최근 7일 활성' 타일은 스냅샷이 적어 보낸 마지막 활동 시각 기준이라 여기 WAU와 숫자가 다를 수 있어요.")
            }
        }
    }

    @ViewBuilder
    private func activeUsersFigures(_ active: FeedbackStore.ActiveUsers) -> some View {
        ForEach(active.windows) { window in
            Figure(window.span.label, "\(window.current)곳",
                   note: "\(window.span.previousLabel) \(window.previous)곳") {
                DeltaLabel(value: window.delta, polarity: .higherIsBetter)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 고착도 — 월간 활성 사용자가 한 달에 며칠이나 오는가. 낮다고 나쁜 게
    /// 아니라 앱의 성격이라, 좋고 나쁨을 색으로 말하지 않고 비율만 그린다.
    @ViewBuilder
    private func stickinessRow(_ active: FeedbackStore.ActiveUsers) -> some View {
        if let ratio = active.stickiness {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("고착도 (평균 DAU ÷ MAU)")
                        .font(.callout)
                    Spacer(minLength: 8)
                    Text(String(format: "%.0f%%", (ratio * 100).rounded()))
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                MeterBar(ratio: ratio, height: 5)
                footnote("최근 30일에 한 번이라도 쓴 사람이 30일 중 평균 \(String(format: "%.1f", ratio * 30))일 씁니다. 매일 여는 도구는 높고, 필요할 때만 여는 도구는 낮아요 — 낮다고 나쁜 게 아니라 앱의 성격입니다. 분자는 오늘이 아니라 지나간 날들의 하루 평균이라, 아직 끝나지 않은 오늘 때문에 아침마다 0으로 떨어지지 않아요.")
            }
        }
    }

    /// 세 창을 하루씩 물러나며 다시 잰 30일 추이. 긴 창이 언제나 위에 놓이는 것은
    /// 정의상 당연하다 — 짧은 창은 긴 창의 부분집합이다. 그러니 볼 것은 높낮이가
    /// 아니라 **간격**이다: 세 선이 붙으면 오는 사람이 매일 오는 그 사람들이고,
    /// 벌어지면 한 번 왔다 안 오는 사람이 그만큼 쌓였다는 뜻이다.
    @ViewBuilder
    private func activeUsersChart(_ active: FeedbackStore.ActiveUsers) -> some View {
        let peak = active.series.map(\.month).max() ?? 0
        Chart {
            ForEach(active.series) { point in
                LineMark(x: .value("날짜", point.date, unit: .day),
                         y: .value("사용자", point.month),
                         series: .value("계열", "월간"))
                    .foregroundStyle(Color.teal)
                    .interpolationMethod(.monotone)
            }
            ForEach(active.series) { point in
                LineMark(x: .value("날짜", point.date, unit: .day),
                         y: .value("사용자", point.week),
                         series: .value("계열", "주간"))
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.monotone)
            }
            ForEach(active.series) { point in
                LineMark(x: .value("날짜", point.date, unit: .day),
                         y: .value("사용자", point.day),
                         series: .value("계열", "일간"))
                    // 강조색이 아니라 주황: 이 화면의 강조색은 파랑이라 주간 선과
                    // 구별이 안 됐다. 세 선은 순서가 아니라 서로 다른 창이므로
                    // 색도 서로 최대한 멀어야 한다.
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.monotone)
            }
        }
        // 0에서 시작하지 않으면 몇 명 오르내린 것이 절벽처럼 보인다.
        .chartYScale(domain: 0...Double(max(1, peak)))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: trendHeight)

        FlowLayout(spacing: 12, lineSpacing: 4) {
            legendDot(.orange, "일간 (DAU)")
            legendDot(.blue, "주간 (WAU)")
            legendDot(.teal, "월간 (MAU)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 활동한 사용자는 여기 없다: 7일 창의 활동 설치 수는 위 카드의 WAU와 정의도
    /// 값도 같은 숫자라, 두 번 적으면 읽는 사람이 다른 것인 줄 알고 비교하게 된다.
    @ViewBuilder
    private var weekOverWeekItems: some View {
        comparison("사용 건수", "\(usage.events7)건",
                   "지난주 \(usage.previousEvents7)건", usage.eventsDelta)
        comparison("신규 설치", "\(usage.new7)곳",
                   "지난주 \(usage.previousNew7)곳", usage.newDelta)
    }

    /// One metric's 이번 주 · 지난주 · 변화. More usage is good news on all
    /// three of them, so they share one polarity.
    private func comparison(_ title: String, _ recent: String,
                            _ previous: String, _ delta: Int) -> some View {
        Figure(title, recent, note: previous) {
            DeltaLabel(value: delta, polarity: .higherIsBetter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Tag(text: store.displayName(for: event.projectKey), font: .caption2)
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
                            MeterBar(ratio: share.ratio, height: 5)
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
                Figure("접수", "\(items.count)건", note: "안 읽음 \(scopedUnread)건")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Figure("평균 별점", average.map { String(format: "%.2f", $0) } ?? "—",
                       note: ratings.isEmpty ? "별점 없음" : "\(ratings.count)건 기준")
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.figure())
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
        .cardSurface(radius: 10, bordered: false)
    }
}

/// 스펙이 만든 막대 한 줄 — 분포·비중·무리 크기·퍼널 한 칸이 전부 이 모양이다:
/// 이름과 값이 마주 보는 한 줄, 그 아래 막대, 그 아래 각주.
private struct SpecBar<Trailing: View>: View {
    let label: String
    let ratio: Double
    var hint: String?
    var tint: Color = .accentColor
    var isMuted = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                trailing
            }
            MeterBar(ratio: ratio, tint: tint)
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

extension SpecBar where Trailing == Text {
    /// The plain form: one value on the right and nothing else.
    init(label: String, value: String, ratio: Double, hint: String? = nil) {
        self.init(label: label, ratio: ratio, hint: hint) {
            Text(value).font(.callout.monospacedDigit().weight(.semibold))
        }
    }
}

/// 퍼널 한 칸. 막대 길이는 첫 단계 대비이고, 오른쪽 작은 숫자는 바로 앞 단계 대비다 —
/// 어디서 새는지는 전체 전환율이 아니라 단계 사이의 낙차가 말해 준다.
private struct SpecFunnelStep: View {
    let step: ProjectStatsSpec.Insight.Step

    var body: some View {
        SpecBar(label: step.label,
                ratio: step.ratio,
                hint: step.hint,
                tint: step.isMissing ? Color.secondary.opacity(0.25) : .accentColor,
                isMuted: step.isMissing) {
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
    }

    private static func percent(_ ratio: Double) -> String {
        "→ " + String(format: "%.0f%%", (ratio * 100).rounded())
    }
}

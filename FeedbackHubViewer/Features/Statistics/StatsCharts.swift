//
//  StatsCharts.swift
//  FeedbackHubViewer
//
//  해석 카드가 앞에 내세우는 차트들. 숫자 표 대신 모양으로 읽히게 한다.
//
//  색 규칙(이 앱 공통): 요점인 계열 하나만 강조색, 견줄 것은 회색. 계열이 둘 이상이면
//  범례를 두고, 값은 막대 끝에만 적는다. 글자는 데이터 색을 입지 않는다.
//

import SwiftUI
import Charts

// MARK: - 잔존 곡선

/// 깐 지 N일째에 앱을 쓴 비율. 최근 4주에 깐 사람(강조)과 그 전에 깐 사람(회색)을 겹친다.
/// 볼 것은 **모양**이다: 떨어지다 평평해지면 남는 사람이 있는 것이고, 끝까지 떨어지면 없다.
struct RetentionCurveChart: View {
    let retention: FeedbackStore.Retention

    /// 한 점이 흔들리지 않을 최소 분모.
    static let minimumEligible = 5

    private struct Point: Identifiable {
        let group: String
        let day: Int
        let ratio: Double
        var id: String { group + "\(day)" }
    }

    private static func points(_ curve: [Int: FeedbackStore.Retention.Rate], group: String) -> [Point] {
        curve.keys.sorted().compactMap { day in
            guard let rate = curve[day], rate.eligible >= minimumEligible, let ratio = rate.ratio else { return nil }
            return Point(group: group, day: day, ratio: ratio)
        }
    }

    private var series: [Point] {
        let recent = Self.points(retention.recentCurve, group: "최근 4주에 깐 사람")
        let older = Self.points(retention.olderCurve, group: "그 전에 깐 사람")
        // 둘 다 선을 그을 만큼 있어야 겹쳐 본다. 아니면 합친 곡선 하나.
        if recent.count >= 3 && older.count >= 3 { return older + recent }
        return Self.points(retention.curve, group: "전체")
    }

    private var groups: [String] {
        var seen: [String] = []
        for point in series where !seen.contains(point.group) { seen.append(point.group) }
        return seen
    }

    private func color(_ group: String) -> Color {
        group == "그 전에 깐 사람" ? Color.secondary.opacity(0.45) : Color.accentColor
    }

    var body: some View {
        let points = series
        if points.isEmpty {
            Text("곡선을 그을 만큼 설치가 쌓이지 않았습니다(한 점에 \(Self.minimumEligible)명 이상).")
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("깐 지 N일째에 앱을 쓴 비율")
                    .font(.headline)
                chart(points)
                if groups.count > 1 {
                    HStack(spacing: 14) {
                        ForEach(groups, id: \.self) { group in
                            HStack(spacing: 6) {
                                Capsule().fill(color(group)).frame(width: 16, height: 3)
                                Text(group).font(.body).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let lead = groups.last ?? "전체"
        let marked = points.filter { $0.group == lead && [1, 7, 30].contains($0.day) }
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("깐 지", point.day), y: .value("쓴 비율", point.ratio),
                         series: .value("무리", point.group))
                    .foregroundStyle(color(point.group))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(marked) { point in
                PointMark(x: .value("깐 지", point.day), y: .value("쓴 비율", point.ratio))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(50)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(point.day)일 \(StatsAnalysis.percent(point.ratio))")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
            }
        }
        .chartXScale(domain: 1...FeedbackStore.Retention.curveDays)
        .chartXAxis {
            AxisMarks(values: [1, 7, 14, 21, 30]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let day = value.as(Int.self) { Text("\(day)일") }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(StatsAnalysis.percent(v)) }
                }
            }
        }
        .frame(height: 190)
        .accessibilityLabel("잔존 곡선")
    }
}

// MARK: - 주 단위 코호트 삼각형 (Firebase · Amplitude 방식)

/// 줄은 깐 주, 칸은 그 뒤 k주째에 한 번이라도 온 비율. 아직 안 지난 칸은 비워 둬서
/// 오른쪽 아래가 삼각형으로 빈다. 진할수록 많이 남은 것.
struct CohortTriangle: View {
    let retention: FeedbackStore.Retention

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("깐 주")
                    Text("인원")
                    ForEach(1...FeedbackStore.Retention.triangleWeeks, id: \.self) { k in
                        Text("\(k)주").frame(minWidth: 48)
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(retention.cohorts) { cohort in
                    GridRow {
                        Text(cohort.start.formatted(.dateTime.month(.defaultDigits).day()))
                            .font(.body.monospacedDigit())
                        Text("\(AppFormat.count(cohort.size))명")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        ForEach(Array(cohort.weekly.enumerated()), id: \.offset) { _, rate in
                            cell(rate)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("주 단위 코호트 잔존 표")
    }

    @ViewBuilder
    private func cell(_ rate: FeedbackStore.Retention.Rate) -> some View {
        if let ratio = rate.ratio {
            Text(StatsAnalysis.percent(ratio))
                .font(.body.monospacedDigit())
                .foregroundStyle(ratio > 0.45 ? Color.white : Color.primary)
                .frame(minWidth: 48, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.08 + 0.85 * min(ratio * 1.6, 1))))
                .help("\(AppFormat.count(rate.eligible))명 중 \(AppFormat.count(rate.returned))명")
        } else {
            Color.clear.frame(minWidth: 48, minHeight: 28)
        }
    }
}

// MARK: - Lifecycle (신규 · 유지 · 복귀 · 이탈)

struct LifecycleChart: View {
    let lifecycle: FeedbackStore.Lifecycle

    private struct Part: Identifiable {
        let start: Date
        let kind: String
        let value: Int
        var id: String { "\(start.timeIntervalSince1970)\(kind)" }
    }

    static let kinds = ["유지", "신규", "복귀", "이탈"]

    private var parts: [Part] {
        lifecycle.weeks.flatMap { week in
            [Part(start: week.start, kind: "유지", value: week.retained),
             Part(start: week.start, kind: "신규", value: week.new),
             Part(start: week.start, kind: "복귀", value: week.resurrected),
             Part(start: week.start, kind: "이탈", value: -week.dormant)]
        }
    }

    var body: some View {
        Chart(parts) { part in
            BarMark(x: .value("주", part.start, unit: .weekOfYear),
                    y: .value("사람", part.value),
                    width: .ratio(0.6))
                .foregroundStyle(by: .value("구분", part.kind))
        }
        .chartForegroundStyleScale(domain: Self.kinds, range: [Color.blue, Color.green, Color.purple, Color.orange])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(abs(v))") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .frame(height: 210)
        .accessibilityLabel("주마다 신규 · 유지 · 복귀 · 이탈")
    }
}

// MARK: - 선과 견주기 (불릿 차트)

/// 앱이 정한 하한 · 목표와 지금 값. 막대 하나에 선 둘 — 불릿 차트.
/// 깔때기와 따로 두는 이유: 선은 "그 상태에 닿은 비율(순서 무관)"로 정의돼 있고,
/// 깔때기 막대는 순서대로 온 사람만 센다. 한 그림에 두면 같은 선이 다른 값과 견줘진다.
struct GoalBullet: View {
    let goal: ProjectStatsSpec.Insight.Goal

    var body: some View {
        if let reached = goal.reached {
            let state: Color = goal.floor.map { reached < $0 } == true ? .red
                : goal.target.map { reached < $0 } == true ? .orange : .green
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(goal.label ?? "마지막 칸")에 닿은 설치 (순서 무관)")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(StatsAnalysis.percent(reached))
                        .font(.title3.weight(.semibold))
                }
                Chart {
                    BarMark(xStart: .value("0", 0), xEnd: .value("선 끝", 1), y: .value("", "track"), height: .fixed(14))
                        .foregroundStyle(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    BarMark(xStart: .value("0", 0), xEnd: .value("지금", min(reached, 1)), y: .value("", "track"), height: .fixed(14))
                        .foregroundStyle(state)
                        .clipShape(Capsule())
                    if let floor = goal.floor {
                        RuleMark(x: .value("하한", floor))
                            .foregroundStyle(Color.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .annotation(position: .bottom, spacing: 2) {
                                Text("하한 \(StatsAnalysis.percent(floor))").font(.body).foregroundStyle(.secondary)
                            }
                    }
                    if let target = goal.target {
                        RuleMark(x: .value("목표", target))
                            .foregroundStyle(Color.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .annotation(position: .bottom, spacing: 2) {
                                Text("목표 \(StatsAnalysis.percent(target))").font(.body).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartXScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 52)
                Text("전체 \(AppFormat.count(goal.base))대 중 \(AppFormat.count(goal.reachedCount))대. 앞 칸을 건너뛴 사람도 셉니다. 이 앱이 그은 선은 이 값으로 판정해요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .cardSurface(radius: 10, bordered: false)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - 퍼널 (Amplitude · Mixpanel 방식)

/// 단계마다 세로 막대. 진한 부분이 그 단계까지 온 사람, 위의 연한 부분이 바로 앞
/// 단계에서 빠진 사람이다. 막대 위에는 첫 단계 대비 %, 막대 안에는 앞 단계에서
/// 넘어온 비율을 적는다.
struct FunnelChart: View {
    struct Stage: Identifiable {
        let label: String
        let count: Int
        /// 그 단계의 값을 앱이 한 번도 안 보냄 — 0명과 다르다.
        var isMissing = false
        /// 앞 단계보다 많음 — 앞을 거치지 않고도 닿는 자리라 전환율을 적지 않는다.
        var exceedsPrevious = false
        var id: String { label }
    }

    let stages: [Stage]
    /// 앱이 정한 하한(첫 단계 대비 비율). 있으면 가로선으로.
    var floor: Double? = nil

    private struct Segment: Identifiable {
        let stage: String
        let kind: String
        let value: Int
        var id: String { stage + kind }
    }

    private var first: Int { stages.first?.count ?? 0 }

    private var segments: [Segment] {
        var result: [Segment] = []
        var previous: Int?
        for stage in stages {
            if stage.isMissing {
                result.append(Segment(stage: stage.label, kind: "안 보냄", value: previous ?? first))
            } else {
                result.append(Segment(stage: stage.label, kind: "온 사람", value: stage.count))
                if let previous, previous > stage.count {
                    result.append(Segment(stage: stage.label, kind: "빠진 사람", value: previous - stage.count))
                }
                previous = stage.count
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
            conversions
        }
    }

    private var chart: some View {
        Chart {
            ForEach(segments) { segment in
                BarMark(x: .value("단계", segment.stage),
                        y: .value("사람", segment.value),
                        width: .ratio(0.62))
                    .foregroundStyle(by: .value("구분", segment.kind))
            }
            ForEach(stages) { stage in
                // 막대 꼭대기: 첫 단계 대비.
                if !stage.isMissing {
                    PointMark(x: .value("단계", stage.label), y: .value("사람", topValue(of: stage)))
                        .opacity(0)
                        .annotation(position: .top, spacing: 4) {
                            VStack(spacing: 0) {
                                Text(AppFormat.count(stage.count))
                                    .font(.body.weight(.semibold))
                                if first > 0 {
                                    Text(StatsAnalysis.percent(Double(stage.count) / Double(first)))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                } else {
                    PointMark(x: .value("단계", stage.label), y: .value("사람", topValue(of: stage)))
                        .opacity(0)
                        .annotation(position: .top, spacing: 4) {
                            Text("안 보냄").font(.body).foregroundStyle(.secondary)
                        }
                }
            }
            if let floor, first > 0 {
                RuleMark(y: .value("하한", Double(first) * floor))
                    .foregroundStyle(Color.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        Text("하한 \(StatsAnalysis.percent(floor))").font(.body).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: ["온 사람", "빠진 사람", "안 보냄"],
                                   range: [Color.accentColor, Color.accentColor.opacity(0.15), Color.secondary.opacity(0.12)])
        .chartLegend(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...Double(max(first, 1)) * 1.25)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true, multiLabelAlignment: .center) {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
            }
        }
        .frame(height: 240)
        .accessibilityLabel(stages.map { "\($0.label) \($0.isMissing ? "안 보냄" : "\($0.count)명")" }.joined(separator: ", "))
    }

    /// 단계 사이 넘어간 비율 — 막대 아래 한 줄. 가장 크게 새는 칸은 굵게.
    @ViewBuilder
    private var conversions: some View {
        let pairs = zip(stages, stages.dropFirst()).map { ($0, $1) }
        let rates: [Double?] = pairs.map { pair in
            let (a, b) = pair
            guard !a.isMissing, !b.isMissing, !b.exceedsPrevious, a.count > 0 else { return nil }
            return Double(b.count) / Double(a.count)
        }
        let worst = rates.compactMap { $0 }.min()
        FlowLayout(spacing: 10, lineSpacing: 6) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                let (a, b) = pair
                HStack(spacing: 4) {
                    Text("\(a.label) → \(b.label)")
                        .foregroundStyle(.secondary)
                    if let rate = rates[index] {
                        Text(StatsAnalysis.percent(rate))
                            .fontWeight(rate == worst ? .bold : .regular)
                            .foregroundStyle(rate == worst ? Color.red : Color.primary)
                    } else if b.exceedsPrevious {
                        Text("앞 단계 밖에서도 옴").foregroundStyle(.orange)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .font(.body)
            }
        }
    }

    private func topValue(of stage: Stage) -> Int {
        guard let index = stages.firstIndex(where: { $0.id == stage.id }) else { return stage.count }
        // 빠진 사람까지 쌓은 높이 = 앞 단계 값(더 크면).
        let previous = stages[..<index].last(where: { !$0.isMissing })?.count ?? stage.count
        return stage.isMissing ? previous : max(stage.count, previous)
    }
}

// MARK: - 며칠 왔나: 이야기인 칸만 강조

struct ActiveDaysChart: View {
    let days: FeedbackStore.ActiveDays
    /// 강조할 칸의 이름. nil 이면 전부 같은 색.
    let highlight: String?

    var body: some View {
        Chart(days.buckets) { bucket in
            let share = days.total > 0 ? Double(bucket.count) / Double(days.total) : 0
            BarMark(x: .value("사람", bucket.count),
                    y: .value("온 날", bucket.label),
                    height: .fixed(22))
                .foregroundStyle(highlight == nil || highlight == bucket.label
                                 ? Color.accentColor : Color.secondary.opacity(0.35))
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                .annotation(position: .trailing, spacing: 6) {
                    Text("\(AppFormat.count(bucket.count))명 · \(StatsAnalysis.percent(share))")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.body) }
        }
        .frame(height: CGFloat(days.buckets.count) * 34)
        .accessibilityLabel("최근 30일에 며칠 왔는지 분포")
    }
}

// MARK: - 비중 도넛

/// 도넛의 조각 하나. 조각마다 제 색을 갖는다 — 색이 곧 이름이라 범례와 같은 색이어야 한다.
struct DonutSlice: Identifiable {
    let label: String
    let value: Int
    let color: Color
    var id: String { label }
}

/// 몫을 나누는 도넛. 가운데에는 요점인 조각(첫 조각)의 비율을 적는다.
struct ShareDonut: View {
    let title: String
    let slices: [DonutSlice]
    /// 가운데 비율을 따로 정할 때(모름을 분모에서 빼는 경우 등). nil 이면 첫 조각 ÷ 전체.
    var centerRatio: Double?? = nil

    var body: some View {
        let whole = slices.reduce(0) { $0 + $1.value }
        let lead = slices.first
        let ratio: Double? = centerRatio ?? (whole > 0 ? Double(lead?.value ?? 0) / Double(whole) : nil)
        VStack(spacing: 6) {
            Chart(slices.filter { $0.value > 0 }) { slice in
                SectorMark(angle: .value(slice.label, slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(slice.color)
                    .cornerRadius(3)
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(ratio.map(StatsAnalysis.percent) ?? "—")
                        .font(.title3.weight(.semibold))
                    if let lead {
                        Text(lead.label).font(.body).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 130, height: 130)
            Text(title)
                .font(.body.weight(.semibold))
            Text("\(AppFormat.count(whole))명")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + " " + (lead.map { "\($0.label) " + (ratio.map(StatsAnalysis.percent) ?? "모름") + ", " } ?? "") + slices.map { "\($0.label) \($0.value)명" }.joined(separator: ", "))
    }
}

/// 도넛 범례 — 도넛이 여럿이어도 조각 이름은 같으니 한 번만.
struct ShareLegend: View {
    let slices: [DonutSlice]

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle().fill(slice.color).frame(width: 10, height: 10)
                    Text(slice.label).font(.body).foregroundStyle(.secondary)
                }
            }
        }
    }
}

//
//  CarryingCapacityCard.swift
//  FeedbackHubViewer
//
//  성장 상한을 한 장에 보여 주는 카드 — 계산은 `CarryingCapacity`가 하고, 여기서는
//  그 결과를 읽는 순서대로 놓기만 한다.
//
//   1. 상한과 지금 자리(막대 하나). 이 앱이 어디까지 자랄 수 있고 지금 어디쯤인가.
//   2. 그 상한을 만든 두 숫자: 기간당 신규와 기간 이탈률. 상한을 올리려면 둘 중
//      하나를 움직여야 하고, 어느 쪽이 병목인지는 나란히 놓여야 보인다.
//   3. 실제 궤적과 전망선. 식이 맞는 이야기를 하고 있는지는 과거 위에 얹어 봐야 안다.
//   4. 이 숫자가 흔들리는 이유(`caveats`). 숨기면 잘못 믿게 된다.
//

import SwiftUI
import Charts

struct CarryingCapacityCard: View {
    @EnvironmentObject private var store: FeedbackStore
    /// 이 카드가 설명하는 범위(nil == 전체 프로젝트).
    let project: String?

    @State private var period: CarryingCapacity.Period = .week
    /// 지금 켜져 있는 계열. 상한선이 실제 궤적보다 한참 위면 궤적이 바닥에
    /// 눌리는데, 그때 상한을 잠깐 끄면 궤적 자체를 읽을 수 있다.
    @State private var series = ChartSeriesSelection()
    /// 가리키고 있는 칸. 상한선까지 얼마나 남았는지는 눈금으로 못 읽는다.
    @State private var cursor: Date?

    #if os(macOS)
    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    private let chartHeight: CGFloat = 170
    #else
    private let tileColumns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]
    private let chartHeight: CGFloat = 150
    #endif

    var body: some View {
        Card(title: "성장 상한 (carrying capacity)", systemImage: "speedometer") {
            Picker("기간", selection: $period) {
                ForEach(CarryingCapacity.Period.allCases) { unit in
                    Text(unit.pickerLabel).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let result = store.carryingCapacity(for: project, period: period) {
                headline(result)
                tiles(result)
                chart(result)
                caveats(result)
                footnote(result)
            } else {
                Text("아직 활동 기록이 없어 상한을 잴 수 없습니다. 이벤트가 두 \(period.unit) 이상 쌓이면 계산됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 상한과 지금 자리

    @ViewBuilder
    private func headline(_ result: CarryingCapacity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.capacity.map { Self.count($0) } ?? "—")
                    .font(.figure(.largeTitle))
                    .foregroundStyle(result.capacity == nil ? Color.secondary : .accentColor)
                if result.capacity != nil { Text("곳").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Text(subtitle(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)

            if let fill = result.fill {
                // 상한을 넘어선 상태도 있을 수 있다(최근에 유입이 몰렸거나 이탈이
                // 잠시 멈춘 경우). 막대는 100%에서 멈추되 숫자는 그대로 말한다.
                MeterBar(ratio: fill, height: 8,
                         tint: fill >= 1 ? .orange : .accentColor)
            }
        }
    }

    /// 막대 옆에 붙는 한 줄 — 지금 몇 곳이고 상한의 몇 %인가.
    private func subtitle(_ result: CarryingCapacity) -> String {
        guard result.capacity != nil else {
            return "지금 \(result.currentActive)곳 · 상한을 계산할 수 없음"
        }
        guard let fill = result.fill else { return "지금 \(result.currentActive)곳" }
        return "지금 \(result.currentActive)곳 · 상한의 \(Self.percent(fill))"
    }

    // MARK: - 상한을 만든 숫자들

    private func tiles(_ result: CarryingCapacity) -> some View {
        LazyVGrid(columns: tileColumns, spacing: 10) {
            StatTile(title: "\(result.period.label) 신규", value: Self.decimal(result.averageNew), unit: "곳",
                     systemImage: "sparkles", tint: .green)
            StatTile(title: "\(result.period.label) 이탈률",
                     value: result.churnRate > 0 ? Self.percent(result.churnRate) : "—", unit: "",
                     systemImage: "arrow.down.right", tint: .red)
            StatTile(title: "평균 사용 수명",
                     value: result.averageLifetime.map { Self.decimal($0) } ?? "—",
                     unit: result.averageLifetime == nil ? "" : result.period.unit,
                     systemImage: "hourglass", tint: .indigo)
            StatTile(title: "지금 활동 사용자", value: "\(result.currentActive)", unit: "곳",
                     systemImage: "person.2.fill", tint: .blue)
        }
    }

    // MARK: - 궤적과 전망

    @ViewBuilder
    private func chart(_ result: CarryingCapacity) -> some View {
        // 끝난 기간만 선으로 잇는다. 진행 중인 기간은 아직 덜 찼을 뿐인데 선에
        // 넣으면 매번 마지막에서 꺾여 내려가는 것처럼 보인다.
        let done = result.history.filter { !$0.isPartial }
        let partial = result.history.first(where: \.isPartial)

        if done.count < 2 {
            Text("아직 그릴 만한 과거가 없습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Chart {
                if series.isVisible("actual") {
                    ForEach(done) { point in
                        LineMark(x: .value("기간", point.start, unit: result.period.component),
                                 y: .value("활동 사용자", point.active),
                                 series: .value("계열", "실제"))
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.monotone)
                    }
                    if let partial {
                        PointMark(x: .value("기간", partial.start, unit: result.period.component),
                                  y: .value("활동 사용자", partial.active))
                            .foregroundStyle(Color.blue.opacity(0.35))
                            .symbolSize(28)
                    }
                }
                if series.isVisible("projection") {
                    ForEach(result.projection) { point in
                        LineMark(x: .value("기간", point.date, unit: result.period.component),
                                 y: .value("활동 사용자", point.active),
                                 series: .value("계열", "전망"))
                            .foregroundStyle(Color.blue.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                if series.isVisible("capacity"), let capacity = result.capacity {
                    RuleMark(y: .value("상한", capacity))
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("상한 \(Self.count(capacity))곳")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                }
                if let date = cursorDate(result) {
                    RuleMark(x: .value("기간", date, unit: result.period.component))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartReadout(title: title(for: date, period: result.period),
                                         items: readout(at: date, result: result))
                        }
                }
            }
            .chartYScale(domain: 0...yMaximum(result))
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: chartHeight)
            .chartCursor($cursor)

            ChartLegend(series: Self.chartSeries(hasPartial: partial != nil,
                                                 unit: result.period.unit),
                        selection: $series)
        }
    }

    // MARK: - 가리킨 자리의 값

    /// 가리킨 곳에서 가장 가까운 칸의 시작. 실제 궤적과 전망선은 같은 격자 위에
    /// 있으므로 하나의 날짜로 둘 다 찾을 수 있다.
    private func cursorDate(_ result: CarryingCapacity) -> Date? {
        guard let cursor else { return nil }
        var dates = result.history.map(\.start)
        dates.append(contentsOf: result.projection.map(\.date))
        return dates.min {
            abs($0.timeIntervalSince(cursor)) < abs($1.timeIntervalSince(cursor))
        }
    }

    private func title(for date: Date, period: CarryingCapacity.Period) -> String {
        switch period {
        case .day:   return AppFormat.chartDay(date)
        case .week:  return AppFormat.chartDay(date) + " 주"
        case .month: return AppFormat.chartMonth(date)
        }
    }

    /// 그 칸에서 켜져 있는 계열의 값. 전망선은 관측이 아니므로 그 사실이 이름에
    /// 이미 들어 있고(“전망”), 실제 궤적이 있는 칸에는 전망을 적지 않는다 —
    /// 같은 자리에 두 숫자가 있으면 어느 쪽이 일어난 일인지 헷갈린다.
    private func readout(at date: Date, result: CarryingCapacity) -> [ChartReadout.Item] {
        var items: [ChartReadout.Item] = []
        let actual = result.history.first { $0.start == date }
        if series.isVisible("actual"), let actual {
            items.append(.init(label: actual.isPartial ? "활동 사용자 (진행 중)" : "활동 사용자",
                               value: "\(actual.active)곳",
                               color: .blue))
            if let churn = actual.churnRate {
                items.append(.init(label: "이탈률", value: Self.percent(churn), color: .red))
            }
            items.append(.init(label: "신규", value: "\(actual.new)곳", color: .green))
        }
        if series.isVisible("projection"), actual == nil,
           let projected = result.projection.first(where: { $0.date == date }) {
            items.append(.init(label: "전망", value: "\(Self.count(projected.active))곳",
                               color: Color.blue.opacity(0.55)))
        }
        if series.isVisible("capacity"), let capacity = result.capacity {
            items.append(.init(label: "상한", value: "\(Self.count(capacity))곳", color: .orange))
        }
        return items
    }

    /// 축은 **켜진 계열**만 보고 잡는다. 상한이 궤적보다 한참 위일 때 상한을 끄면
    /// 눈금이 궤적 크기로 내려오는 것이 이 카드에서 계열을 끄는 이유다.
    /// 여백은 10%만.
    private func yMaximum(_ result: CarryingCapacity) -> Double {
        var tops: [Double] = []
        if series.isVisible("actual") { tops.append(Double(result.history.map(\.active).max() ?? 0)) }
        if series.isVisible("projection") { tops.append(result.projection.map(\.active).max() ?? 0) }
        if series.isVisible("capacity"), let capacity = result.capacity { tops.append(capacity) }
        return max(1, (tops.max() ?? 0) * 1.1)
    }

    /// 진행 중인 칸은 실제 궤적에 딸린 표시라 따로 켜고 끄지 않는다 — 범례에는
    /// 그런 점이 있다는 사실만 적는다.
    private static func chartSeries(hasPartial: Bool, unit: String) -> [ChartSeries] {
        var list = [
            ChartSeries("actual", hasPartial ? "활동 사용자 (연한 점 = 진행 중인 \(unit))" : "활동 사용자", .blue),
            ChartSeries("projection", "전망 (지금 속도가 이어질 때)", Color.blue.opacity(0.55), isDashed: true),
            ChartSeries("capacity", "상한", .orange, isDashed: true)
        ]
        if !hasPartial { list[0] = ChartSeries("actual", "활동 사용자", .blue) }
        return list
    }

    // MARK: - 주의와 설명

    @ViewBuilder
    private func caveats(_ result: CarryingCapacity) -> some View {
        if !result.caveats.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.caveats, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .cardSurface(radius: 8, bordered: false)
        }
    }

    private func footnote(_ result: CarryingCapacity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("이건 \(result.period.activityName)의 상한입니다 — 위 활성 사용자 카드의 그 숫자가 결국 멈추는 자리예요. 상한 = \(result.period.label) 신규 ÷ \(result.period.label) 이탈률. 지금 속도로 유입되고 지금 비율로 빠져나가면 활동 사용자는 이 값 근처에서 멈춥니다 — 유입을 늘리거나 이탈을 줄이지 않는 한 그 위로는 가지 않습니다.")
            Text("선 위를 가리키면 그 \(result.period.unit)의 정확한 값(활동 사용자·이탈률·신규)이 나옵니다. 범례를 누르면 계열이 켜지고 꺼져요. 최근 \(result.sampleCount)\(result.period.unit)치(진행 중인 \(result.period.unit) 제외)의 평균입니다. 활동 사용자 = 그 기간에 이벤트를 보낸 설치, 신규 = 이 허브에서 처음 활동한 설치, 이탈 = 지난 기간에 활동했는데 이번 기간에 아무것도 보내지 않은 설치.")
            Text("앱이 주요 행동만 보내므로, 열어만 보고 아무것도 하지 않은 설치는 활동에 들어오지 않습니다. 스토어 다운로드 수와도 다른 숫자입니다.")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 형식

    private static func count(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func percent(_ ratio: Double) -> String {
        let scaled = ratio * 100
        return scaled < 10 ? String(format: "%.1f%%", scaled) : String(format: "%.0f%%", scaled.rounded())
    }
}

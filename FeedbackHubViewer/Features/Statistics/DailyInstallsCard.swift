//
//  DailyInstallsCard.swift
//  FeedbackHubViewer
//
//  "하루에 몇 대가 새로 들어오나" — 일별 신규 설치 막대. 같은 숫자가 원본 데이터의
//  '기간별 추이'에도 선 하나로 있지만, 거기는 접혀 있고 다른 두 계열에 눌려
//  바닥에 붙는다. 유입은 따로 볼 만한 질문이라 한 장을 통째로 준다.
//  계산은 `FeedbackStore.dailyInstalls(for:audience:)`.
//
//  전체 프로젝트(`project == nil`)에서는 앱마다 색을 달리 쌓는다. 막대 높이는 그날
//  들어온 전부이고, 띠가 어느 앱에서 왔는지를 말한다 — 이 화면은 합이 아니라 비교라서
//  (`ProjectComparisonView`) 합만 그리면 무엇이 움직였는지가 사라진다.
//

import SwiftUI
import Charts

struct DailyInstallsCard: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String?
    let audience: FeedbackStore.Audience

    @State private var range: Range = .month
    @State private var cursor: Date?

    #if os(macOS)
    private let chartHeight: CGFloat = 180
    #else
    private let chartHeight: CGFloat = 150
    #endif

    /// 쌓아 그릴 앱의 수. 그보다 많으면 작은 앱들은 '기타' 한 띠로 묶는다 —
    /// 색이 열 개를 넘으면 범례와 막대를 눈으로 짝지을 수 없다.
    private static let maxBands = 6
    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
    private static let othersName = "기타"

    /// 쌓인 막대의 한 띠 — 한 앱(또는 '기타')의 보이는 기간 일별 설치.
    struct Band: Identifiable {
        var id: String { name }
        let name: String
        let color: Color
        let days: [FeedbackStore.DailyInstall]
        var total: Int { days.reduce(0) { $0 + $1.count } }
    }

    /// 몇 날을 보여 줄지. `전체` 는 첫 설치일부터.
    enum Range: Int, CaseIterable, Identifiable {
        case twoWeeks = 14, month = 30, quarter = 90, year = 365, all = 0
        var id: Int { rawValue }

        var label: String {
            switch self {
            case .twoWeeks: return "2주"
            case .month: return "30일"
            case .quarter: return "90일"
            case .year: return "1년"
            case .all: return "전체"
            }
        }
    }

    var body: some View {
        let perApp = project == nil ? appHistories : []
        let all = project == nil ? Self.summed(perApp.map(\.days))
                                 : store.dailyInstalls(for: project, audience: audience)
        let days = range == .all ? all : Array(all.suffix(range.rawValue))
        let bands = Self.bands(perApp, from: days.first?.date)

        Card(title: "일별 신규 설치", systemImage: "arrow.down.app") {
            Picker("기간", selection: $range) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if days.isEmpty {
                Text("설치일(installDate)을 보낸 스냅샷이 아직 없습니다. 앱이 스냅샷을 보내기 시작하면 하루하루 새로 들어온 설치가 여기 막대로 쌓여요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                figures(days, bands: bands)
                chart(days, history: all, bands: bands)
                Text((bands.isEmpty ? "" : "막대 하나가 그날 모든 앱에 새로 들어온 설치이고, 색이 앱입니다. 들어온 수가 많은 \(Self.maxBands)개 앱 밖은 '\(Self.othersName)'로 묶었어요. ")
                     + "스냅샷의 설치일(installDate)로 셉니다. 앱을 지웠다 다시 깔면 새 설치로 한 번 더 들어가요. 맨 오른쪽 오늘 막대는 아직 끝나지 않은 하루라 흐리게 그리고, 하루 평균에서도 뺐습니다."
                     + (days.count >= 30 ? " 선은 앞 7일의 평균이라 요일 들쭉날쭉을 걸러 방향만 보여 줍니다." : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 숫자

    @ViewBuilder
    private func figures(_ days: [FeedbackStore.DailyInstall], bands: [Band]) -> some View {
        let finished = days.dropLast()
        let total = days.reduce(0) { $0 + $1.count }
        let average = finished.isEmpty ? 0 : Double(finished.reduce(0) { $0 + $1.count }) / Double(finished.count)
        let best = days.max { $0.count < $1.count }

        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Figure("\(days.count)일 합계", "\(total)대")
            Figure("하루 평균", String(format: "%.1f대", average), note: "오늘 제외")
            if let best, best.count > 0 {
                Figure("가장 많았던 날", "\(best.count)대", note: AppFormat.chartDay(best.date))
            }
            Figure("오늘 지금까지", "\(days.last?.count ?? 0)대", note: "진행 중")
            if let top = bands.filter({ $0.name != Self.othersName }).max(by: { $0.total < $1.total }),
               top.total > 0 {
                Figure("가장 많이 들어온 앱", top.name, note: "\(top.total)대")
            }
        }
    }

    // MARK: 그래프

    @ViewBuilder
    private func chart(_ days: [FeedbackStore.DailyInstall],
                       history: [FeedbackStore.DailyInstall],
                       bands: [Band]) -> some View {
        let peak = days.map(\.count).max() ?? 0
        // 평균은 잘라 내기 전의 전체로 낸다 — 보이는 첫 날부터 선이 이어지게.
        let start = days.first?.date ?? .distantPast
        let average = days.count >= 30
            ? Self.trailingAverage(history, window: 7).filter { $0.date >= start } : []
        let today = days.last?.date

        Chart {
            if bands.isEmpty {
                ForEach(days) { day in
                    BarMark(x: .value("날짜", day.date, unit: .day),
                            y: .value("신규 설치", day.count))
                        .foregroundStyle(Color.green.opacity(day.date == today ? 0.35 : 0.8))
                }
            } else {
                ForEach(bands) { band in
                    ForEach(band.days) { day in
                        BarMark(x: .value("날짜", day.date, unit: .day),
                                y: .value("신규 설치", day.count))
                            .foregroundStyle(by: .value("앱", band.name))
                            .opacity(day.date == today ? 0.4 : 0.85)
                    }
                }
            }
            ForEach(average, id: \.date) { point in
                LineMark(x: .value("날짜", point.date, unit: .day),
                         y: .value("7일 평균", point.value))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let point = selected(days) {
                RuleMark(x: .value("날짜", point.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartReadout(title: AppFormat.chartDay(point.date),
                                     items: readout(point, average: average, bands: bands))
                    }
            }
        }
        // 0에서 시작해야 하루 한두 대 차이가 절벽처럼 보이지 않는다.
        .chartYScale(domain: 0...Double(max(1, peak)))
        .chartYAxis { AxisMarks(position: .leading) }
        .chartForegroundStyleScale(domain: bands.map(\.name), range: bands.map(\.color))
        .chartLegend(bands.isEmpty ? .hidden : .visible)
        .frame(height: chartHeight)
        .chartCursor($cursor)
    }

    private func selected(_ days: [FeedbackStore.DailyInstall]) -> FeedbackStore.DailyInstall? {
        guard let cursor else { return nil }
        return days.min {
            abs($0.date.timeIntervalSince(cursor)) < abs($1.date.timeIntervalSince(cursor))
        }
    }

    private func readout(_ day: FeedbackStore.DailyInstall,
                         average: [(date: Date, value: Double)],
                         bands: [Band]) -> [ChartReadout.Item] {
        var items = [ChartReadout.Item(label: bands.isEmpty ? "신규 설치" : "모든 앱", value: "\(day.count)대",
                                       color: bands.isEmpty ? .green : .secondary)]
        // 그날 들어온 앱만, 많은 순으로. 0대인 띠까지 적으면 패널이 막대를 덮는다.
        let counts = bands.compactMap { band -> (Band, Int)? in
            guard let count = band.days.first(where: { $0.date == day.date })?.count, count > 0 else { return nil }
            return (band, count)
        }
        for (band, count) in counts.sorted(by: { $0.1 > $1.1 }) {
            items.append(.init(label: band.name, value: "\(count)대", color: band.color))
        }
        if let mean = average.first(where: { $0.date == day.date }) {
            items.append(.init(label: "7일 평균", value: String(format: "%.1f대", mean.value),
                               color: .primary.opacity(0.55)))
        }
        return items
    }

    // MARK: 전체 프로젝트

    /// 앱마다의 일별 설치 전체 이력. 숫자는 한 앱 화면과 같은 계산이라, 여기서 본
    /// 띠를 그 앱에서 열면 같은 막대가 나온다.
    private var appHistories: [(name: String, days: [FeedbackStore.DailyInstall])] {
        store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject }
            .map { (store.displayName(for: $0), store.dailyInstalls(for: $0, audience: audience)) }
            .filter { !$0.1.isEmpty }
    }

    /// 앱마다 시작일이 다른 이력을 날짜로 맞춰 더한다. 모두 오늘에서 끝나므로 끝은 같다.
    static func summed(_ histories: [[FeedbackStore.DailyInstall]]) -> [FeedbackStore.DailyInstall] {
        var counts: [Date: Int] = [:]
        for history in histories {
            for day in history { counts[day.date, default: 0] += day.count }
        }
        return counts.keys.sorted().map { FeedbackStore.DailyInstall(date: $0, count: counts[$0] ?? 0) }
    }

    /// 보이는 기간(`start` 부터)에서 많이 들어온 앱 순으로 띠를 만든다. 넘치는 앱은 '기타'.
    static func bands(_ histories: [(name: String, days: [FeedbackStore.DailyInstall])],
                      from start: Date?) -> [Band] {
        guard let start, !histories.isEmpty else { return [] }
        var visible: [Band] = []
        for app in histories {
            let days = app.days.filter { $0.date >= start }
            let band = Band(name: app.name, color: .gray, days: days)
            if band.total > 0 { visible.append(band) }
        }
        visible.sort { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }

        let fits = visible.count <= maxBands
        let named: [Band] = fits ? visible : Array(visible.prefix(maxBands - 1))
        var bands: [Band] = []
        for (index, app) in named.enumerated() {
            bands.append(Band(name: app.name, color: palette[index % palette.count], days: app.days))
        }
        if !fits {
            let rest: [[FeedbackStore.DailyInstall]] = visible.dropFirst(maxBands - 1).map { $0.days }
            bands.append(Band(name: othersName, color: .gray, days: summed(rest)))
        }
        return bands
    }

    /// 그날까지 앞 `window` 일의 평균. 끝나지 않은 오늘은 넣지 않는다 — 넣으면 아침마다
    /// 선 끝이 꺾여 내려간다. 창이 다 차기 전의 날도 그리지 않는다.
    static func trailingAverage(_ days: [FeedbackStore.DailyInstall],
                                window: Int) -> [(date: Date, value: Double)] {
        let finished = Array(days.dropLast())
        guard finished.count >= window else { return [] }
        var result: [(date: Date, value: Double)] = []
        var sum = finished.prefix(window).reduce(0) { $0 + $1.count }
        result.append((finished[window - 1].date, Double(sum) / Double(window)))
        for index in window..<finished.count {
            sum += finished[index].count - finished[index - window].count
            result.append((finished[index].date, Double(sum) / Double(window)))
        }
        return result
    }
}

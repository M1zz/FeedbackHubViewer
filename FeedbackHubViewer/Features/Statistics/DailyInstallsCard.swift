//
//  DailyInstallsCard.swift
//  FeedbackHubViewer
//
//  "하루에 몇 대가 새로 들어오나" — 일별 신규 설치 막대. 같은 숫자가 원본 데이터의
//  '기간별 추이'에도 선 하나로 있지만, 거기는 접혀 있고 다른 두 계열에 눌려
//  바닥에 붙는다. 유입은 따로 볼 만한 질문이라 한 장을 통째로 준다.
//  계산은 `FeedbackStore.dailyInstalls(for:audience:)`.
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
        let all = store.dailyInstalls(for: project, audience: audience)
        let days = range == .all ? all : Array(all.suffix(range.rawValue))

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
                figures(days)
                chart(days, history: all)
                Text("스냅샷의 설치일(installDate)로 셉니다. 앱을 지웠다 다시 깔면 새 설치로 한 번 더 들어가요. 맨 오른쪽 오늘 막대는 아직 끝나지 않은 하루라 흐리게 그리고, 하루 평균에서도 뺐습니다."
                     + (days.count >= 30 ? " 선은 앞 7일의 평균이라 요일 들쭉날쭉을 걸러 방향만 보여 줍니다." : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 숫자

    @ViewBuilder
    private func figures(_ days: [FeedbackStore.DailyInstall]) -> some View {
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
        }
    }

    // MARK: 그래프

    @ViewBuilder
    private func chart(_ days: [FeedbackStore.DailyInstall],
                       history: [FeedbackStore.DailyInstall]) -> some View {
        let peak = days.map(\.count).max() ?? 0
        // 평균은 잘라 내기 전의 전체로 낸다 — 보이는 첫 날부터 선이 이어지게.
        let start = days.first?.date ?? .distantPast
        let average = days.count >= 30
            ? Self.trailingAverage(history, window: 7).filter { $0.date >= start } : []
        let today = days.last?.date

        Chart {
            ForEach(days) { day in
                BarMark(x: .value("날짜", day.date, unit: .day),
                        y: .value("신규 설치", day.count))
                    .foregroundStyle(Color.green.opacity(day.date == today ? 0.35 : 0.8))
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
                                     items: readout(point, average: average))
                    }
            }
        }
        // 0에서 시작해야 하루 한두 대 차이가 절벽처럼 보이지 않는다.
        .chartYScale(domain: 0...Double(max(1, peak)))
        .chartYAxis { AxisMarks(position: .leading) }
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
                         average: [(date: Date, value: Double)]) -> [ChartReadout.Item] {
        var items = [ChartReadout.Item(label: "신규 설치", value: "\(day.count)대", color: .green)]
        if let mean = average.first(where: { $0.date == day.date }) {
            items.append(.init(label: "7일 평균", value: String(format: "%.1f대", mean.value),
                               color: .primary.opacity(0.55)))
        }
        return items
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

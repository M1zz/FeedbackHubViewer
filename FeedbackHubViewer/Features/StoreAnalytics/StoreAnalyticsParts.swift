//
//  StoreAnalyticsParts.swift
//  FeedbackHubViewer
//
//  스토어 분석 카드들이 같이 쓰는 조각 — 몫 막대 목록, 두 줄 추이 차트, 숫자 꼴.
//

import SwiftUI
import Charts

// MARK: - 숫자 꼴

enum AnalyticsFormat {
    static func count(_ value: Double) -> String { AppFormat.count(Int(value.rounded())) }

    static func percent(_ ratio: Double) -> String {
        ratio >= 0.1 ? String(format: "%.0f%%", ratio * 100) : String(format: "%.1f%%", ratio * 100)
    }

    static func usd(_ value: Double) -> String { String(format: "$%.2f", value) }

    static func decimal(_ value: Double) -> String { String(format: "%.1f", value) }

    /// 초 → "29초" · "1분 12초".
    static func seconds(_ value: Double) -> String {
        let total = Int(value.rounded())
        guard total >= 60 else { return "\(total)초" }
        let minutes = total / 60, rest = total % 60
        return rest == 0 ? "\(minutes)분" : "\(minutes)분 \(rest)초"
    }

    /// 밀리초 → "10.3초".
    static func milliseconds(_ value: Double) -> String { String(format: "%.1f초", value / 1000) }
}

// MARK: - 몫 막대

/// 한 열을 값으로 나눈 몫 — 위에서 `limit` 개, 나머지는 "그 밖 N개" 로 접는다.
struct ShareList: View {
    let title: String
    let shares: [AnalyticsShare]
    var limit = 6
    var tint: Color = .accentColor
    /// 오른쪽에 쓸 값. 기본은 건수.
    var format: (Double) -> String = AnalyticsFormat.count
    /// 몫(%)을 같이 쓰나. 평균처럼 더할 수 없는 값이면 끈다.
    var showsShare = true

    @State private var showsAll = false

    var body: some View {
        if !shares.isEmpty {
            let total = shares.reduce(0) { $0 + $1.value }
            let peak = shares.map(\.value).max() ?? 0
            let shown = showsAll ? shares : Array(shares.prefix(limit))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(shown) { share in
                    SpecBar(label: StoreAnalytics.word(share.key),
                            value: format(share.value) + (showsShare && total > 0 ? " · " + AnalyticsFormat.percent(share.value / total) : ""),
                            ratio: peak > 0 ? share.value / peak : 0,
                            tint: tint)
                }
                if shares.count > limit {
                    Button(showsAll ? "접기" : "그 밖 \(shares.count - limit)개 더 보기") { showsAll.toggle() }
                        .buttonStyle(.borderless)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 몫 목록 여럿을 넓으면 두 칸, 좁으면 한 칸으로.
struct ShareGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            content
        }
    }
}

// MARK: - 두 줄 추이

/// 날짜마다 두 값 — 앞 값은 실선, 뒤 값은 다른 색 실선.
struct AnalyticsDayChart: View {
    let points: [AnalyticsDayPoint]
    let first: ChartSeries
    let second: ChartSeries
    var format: (Double) -> String = AnalyticsFormat.count

    @State private var selection = ChartSeriesSelection()
    @State private var cursor: Date?

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let first: Double
        let second: Double
    }

    var body: some View {
        let points = self.points.compactMap { point in
            KeywordHistory.date(fromDayKey: point.day).map { Point(date: $0, first: point.first, second: point.second) }
        }
        if points.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                chart(points)
                ChartLegend(series: [first, second], selection: $selection)
            }
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let showsFirst = selection.isVisible(first.id)
        let showsSecond = selection.isVisible(second.id)
        let peak = points.reduce(0.0) { max($0, max(showsFirst ? $1.first : 0, showsSecond ? $1.second : 0)) }
        let nearest = cursor.flatMap { cursor in
            points.min { abs($0.date.timeIntervalSince(cursor)) < abs($1.date.timeIntervalSince(cursor)) }
        }
        return Chart {
            if showsFirst {
                ForEach(points) { point in
                    LineMark(x: .value("날짜", point.date, unit: .day), y: .value("값", point.first),
                             series: .value("계열", first.label))
                        .foregroundStyle(first.color)
                        .interpolationMethod(.monotone)
                }
            }
            if showsSecond {
                ForEach(points) { point in
                    LineMark(x: .value("날짜", point.date, unit: .day), y: .value("값", point.second),
                             series: .value("계열", second.label))
                        .foregroundStyle(second.color)
                        .interpolationMethod(.monotone)
                }
            }
            if let nearest {
                RuleMark(x: .value("날짜", nearest.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartReadout(title: AppFormat.chartDay(nearest.date), items: [
                            .init(label: first.label, value: format(nearest.first), color: first.color),
                            .init(label: second.label, value: format(nearest.second), color: second.color)
                        ])
                    }
            }
        }
        .chartYScale(domain: 0...max(1, peak))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 170)
        .chartCursor($cursor)
    }
}

// MARK: - 글

struct AnalyticsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 한 줄 결론 — 카드 맨 위의 굵은 문장.
struct AnalyticsHeadline: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 숫자 여럿을 한 줄에, 좁으면 두 줄로.
struct FigureRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .topLeading)],
                  alignment: .leading, spacing: 12) {
            content
        }
    }
}

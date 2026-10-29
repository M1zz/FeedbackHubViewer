//
//  Sparkline.swift
//  FeedbackHubViewer
//
//  A 14-day event sparkline. Deliberately axis-free: it shows the shape of the
//  last two weeks, not exact values. Used by the project cards, the sidebar
//  rows and the dashboard alike, which is why it lives here and not on any one
//  of those screens.
//
//  오늘은 그리지 않는다. 아직 끝나지 않은 하루라 늘 어제보다 작아서, 한눈에 보는 자리에서는
//  모든 앱이 끝에서 꺾여 내려가는 것처럼 보였다. 오늘이 차오르는 모습은 상세 화면의
//  그래프가 보여 준다.
//

import SwiftUI
import Charts

struct Sparkline: View {
    let points: [FeedbackStore.DayCount]

    /// 끝난 날들만.
    private var settled: [FeedbackStore.DayCount] {
        let today = Calendar.current.startOfDay(for: Date())
        return points.filter { $0.date < today }
    }

    var body: some View {
        let points = settled
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

//
//  Sparkline.swift
//  FeedbackHubViewer
//
//  A 14-day event sparkline. Deliberately axis-free: it shows the shape of the
//  last two weeks, not exact values. Used by the project cards, the sidebar
//  rows and the dashboard alike, which is why it lives here and not on any one
//  of those screens.
//

import SwiftUI
import Charts

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

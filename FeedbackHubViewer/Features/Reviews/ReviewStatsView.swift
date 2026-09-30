//
//  ReviewStatsView.swift
//  FeedbackHubViewer
//
//  한 앱 리뷰의 숫자 — ReviewManager 통계 탭의 리뷰 카드들(주요 지표 · 평점 분포 ·
//  나라별 분포 · 추이 · 응답 분석).
//
//  응답 시간은 "응답을 마지막으로 고친 때 − 리뷰가 올라온 때"다. App Store Connect 는
//  처음 단 때를 따로 주지 않아서, 나중에 고친 응답은 실제보다 늦게 답한 것으로 잡힌다.
//

import SwiftUI
import Charts

struct ReviewStatsView: View {
    let reviews: [CustomerReview]

    enum Period: String, CaseIterable, Identifiable {
        case day = "1일"
        case week = "7일"
        case month = "30일"
        case all = "전체"
        var id: String { rawValue }

        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }

    @State private var period: Period = .month

    private var scoped: [CustomerReview] {
        guard let days = period.days else { return reviews }
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        return reviews.filter { $0.createdDate >= cutoff }
    }

    var body: some View {
        let scoped = self.scoped
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("기간", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                if scoped.isEmpty {
                    Card(title: "리뷰 없음", systemImage: "chart.bar.xaxis") {
                        Text(reviews.isEmpty ? "받아 둔 리뷰가 없습니다." : "최근 \(period.rawValue)에 올라온 리뷰가 없습니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    keyMetrics(scoped)
                    distribution(scoped)
                    trend(scoped)
                    territories(scoped)
                    responses(scoped)
                }
            }
            .padding(ReviewLayout.padding)
        }
    }

    // MARK: 주요 지표

    private func keyMetrics(_ reviews: [CustomerReview]) -> some View {
        let total = reviews.count
        let positive = reviews.filter { $0.rating >= 4 }.count
        let negative = reviews.filter { $0.rating <= 2 }.count
        let neutral = total - positive - negative
        let answered = reviews.filter { $0.response != nil }.count
        return LazyVGrid(columns: ReviewLayout.tileColumns, spacing: 10) {
            StatTile(title: "평균 평점", value: String(format: "%.2f", PriorityScorer.average(reviews) ?? 0),
                     systemImage: "star.fill", tint: .yellow)
            StatTile(title: "리뷰", value: AppFormat.count(total), unit: "건",
                     systemImage: "text.bubble", tint: .blue)
            StatTile(title: "긍정 (4~5점)", value: "\(positive)", unit: Self.percent(positive, of: total),
                     systemImage: "hand.thumbsup", tint: .green)
            StatTile(title: "부정 (1~2점)", value: "\(negative)", unit: Self.percent(negative, of: total),
                     systemImage: "hand.thumbsdown", tint: .red)
            StatTile(title: "중립 (3점)", value: "\(neutral)", unit: Self.percent(neutral, of: total),
                     systemImage: "minus.circle", tint: .orange)
            StatTile(title: "응답률", value: Self.percent(answered, of: total),
                     systemImage: "checkmark.bubble", tint: .green)
            StatTile(title: "새 리뷰 (24시간)", value: "\(reviews.filter(\.isNew).count)", unit: "건",
                     systemImage: "sparkles", tint: .purple)
            StatTile(title: "답 안 함", value: "\(total - answered)", unit: "건",
                     systemImage: "exclamationmark.bubble", tint: total == answered ? .secondary : .orange)
        }
    }

    // MARK: 평점 분포

    private func distribution(_ reviews: [CustomerReview]) -> some View {
        let counts = Dictionary(grouping: reviews, by: \.rating).mapValues(\.count)
        return Card(title: "평점 분포", systemImage: "star.leadinghalf.filled") {
            VStack(spacing: 8) {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    let count = counts[stars] ?? 0
                    barRow(label: "\(stars)점", ratio: Double(count) / Double(reviews.count),
                           value: "\(count)건 · \(Self.percent(count, of: reviews.count))",
                           tint: ReviewLayout.ratingTint(stars))
                }
            }
        }
    }

    // MARK: 추이

    private struct Bucket: Identifiable {
        let date: Date
        let count: Int
        let average: Double
        var id: Date { date }
    }

    private var bucketUnit: Calendar.Component {
        switch period {
        case .day: return .hour
        case .week, .month: return .day
        case .all: return .month
        }
    }

    private func trend(_ reviews: [CustomerReview]) -> some View {
        let calendar = Calendar.current
        let unit = bucketUnit
        let grouped = Dictionary(grouping: reviews) { review in
            calendar.dateInterval(of: unit, for: review.createdDate)?.start ?? review.createdDate
        }
        let buckets = grouped.map { date, items in
            Bucket(date: date, count: items.count, average: PriorityScorer.average(items) ?? 0)
        }
        .sorted { $0.date < $1.date }

        return Card(title: "리뷰 추이", systemImage: "chart.bar") {
            Chart(buckets) { bucket in
                BarMark(x: .value("때", bucket.date, unit: unit),
                        y: .value("리뷰", bucket.count))
                    .foregroundStyle(ReviewLayout.ratingTint(Int(bucket.average.rounded())).gradient)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            Text(unitCaption + " 막대 색은 그 칸의 평균 평점입니다 — 초록이 5점, 빨강이 1점 쪽.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unitCaption: String {
        switch bucketUnit {
        case .hour: return "시간마다 올라온 리뷰 수."
        case .month: return "달마다 올라온 리뷰 수."
        default: return "하루마다 올라온 리뷰 수."
        }
    }

    // MARK: 나라별

    private func territories(_ reviews: [CustomerReview]) -> some View {
        let grouped = Dictionary(grouping: reviews, by: \.territory)
            .map { (code: $0.key, reviews: $0.value) }
            .sorted { $0.reviews.count > $1.reviews.count }
        let top = grouped.prefix(10)
        return Card(title: "나라별 리뷰", systemImage: "globe") {
            VStack(spacing: 8) {
                ForEach(top, id: \.code) { item in
                    let average = PriorityScorer.average(item.reviews) ?? 0
                    barRow(label: ReviewTerritory.name(for: item.code),
                           ratio: Double(item.reviews.count) / Double(reviews.count),
                           value: "\(item.reviews.count)건 · " + String(format: "평균 %.1f", average),
                           tint: .blue)
                }
            }
            if grouped.count > top.count {
                Text("그 밖의 \(grouped.count - top.count)개 나라는 줄였습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 응답

    private func responses(_ reviews: [CustomerReview]) -> some View {
        let answered = reviews.filter { $0.response != nil }
        let delays = answered.compactMap { review in
            review.response.map { $0.lastModifiedDate.timeIntervalSince(review.createdDate) }
        }.filter { $0 >= 0 }
        let fast = delays.filter { $0 < 24 * 3600 }.count
        let averageDelay = delays.isEmpty ? nil : delays.reduce(0, +) / Double(delays.count)

        return Card(title: "응답 분석", systemImage: "bubble.left.and.bubble.right") {
            LazyVGrid(columns: ReviewLayout.tileColumns, spacing: 10) {
                StatTile(title: "답한 리뷰", value: "\(answered.count)", unit: "건",
                         systemImage: "checkmark.bubble", tint: .green)
                StatTile(title: "응답률", value: Self.percent(answered.count, of: reviews.count),
                         systemImage: "percent", tint: .blue)
                StatTile(title: "24시간 안에 답함", value: "\(fast)", unit: Self.percent(fast, of: answered.count),
                         systemImage: "bolt", tint: .orange)
                StatTile(title: "평균 응답 시간", value: averageDelay.map(Self.duration) ?? "—",
                         systemImage: "clock", tint: .purple)
            }
            Text("별점마다 답한 비율")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(spacing: 8) {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    let group = reviews.filter { $0.rating == stars }
                    if !group.isEmpty {
                        let done = group.filter { $0.response != nil }.count
                        barRow(label: "\(stars)점", ratio: Double(done) / Double(group.count),
                               value: "\(done)/\(group.count) · \(Self.percent(done, of: group.count))",
                               tint: .green)
                    }
                }
            }
            Text("응답 시간은 응답을 마지막으로 고친 때로 잽니다. 나중에 고친 응답은 실제보다 늦게 잡혀요.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 부품

    private func barRow(label: String, ratio: Double, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            MeterBar(ratio: ratio, height: 8, tint: tint)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 96, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "—" }
        return "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        if hours >= 24 { return "\(hours / 24)일" }
        if hours > 0 { return "\(hours)시간" }
        return "\(max(1, Int(interval) / 60))분"
    }
}

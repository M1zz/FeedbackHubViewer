//
//  AppChartsBoard.swift
//  FeedbackHubViewer
//
//  홈의 세 번째 얼굴 — 앱 전부를 그래프 몇 장에 앱 아이콘으로 찍어 한눈에 견준다.
//  앱 이름 서른 개보다 아이콘 서른 개가 빨리 읽힌다(`AppIcon` 머리말).
//
//  그래프마다 **고정 기준**(세로줄 · 가로줄)으로 4분면을 나누고, 칸마다 이름 · 앱 · 할 일을 적는다.
//  절대 숫자만으로는 앱이 어떤 상태인지 읽기 어렵다 — 어느 칸에 있느냐가 곧 상태다(`Criterion`).
//
//   · 수익: 30일 다운로드 × 유료 전환 — 받는데 안 삼 · 잘 버는 중 · 작지만 잘 팜 · 작고 안 팜.
//   · 성장: 7일 쓰는 사람 × 지난주 대비 — 주력인데 줄어듦 · 주력 크는 중 · 떠오름 · 작고 줄어듦.
//   · 진열: 30일 노출 × 받는 몫 — 보이는데 안 받음 · 잘 팔리는 진열 · 받는데 안 보임.
//   · 안정성: 쓰는 사람 × 100명당 크래시 — 많이 쓰는데 불안정이 먼저.
//   · 평판: 리뷰 수 × 평균 별점 — 리뷰 많은데 불만 · 좋은데 리뷰 적음 · 사랑받음.
//   · 30일 첫 다운로드 순위 — 막대 끝에 아이콘.
//
//  점에 마우스를 올리면 앱 이름과 두 숫자, 누르면 그 앱의 그 칸으로 간다.
//  숫자가 없는 앱(스토어 리포트 없음 · 허브 기록 없음)은 그 그래프에서만 빠지고, 몇 개 빠졌는지 적는다.
//

import SwiftUI
import Charts

struct AppChartsBoard: View {
    let rows: [AppGridHome.Row]

    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @ObservedObject private var icons = StoreIcons.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("앱마다 아이콘 하나. 그래프마다 세로줄 · 가로줄이 **기준**이라, 어느 칸에 있느냐가 곧 그 앱의 상태입니다. 그래프 아래에 칸마다 어떤 앱이 있고 무엇을 하면 되는지 적었습니다. 아이콘을 누르면 그 앱의 칸이 열립니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 16)], spacing: 16) {
                revenueChart
                growthChart
                exposureChart
                crashChart
                reviewChart
                downloadsChart
            }
        }
        .task(id: rows.map(\.project)) {
            // 수익 4분면은 상품 목록으로 결제를 앱에 잇는다. 이미 받은 앱은 건너뛴다.
            await purchases.loadSales()
            for row in rows where purchases.products(for: row.project) == nil {
                await purchases.loadCatalog(bundleID: row.project)
            }
        }
    }

    // MARK: - 기준

    /// 4분면의 기준. 가운데값이 아니라 고정값 — 앱이 늘거나 줄어도 칸의 뜻이 그대로다.
    enum Criterion {
        /// 7일 쓰는 사람 — 홈이 "사용 급감" 을 세기 시작하는 크기와 같다.
        static let users = 20.0
        /// 30일 노출 — 이보다 적으면 비율이 흔들린다(`AppPotential.Benchmark.minImpressions`).
        static let impressions = Double(AppPotential.Benchmark.minImpressions)
        /// 노출 → 첫 다운로드 % — 업계 평균(눌러 봄 6% × 받음 25%).
        static let exposureConversion = AppPotential.Benchmark.tapThrough * AppPotential.Benchmark.pageConversion * 100
        /// 7일 사용자 100명당 크래시 · 멈춤 — 크래시 없는 사용자 99% 언저리.
        static let crashesPer100 = 1.0
        /// 받은 리뷰 수 — 별점 평균을 믿을 만한 정도.
        static let reviews = 10.0
        static let stars = 4.0
        /// 30일 첫 다운로드 — 이보다 적으면 전환율을 말하지 않는다(`AppPotential.Benchmark.minDownloads`).
        static let downloads = Double(AppPotential.Benchmark.minDownloads)
        /// 받기 → 유료 % — 무료로 쓰다 사는 앱의 중앙값.
        static let paidRate = AppPotential.Benchmark.freemiumPaid * 100
    }

    // MARK: - 그래프들

    /// 수익 — 30일 첫 다운로드 × 유료 전환.
    private var revenueChart: some View {
        let points = rows.compactMap { row -> IconScatter.Point? in
            let input = PotentialBoard.input(row.project, store: store, connect: purchases, keywords: keywords)
            guard let paid = input.paid, input.downloads > 0 else { return nil }
            let rate = Double(paid) / Double(input.downloads) * 100
            return IconScatter.Point(project: row.project, name: row.name,
                                     x: Double(input.downloads), y: min(rate, 20),
                                     xText: "30일 다운로드 \(AppFormat.count(input.downloads))",
                                     yText: "결제 \(paid)건 · 전환 \(Self.percent(rate))")
        }
        return IconScatter(title: "수익 — 받는 사람 × 사는 몫",
                           systemImage: "wonsign.circle.fill",
                           reading: "세로줄 30일 다운로드 \(Int(Criterion.downloads)) · 가로줄 유료 전환 \(Self.percent(Criterion.paidRate))(무료로 쓰다 사는 앱의 업계 중앙값)",
                           xTitle: "30일 첫 다운로드(로그)", yTitle: "유료 전환 %",
                           points: points, missing: rows.count - points.count,
                           logX: true, xRule: Criterion.downloads, yRule: Criterion.paidRate,
                           quadrants: [
                            .init(corner: .bottomRight, name: "받는데 안 삼", advice: "페이월이 새는 곳 — 쓰는 흐름 안에서 보이게, 유료 기능을 분명히", tint: .orange),
                            .init(corner: .topRight, name: "잘 버는 중", advice: "광고 · 홍보로 유입을 늘리면 그대로 돈이 된다", tint: .green),
                            .init(corner: .topLeft, name: "작지만 잘 팜", advice: "파는 힘은 있다 — 노출 · 키워드로 받는 사람을 늘리기", tint: .blue),
                            .init(corner: .bottomLeft, name: "작고 안 팜", advice: "둘 다 작다 — 다른 앱에 시간을 쓰거나 정리 후보", tint: .gray),
                           ],
                           section: .purchases, iconURL: iconURL, open: open)
    }

    /// 쓰는 사람 × 지난주 대비.
    private var growthChart: some View {
        let points = rows.compactMap { row -> IconScatter.Point? in
            guard let metric = row.activity ?? row.downloads, metric.current > 0 else { return nil }
            let change = Double(metric.delta) / Double(max(metric.previous, 5)) * 100
            return IconScatter.Point(project: row.project, name: row.name,
                                     x: Double(metric.current), y: min(max(change, -100), 200),
                                     xText: "7일 \(metric.title) \(AppFormat.count(metric.current))",
                                     yText: "지난주 대비 \(change >= 0 ? "+" : "")\(Int(change.rounded()))%")
        }
        return IconScatter(title: "성장 — 쓰는 사람 × 지난주 대비",
                           systemImage: "person.2.fill",
                           reading: "세로줄 7일 \(Int(Criterion.users))명 · 가로줄 지난주와 같음(0%)",
                           xTitle: "7일 쓰는 사람(로그)", yTitle: "지난주 대비 %",
                           points: points, missing: rows.count - points.count,
                           logX: true, xRule: Criterion.users, yRule: 0,
                           quadrants: [
                            .init(corner: .bottomRight, name: "주력인데 줄어듦", advice: "먼저 볼 것 — 업데이트 · 크래시 · 경쟁 앱을 확인", tint: .red),
                            .init(corner: .topRight, name: "주력 · 크는 중", advice: "지금 하는 것을 계속, 결제 흐름을 다듬을 때", tint: .green),
                            .init(corner: .topLeft, name: "떠오름", advice: "작지만 크는 중 — 무엇 때문에 느는지 유입을 보고 더 밀기", tint: .blue),
                            .init(corner: .bottomLeft, name: "작고 줄어듦", advice: "조용히 식는 중 — 손댈 이유가 없으면 두기", tint: .gray),
                           ],
                           section: .stats, iconURL: iconURL, open: open)
    }

    /// 스토어 노출 × 노출 대비 첫 다운로드.
    private var exposureChart: some View {
        let points = rows.compactMap { row -> IconScatter.Point? in
            guard case .ready(let funnel)? = purchases.funnels[row.project]?.value, funnel.instances > 0 else { return nil }
            let total = funnel.total
            guard total.impressions > 0, let conversion = total.conversion else { return nil }
            return IconScatter.Point(project: row.project, name: row.name,
                                     x: Double(total.impressions), y: min(conversion * 100, 30),
                                     xText: "30일 노출 \(AppFormat.count(total.impressions))",
                                     yText: "받은 몫 \(Self.percent(conversion * 100))")
        }
        return IconScatter(title: "진열 — 스토어 노출 × 받는 몫",
                           systemImage: "eye.fill",
                           reading: "세로줄 30일 노출 \(Int(Criterion.impressions)) · 가로줄 노출 대비 다운로드 \(Self.percent(Criterion.exposureConversion))(업계 평균)",
                           xTitle: "30일 노출(로그)", yTitle: "노출 대비 첫 다운로드 %",
                           points: points, missing: rows.count - points.count,
                           logX: true, xRule: Criterion.impressions, yRule: Criterion.exposureConversion,
                           quadrants: [
                            .init(corner: .bottomRight, name: "보이는데 안 받음", advice: "아이콘 · 스크린샷 첫 세 장 · 부제를 손보면 바로 는다", tint: .orange),
                            .init(corner: .topRight, name: "잘 팔리는 진열", advice: "진열은 됐다 — 광고 · 홍보로 노출을 늘리기", tint: .green),
                            .init(corner: .topLeft, name: "받는데 안 보임", advice: "보면 받는다 — 키워드 · 홍보로 노출 늘리기", tint: .blue),
                            .init(corner: .bottomLeft, name: "안 보이고 안 받음", advice: "표본이 작다 — 키워드부터", tint: .gray),
                           ],
                           section: .acquisition, iconURL: iconURL, open: open)
    }

    /// 쓰는 사람 × 100명당 크래시.
    private var crashChart: some View {
        let points = rows.compactMap { row -> IconScatter.Point? in
            let users = row.reach
            guard users > 0 else { return nil }
            let crashes = store.crashSummary(for: row.project).last7Days
            let rate = Double(crashes) / Double(users) * 100
            return IconScatter.Point(project: row.project, name: row.name,
                                     x: Double(users), y: min(rate, 20),
                                     xText: "7일 쓰는 사람 \(AppFormat.count(users))",
                                     yText: "크래시 · 멈춤 \(AppFormat.count(crashes)) · 100명당 \(String(format: "%.1f", rate))")
        }
        return IconScatter(title: "안정성 — 쓰는 사람 × 100명당 크래시",
                           systemImage: "exclamationmark.triangle.fill",
                           reading: "세로줄 7일 \(Int(Criterion.users))명 · 가로줄 100명당 크래시 · 멈춤 \(Int(Criterion.crashesPer100))건",
                           xTitle: "7일 쓰는 사람(로그)", yTitle: "100명당 크래시 · 멈춤",
                           points: points, missing: rows.count - points.count,
                           logX: true, xRule: Criterion.users, yRule: Criterion.crashesPer100,
                           quadrants: [
                            .init(corner: .topRight, name: "많이 쓰는데 불안정", advice: "가장 먼저 — 진단 칸에서 가장 많이 난 크래시부터", tint: .red),
                            .init(corner: .topLeft, name: "작지만 불안정", advice: "쓰는 사람이 적어 피해는 작다 — 다음 업데이트 때", tint: .orange),
                            .init(corner: .bottomRight, name: "많이 쓰고 안정", advice: "지키기 — 새 버전 낼 때 릴리즈 건강만 확인", tint: .green),
                            .init(corner: .bottomLeft, name: "작고 안정", advice: "할 일 없음", tint: .gray),
                           ],
                           section: .crashes, iconURL: iconURL, open: open)
    }

    /// 리뷰 수 × 평균 별점.
    private var reviewChart: some View {
        let points = rows.compactMap { row -> IconScatter.Point? in
            guard let feed = purchases.reviewFeeds[row.project], !feed.reviews.isEmpty,
                  let average = feed.average else { return nil }
            return IconScatter.Point(project: row.project, name: row.name,
                                     x: Double(feed.reviews.count), y: average,
                                     xText: "리뷰 \(AppFormat.count(feed.reviews.count))개",
                                     yText: "평균 별 \(String(format: "%.1f", average))")
        }
        return IconScatter(title: "평판 — 리뷰 수 × 평균 별점",
                           systemImage: "star.fill",
                           reading: "세로줄 리뷰 \(Int(Criterion.reviews))개 · 가로줄 별 \(Int(Criterion.stars))",
                           xTitle: "받은 리뷰(로그)", yTitle: "평균 별점",
                           points: points, missing: rows.count - points.count,
                           logX: true, xRule: Criterion.reviews, yRule: Criterion.stars, yDomain: 1...5,
                           quadrants: [
                            .init(corner: .bottomRight, name: "리뷰 많은데 불만", advice: "낮은 별 리뷰를 읽고 답장 · 고친 버전에서 리뷰 요청", tint: .red),
                            .init(corner: .topLeft, name: "좋은데 리뷰 적음", advice: "만족한 순간에 리뷰 요청을 띄우면 스토어 전환이 오른다", tint: .blue),
                            .init(corner: .topRight, name: "사랑받음", advice: "별점을 스토어 문구 · 홍보에 쓰기", tint: .green),
                            .init(corner: .bottomLeft, name: "적고 낮음", advice: "표본이 작다 — 낮은 별 리뷰 한두 개부터 답하기", tint: .gray),
                           ],
                           section: .reviews, iconURL: iconURL, open: open)
    }

    /// 30일 첫 다운로드 순위 — 막대 끝에 아이콘.
    private var downloadsChart: some View {
        let bars = rows.compactMap { row -> (row: AppGridHome.Row, count: Int)? in
            guard case .ready(let funnel)? = purchases.funnels[row.project]?.value, funnel.instances > 0 else { return nil }
            let count = funnel.total.firstDownloads
            return count > 0 ? (row, count) : nil
        }
        .sorted { $0.count > $1.count }
        .prefix(12)
        return ChartCard(title: "30일 첫 다운로드 순위", systemImage: "arrow.down.app.fill",
                         reading: "스토어 리포트가 있는 앱 중 위에서 12개. 막대를 누르면 그 앱의 유입이 열립니다") {
            if bars.isEmpty {
                emptyText
            } else {
                Chart(Array(bars), id: \.row.project) { bar in
                    BarMark(x: .value("첫 다운로드", bar.count), y: .value("앱", bar.row.name))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing, spacing: 6) {
                            HStack(spacing: 6) {
                                AppIcon(url: iconURL(bar.row.project), size: 24)
                                Text(AppFormat.count(bar.count))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel().font(.body) }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.body) }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let frame = proxy.plotFrame else { return }
                                let y = location.y - geo[frame].origin.y
                                if let name: String = proxy.value(atY: y),
                                   let bar = bars.first(where: { $0.row.name == name }) {
                                    open(bar.row.project, .acquisition)
                                }
                            }
                    }
                }
                .frame(height: CGFloat(bars.count) * 34 + 40)
                .padding(.trailing, 70)
            }
        }
    }

    private var emptyText: some View {
        Text("아직 그릴 숫자가 없습니다.")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - 도움

    private func iconURL(_ project: String) -> URL? { icons.url(for: project, keywords: keywords) }

    private func open(_ project: String, _ section: FeedbackStore.ProjectSection) {
        store.open(project: project, section: section)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%"
    }
}

/// 그래프 한 장의 틀 — 제목 · 읽는 법 · 그래프.
private struct ChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    let reading: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            Text(reading)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
    }
}

/// 앱마다 점 하나를 아이콘으로 찍는 흩어 그리기.
private struct IconScatter: View {
    struct Point: Identifiable {
        let project: String
        let name: String
        let x: Double
        let y: Double
        let xText: String
        let yText: String
        var id: String { project }
    }

    let title: String
    let systemImage: String
    let reading: String
    let xTitle: String
    let yTitle: String
    let points: [Point]
    /// 숫자가 없어 빠진 앱 수.
    let missing: Int
    var logX = false
    /// 세로 기준선. 가로 기준선과 함께 있으면 4분면.
    var xRule: Double?
    /// 가로 기준선(0% · 기준 비율 · 별 4).
    var yRule: Double?
    var yDomain: ClosedRange<Double>?
    /// 4분면 — 보여 줄 차례대로(먼저 손볼 칸부터).
    var quadrants: [Quadrant] = []
    let section: FeedbackStore.ProjectSection
    let iconURL: (String) -> URL?
    let open: (String, FeedbackStore.ProjectSection) -> Void

    @State private var hovered: Point?

    enum Corner { case topRight, topLeft, bottomRight, bottomLeft }

    struct Quadrant {
        let corner: Corner
        let name: String
        let advice: String
        let tint: Color
    }

    private func corner(of point: Point) -> Corner? {
        guard let xRule, let yRule else { return nil }
        switch (point.x >= xRule, point.y >= yRule) {
        case (true, true): return .topRight
        case (false, true): return .topLeft
        case (true, false): return .bottomRight
        case (false, false): return .bottomLeft
        }
    }

    private func quadrant(of point: Point) -> Quadrant? {
        corner(of: point).flatMap { c in quadrants.first { $0.corner == c } }
    }

    private static let iconSize: CGFloat = 26

    var body: some View {
        ChartCard(title: title, systemImage: systemImage, reading: reading) {
            if points.isEmpty {
                Text("아직 그릴 숫자가 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
                    .frame(height: 300)
                HStack {
                    Text(hovered.map { point in
                        let state = quadrant(of: point).map { " · \($0.name)" } ?? ""
                        return "\(point.name)\(state) — \(point.xText) · \(point.yText)"
                    } ?? "아이콘에 마우스를 올려 보세요")
                        .font(.body.weight(hovered == nil ? .regular : .semibold))
                        .foregroundStyle(hovered == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if missing > 0 {
                        Text("숫자 없는 앱 \(missing)개 빠짐")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                if !quadrants.isEmpty { verdicts }
            }
        }
    }

    /// 칸마다 — 이름 · 앱 수 · 앱 아이콘 · 할 일. 빈 칸은 뺀다.
    private var verdicts: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(quadrants.enumerated()), id: \.offset) { _, q in
                let members = points.filter { corner(of: $0) == q.corner }.sorted { $0.x > $1.x }
                if !members.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(q.tint).frame(width: 12, height: 12)
                            Text(q.name).font(.body.weight(.semibold))
                            Text("\(members.count)개").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(q.advice)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        FlowLayout(spacing: 6) {
                            ForEach(members) { point in
                                Button { open(point.project, section) } label: {
                                    AppIcon(url: iconURL(point.project), size: 28)
                                }
                                .buttonStyle(.plain)
                                .help("\(point.name) — \(point.xText) · \(point.yText)")
                                .accessibilityLabel("\(point.name), \(q.name)")
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var chart: some View {
        Chart {
            if let xRule {
                RuleMark(x: .value("기준", xRule))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let yRule {
                RuleMark(y: .value("기준", yRule))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(points) { point in
                PointMark(x: .value(xTitle, point.x), y: .value(yTitle, point.y))
                    .symbol {
                        AppIcon(url: iconURL(point.project), size: Self.iconSize)
                            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                            .scaleEffect(hovered?.id == point.id ? 1.5 : 1)
                            .opacity(hovered == nil || hovered?.id == point.id ? 1 : 0.55)
                    }
            }
        }
        .chartBackground { proxy in quadrantBackground(proxy) }
        .modifier(XScale(log: logX))
        .modifier(YDomain(domain: yDomain))
        .chartXAxisLabel(xTitle)
        .chartYAxisLabel(yTitle)
        .chartXAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.body) } }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.body) } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hovered = nearest(to: location, proxy: proxy, geo: geo)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { location in
                        if let point = nearest(to: location, proxy: proxy, geo: geo) { open(point.project, section) }
                    }
            }
        }
        .padding(Self.iconSize / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(points.map { "\($0.name), \($0.xText), \($0.yText)" }.joined(separator: ". "))
    }

    /// 칸마다 옅은 색과 구석의 이름 — 기준선으로 나눈다.
    @ViewBuilder
    private func quadrantBackground(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            if !quadrants.isEmpty, let xRule, let yRule, let frame = proxy.plotFrame {
                let plot = geo[frame]
                let px = min(max(proxy.position(forX: xRule) ?? plot.width / 2, 0), plot.width)
                let py = min(max(proxy.position(forY: yRule) ?? plot.height / 2, 0), plot.height)
                ForEach(Array(quadrants.enumerated()), id: \.offset) { _, q in
                    let rect: CGRect = switch q.corner {
                    case .topLeft: CGRect(x: 0, y: 0, width: px, height: py)
                    case .topRight: CGRect(x: px, y: 0, width: plot.width - px, height: py)
                    case .bottomLeft: CGRect(x: 0, y: py, width: px, height: plot.height - py)
                    case .bottomRight: CGRect(x: px, y: py, width: plot.width - px, height: plot.height - py)
                    }
                    let alignment: Alignment = switch q.corner {
                    case .topLeft: .topLeading
                    case .topRight: .topTrailing
                    case .bottomLeft: .bottomLeading
                    case .bottomRight: .bottomTrailing
                    }
                    q.tint.opacity(0.07)
                        .overlay(alignment: alignment) {
                            if rect.width > 90, rect.height > 30 {
                                Text(q.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(q.tint.opacity(0.8))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(6)
                            }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: plot.minX + rect.midX, y: plot.minY + rect.midY)
                }
            }
        }
    }

    /// 마우스에서 가장 가까운 아이콘. 아이콘 크기 안에 없으면 nil.
    private func nearest(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Point? {
        guard let frame = proxy.plotFrame else { return nil }
        let origin = geo[frame].origin
        let best = points.compactMap { point -> (Point, CGFloat)? in
            guard let position = proxy.position(for: (point.x, point.y)) else { return nil }
            let dx = position.x + origin.x - location.x, dy = position.y + origin.y - location.y
            return (point, (dx * dx + dy * dy).squareRoot())
        }
        .min { $0.1 < $1.1 }
        return best.flatMap { $0.1 <= Self.iconSize ? $0.0 : nil }
    }
}

private struct XScale: ViewModifier {
    let log: Bool
    func body(content: Content) -> some View {
        if log { content.chartXScale(type: .log) } else { content }
    }
}

private struct YDomain: ViewModifier {
    let domain: ClosedRange<Double>?
    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}

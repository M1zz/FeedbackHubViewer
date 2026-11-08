//
//  KeywordMap.swift
//  FeedbackHubViewer
//
//  검색어 지도. 가로 경쟁 · 세로 인기에 검색어마다 점 하나.
//  왼쪽 위(많이 찾는데 상위 앱이 약한 곳)가 선점 지대다. 점의 색과 모양은 판정을 따른다 —
//  색만으로 가르지 않으려고 모양을 함께 바꾼다(지키기 ● · 올릴 만함 ▲ · 선점 기회 ◆ · 새로 노리기 ■).
//

import SwiftUI
import Charts

struct KeywordMap: View {
    let items: [KeywordRecommendation.Item]

    @State private var hovered: KeywordRecommendation.Item?
    /// 이름을 붙일 점 수. 다 붙이면 겹쳐서 아무것도 안 읽힌다.
    private static let labeledCount = 8

    /// 이름을 붙일 점 — 선점 기회 먼저, 남는 자리는 많이 찾는 말.
    private var labeled: Set<String> {
        let claims = items.filter { $0.verdict == .claim }
        let rest = items.filter { $0.verdict != .claim }.sorted { $0.popularity > $1.popularity }
        // 가까이 붙은 점은 앞(더 중요한) 것만 이름을 단다. 나머지는 마우스를 올리면 나온다.
        var chosen: [KeywordRecommendation.Item] = []
        for item in claims + rest where chosen.count < Self.labeledCount {
            let crowded = chosen.contains {
                abs($0.competition - item.competition) < 12 && abs($0.popularity - item.popularity) < 7
            }
            if !crowded { chosen.append(item) }
        }
        return Set(chosen.map(\.id))
    }

    var body: some View {
        let labeled = labeled
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                RectangleMark(xStart: .value("경쟁", 0),
                              xEnd: .value("경쟁", KeywordRecommendation.claimableCompetition),
                              yStart: .value("인기", 50), yEnd: .value("인기", 100))
                    .foregroundStyle(Color.purple.opacity(0.08))
                    .annotation(position: .overlay, alignment: .topLeading) {
                        Text("선점 지대").font(.hubCaption2).foregroundStyle(.secondary).padding(4)
                    }
                ForEach(items) { item in
                    PointMark(x: .value("경쟁", item.competition), y: .value("인기", item.popularity))
                        .symbol(Self.shape(item.verdict))
                        .symbolSize(hovered?.id == item.id ? 180 : 90)
                        .foregroundStyle(KeywordRecommendationCard.tint(item.verdict))
                        .annotation(position: .top, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if labeled.contains(item.id) || hovered?.id == item.id {
                                Text(item.term).font(.hubCaption2).foregroundStyle(.primary)
                            }
                        }
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxisLabel("경쟁 — 왼쪽일수록 뚫기 쉬움")
            .chartYAxisLabel("인기")
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): hovered = nearest(to: point, proxy: proxy, geo: geo)
                            case .ended: hovered = nil
                            }
                        }
                        .onTapGesture { point in hovered = nearest(to: point, proxy: proxy, geo: geo) }
                }
            }
            .frame(height: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)

            readout
            legend
        }
    }

    // MARK: - 읽기

    /// 가리킨 점의 숫자. 점 옆 말풍선은 가장자리에서 잘려서 차트 아래 한 줄로 둔다.
    @ViewBuilder
    private var readout: some View {
        if let item = hovered {
            HStack(spacing: 6) {
                Image(systemName: Self.symbolName(item.verdict))
                    .foregroundStyle(KeywordRecommendationCard.tint(item.verdict))
                Text(item.term).font(.body.weight(.semibold))
                Text("인기 \(item.popularity) · 경쟁 \(item.competition) · \(item.rank.map { "지금 \($0)위" } ?? "200위 안에 없음") · \(item.verdict.label)")
                    .font(.hubCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("점에 마우스를 올리면 그 검색어의 숫자가 나옵니다. 위로 갈수록 많이 찾고, 왼쪽으로 갈수록 뚫기 쉽습니다.")
                .font(.hubCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legend: some View {
        let order: [KeywordRecommendation.Verdict] = [.keep, .climb, .claim, .target]
        return HStack(spacing: 14) {
            ForEach(order, id: \.self) { verdict in
                let count = items.filter { $0.verdict == verdict }.count
                if count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: Self.symbolName(verdict))
                            .foregroundStyle(KeywordRecommendationCard.tint(verdict))
                        Text("\(verdict.label) \(count)")
                    }
                    .font(.hubCaption)
                }
            }
        }
    }

    private var summary: String {
        let claims = items.filter { $0.verdict == .claim }.count
        return "검색어 지도. 검색어 \(items.count)개 중 선점 기회 \(claims)개. 아래 목록에 같은 숫자가 있습니다."
    }

    // MARK: - 가리키기

    /// 손끝 · 마우스에서 가장 가까운 점. 24pt 안에 없으면 nil.
    private func nearest(to point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> KeywordRecommendation.Item? {
        guard let frame = proxy.plotFrame else { return nil }
        let origin = geo[frame].origin
        let best = items.compactMap { item -> (KeywordRecommendation.Item, CGFloat)? in
            guard let position = proxy.position(for: (item.competition, item.popularity)) else { return nil }
            let dx = position.x + origin.x - point.x, dy = position.y + origin.y - point.y
            return (item, (dx * dx + dy * dy).squareRoot())
        }
        .min { $0.1 < $1.1 }
        return best.flatMap { $0.1 <= 24 ? $0.0 : nil }
    }

    // MARK: - 모양

    static func shape(_ verdict: KeywordRecommendation.Verdict) -> BasicChartSymbolShape {
        switch verdict {
        case .keep: return .circle
        case .climb: return .triangle
        case .claim: return .diamond
        case .target: return .square
        }
    }

    static func symbolName(_ verdict: KeywordRecommendation.Verdict) -> String {
        switch verdict {
        case .keep: return "circle.fill"
        case .climb: return "triangle.fill"
        case .claim: return "diamond.fill"
        case .target: return "square.fill"
        }
    }
}

//
//  MapBubble.swift
//  FeedbackHubViewer
//
//  세계지도 위의 원 하나 — 설치 지도와 수익 지도가 같이 쓴다.
//
//  크기만으로 다르게 하면 한 나라가 압도할 때 나머지가 다 비슷한 점으로 보였다. 그래서 많을수록
//  원이 커지고(넓이가 수에 비례), 진해지고, 테두리가 굵어진다. 가장 많은 세 곳은 원 아래에
//  국기와 수를 적어 지도만 봐도 어디가 큰지 읽힌다.
//
//  그리는 차례도 정한다. 큰 원을 먼저 깔고 작은 원을 위에 얹어야 작은 나라가 큰 원에 묻히지
//  않는다. 이름표는 맨 위.
//

import SwiftUI

struct MapBubble: View {
    /// 가장 많은 곳에 견준 몫(0...1).
    let ratio: Double
    let tint: Color

    static let minDiameter: CGFloat = 8
    static let maxDiameter: CGFloat = 72

    static func diameter(_ ratio: Double) -> CGFloat {
        minDiameter + (maxDiameter - minDiameter) * CGFloat(sqrt(max(0, min(1, ratio))))
    }

    var body: some View {
        let r = max(0, min(1, ratio))
        let diameter = Self.diameter(r)
        Circle()
            .fill(tint.opacity(0.18 + 0.52 * sqrt(r)))
            .overlay(Circle().stroke(tint.opacity(0.55 + 0.45 * r), lineWidth: 1 + 1.5 * r))
            .shadow(color: tint.opacity(r > 0.5 ? 0.35 : 0), radius: 6)
            .frame(width: diameter, height: diameter)
    }
}

/// 가장 많은 곳 이름표 — "🇰🇷 1,234".
struct MapBubbleLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
    }
}

/// 지도 위에 원과 이름표를 차례대로 얹는다.
struct MapBubbles<Item: Identifiable>: View {
    /// 많은 것부터.
    let items: [Item]
    let value: (Item) -> Double
    let point: (Item) -> CGPoint?
    let label: (Item) -> String
    let help: (Item) -> String
    let tint: Color
    /// 이름표를 달 곳 수.
    var labeled = 3

    var body: some View {
        let peak = max(items.map(value).max() ?? 1, .leastNonzeroMagnitude)
        // items 는 많은 것부터라 그대로 그리면 큰 원이 아래에 깔린다.
        ForEach(items) { item in
            if let point = point(item) {
                MapBubble(ratio: value(item) / peak, tint: tint)
                    .help(help(item))
                    .position(point)
            }
        }
        ForEach(Array(items.prefix(labeled))) { item in
            if let point = point(item) {
                MapBubbleLabel(text: label(item), tint: tint)
                    .position(x: point.x, y: point.y + MapBubble.diameter(value(item) / peak) / 2 + 14)
            }
        }
    }
}

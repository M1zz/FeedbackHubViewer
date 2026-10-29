//
//  DeltaLabel.swift
//  FeedbackHubViewer
//
//  "+12 ↗" — this week against last week, in the one shape the whole app uses.
//
//  Four screens had written their own, and they disagreed: one showed "±0",
//  one showed "0"; one used a hyphen, one a minus sign; and the colours were
//  decided per call site, so a rising crash count was once green.
//

import SwiftUI

/// Which direction is the good news. There is no sensible default — a rising
/// 사용 건수 and a rising 크래시 건수 mean opposite things, and getting that
/// backwards is the one mistake a coloured arrow can make.
enum DeltaPolarity {
    /// More is better: 활동한 사용자, 사용 건수, 신규 설치.
    case higherIsBetter
    /// Less is better: 크래시, 멈춤, 검색 순위.
    case lowerIsBetter

    func tint(for value: Int) -> Color {
        guard value != 0 else { return .secondary }
        let isGood = self == .higherIsBetter ? value > 0 : value < 0
        return isGood ? .green : .red
    }
}

struct DeltaLabel: View {
    let value: Int
    var polarity: DeltaPolarity = .higherIsBetter

    private var symbol: String {
        if value > 0 { return "arrow.up.right" }
        if value < 0 { return "arrow.down.right" }
        return "minus"
    }

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(AppFormat.signed(value))
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(polarity.tint(for: value))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("지난주 대비 \(AppFormat.signed(value))")
    }
}

// MARK: - 순위

/// 순위의 오르내림 — 한국 주식처럼 오르면 빨강 ▲, 내리면 파랑 ▼.
///
/// 순위는 숫자가 작아질수록 좋아서 "−18" 을 초록으로 칠해 왔는데, 숫자를 한 번 뒤집어 읽어야
/// 했다. 순위만큼은 시세판처럼 읽히게 한다: 오른 계단 수와 방향, 색 셋이 한 뜻을 말한다.
/// (다른 숫자의 좋고 나쁨 — 크래시 · 사용 건수 — 은 그대로 `DeltaLabel` 의 초록 · 빨강이다.)
enum RankTrend {
    static let up = Color.red
    static let down = Color.blue

    /// 오른 계단 수(양수 = 올라감)의 색.
    static func color(_ climbed: Int) -> Color {
        climbed > 0 ? up : climbed < 0 ? down : .secondary
    }
}

struct RankMoveLabel: View {
    /// 오른 계단 수. 30위 → 12위면 +18, 12위 → 30위면 −18.
    let climbed: Int

    var body: some View {
        Text(climbed > 0 ? "▲\(climbed)" : climbed < 0 ? "▼\(-climbed)" : "–")
            .font(.body.monospacedDigit().weight(.semibold))
            .foregroundStyle(RankTrend.color(climbed))
            .accessibilityLabel(climbed > 0 ? "\(climbed)계단 오름" : climbed < 0 ? "\(-climbed)계단 내림" : "그대로")
    }
}

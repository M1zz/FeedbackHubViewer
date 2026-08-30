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

//
//  TrendFigure.swift
//  FeedbackHubViewer
//
//  변화가 주인공인 숫자 한 칸, 그리고 손봐야 할 것을 알리는 뱃지.
//
//  왜 이런 칸이 따로 있는가: "7일 사용 5,000건"은 그 자체로 아무 결정도 만들지
//  못한다. 5,000이 많은지 적은지는 이 앱의 지난주를 알아야 답할 수 있고, 그걸
//  아는 사람은 화면이지 읽는 사람이 아니다. 그래서 프로젝트 목록에서는 절대값이
//  아니라 **견준 결과**를 큰 활자로 놓고, 그 값을 만든 두 숫자는 밑에 작게 붙인다
//  — 변화만 있고 원본이 없으면 "+300%"가 3건에서 12건인지 3천에서 1만2천인지
//  알 수 없어 그것대로 못 믿을 숫자가 된다.
//
//  퍼센트에 부호를 적지 않는 것은 화살표와 색이 이미 방향을 말하기 때문이다.
//  좋고 나쁨은 `DeltaPolarity`가 정한다 — 오르는 사용 건수와 오르는 크래시는
//  반대말이다.
//

import SwiftUI

/// 지난 창과 견준 한 칸: 제목, 변화, 그리고 그 변화를 만든 두 숫자.
struct TrendFigure: View {
    let title: String
    /// 이번 창의 값.
    let current: Int
    /// 견줄 앞 창의 값.
    let previous: Int
    /// "건", "명", "대" — 밑줄에 붙는 꼬리.
    var unit: String = ""
    /// 앞 창의 이름. "지난주", "그제".
    var previousLabel: String = "지난주"
    var polarity: DeltaPolarity = .higherIsBetter
    var textStyle: Font.TextStyle = .title3

    private var delta: Int { current - previous }

    /// 앞 창이 0이면 비율이랄 것이 없다 — 0에서 늘어난 것은 몇 %가 아니라 "처음"이다.
    private var ratio: Double? { previous > 0 ? Double(delta) / Double(previous) : nil }

    private var symbol: String? {
        guard previous > 0 || current > 0 else { return nil }
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "minus"
    }

    private var tint: Color {
        guard previous > 0 || current > 0 else { return .secondary }
        return polarity.tint(for: delta)
    }

    /// 큰 활자에 놓이는 말. 몇 배로 뛴 값을 "1,900%"로 적으면 자릿수를 세게 되므로
    /// 열 배가 넘어가면 배수로 바꾼다.
    private var headline: String {
        guard let ratio else { return current > 0 ? "처음" : "—" }
        let magnitude = abs(ratio)
        if magnitude >= 10 { return String(format: "%.0f배", magnitude) }
        return String(format: "%.0f%%", (magnitude * 100).rounded())
    }

    private var note: String {
        guard previous > 0 || current > 0 else { return "기록 없음" }
        return "\(AppFormat.count(current))\(unit) · \(previousLabel) \(AppFormat.count(previous))\(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(headline)
                    .font(.figure(textStyle))
            }
            .foregroundStyle(tint)
            Text(note)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        // 칸을 얼마나 넓게 쓸지는 이 칸이 아니라 놓는 쪽이 정한다. 여기서
        // `maxWidth: .infinity`를 걸어 두면 제 이상적 너비를 말하지 않게 되어,
        // 넷을 한 줄에 우겨넣어도 "들어간다"고 대답한다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard previous > 0 || current > 0 else { return "\(title), 기록 없음" }
        guard ratio != nil else { return "\(title), 처음으로 \(current)\(unit)" }
        let direction = delta > 0 ? "늘어" : (delta < 0 ? "줄어" : "그대로")
        return "\(title), \(previousLabel) 대비 \(headline) \(direction), 지금 \(current)\(unit), \(previousLabel) \(previous)\(unit)"
    }
}

/// 손봐야 할 것이 몇 개 있다는 표시. 숫자만 있는 동그라미는 무엇의 3인지 말하지
/// 않으므로, 아이콘을 함께 두고 음성 안내에는 온전한 문장을 준다.
struct CountBadge: View {
    let count: Int
    let systemImage: String
    var tint: Color = .red
    /// "안 읽은 피드백" — 음성 안내와 툴팁이 읽는 이름.
    let name: String

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .help("\(name) \(count)건")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) \(count)건")
        }
    }
}

//
//  ChartReadout.swift
//  FeedbackHubViewer
//
//  가리킨 자리의 정확한 값.
//
//  선 그래프는 모양을 주지만 숫자를 주지 않는다. 눈금이 10 단위인데 점이 그 사이
//  어딘가에 있으면 눈으로 읽을 수 있는 것은 "13쯤"까지다. 그런데 이 화면에서 실제로
//  묻게 되는 것은 대개 "그래서 그날 몇이었나"이고, 그 답이 그래프에는 없었다.
//
//  그래서 가리킨 자리에 세로선을 긋고 그 자리의 값을 숫자로 적는다. 계열마다 따로
//  읽지 않고 **한 번에 다 적는** 이유: 겹쳐 그린 그래프에서 알고 싶은 것은 대개 한
//  값이 아니라 같은 날 값들 **사이의 차이**다 (DAU가 WAU의 몇 분의 일인지 같은 것).
//  꺼 둔 계열은 적지 않는다 — 안 보이는 선의 숫자는 답이 아니라 소음이다.
//

import SwiftUI
import Charts

/// 차트 위에 뜨는 작은 값 패널.
struct ChartReadout: View {
    /// 어느 자리인지 — 날짜나 기간 이름.
    let title: String
    let items: [Item]

    struct Item: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.value)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(8)
        // 선 위에 떠서 선을 가리므로 반투명이 아니라 재질로 — 뒤가 비치되 글자는
        // 읽힌다.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2))
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        // 값을 읽으려고 띄운 것이지 누르려고 띄운 것이 아니다. 손짓을 가로채면
        // 패널 밑을 가리킬 수 없어진다.
        .allowsHitTesting(false)
    }
}

extension View {
    /// 차트에 "가리킨 자리의 값" 기능을 붙인다 — 세로선 하나와 값 패널 하나.
    ///
    /// macOS에서는 마우스를 올리면, iOS에서는 손가락을 대고 움직이면 따라온다.
    /// 그 차이는 `chartXSelection`이 알아서 하므로 여기서 갈라 쓰지 않는다.
    func chartCursor(_ selection: Binding<Date?>) -> some View {
        self.chartXSelection(value: selection)
    }
}

//
//  ChartLegend.swift
//  FeedbackHubViewer
//
//  겹쳐 그린 차트의 범례 — 그리고 스위치.
//
//  여러 계열을 한 그림에 겹치면 축을 공유하게 된다. 축을 공유한다는 것은 가장 큰
//  계열이 눈금을 정한다는 뜻이고, 그래서 작은 계열은 바닥에 눌린다. MAU가 42인
//  축에서 DAU 0~11은 거의 직선이다 — 하필 그 DAU가 지금 궁금한 것일 때가 많다.
//
//  답은 그래프를 나누는 것이 아니다. 나누면 서로의 관계(세 창이 붙었는지
//  벌어졌는지)가 사라지고, 그 관계가 겹쳐 그린 이유였다. 대신 **계열을 끌 수 있게**
//  한다. 끄면 축이 남은 것에 맞춰 다시 잡히므로, 같은 그래프가 그대로 DAU 한 계열의
//  그래프가 된다.
//
//  마지막 한 계열은 꺼지지 않는다. 빈 그래프는 답이 아니라 사고이고, 하나 남은
//  것을 마저 끄려는 손짓은 "이것도 그만 보겠다"보다 "원래대로"에 가깝다.
//

import SwiftUI

/// 겹쳐 그린 차트의 계열 하나.
struct ChartSeries: Identifiable, Hashable {
    /// 코드에서 계열을 가리키는 이름. 화면에는 안 나온다.
    let id: String
    let label: String
    let color: Color
    /// 파선으로 그려지는 계열(전망선처럼 관측이 아닌 것)은 범례도 파선으로.
    var isDashed = false

    init(_ id: String, _ label: String, _ color: Color, isDashed: Bool = false) {
        self.id = id
        self.label = label
        self.color = color
        self.isDashed = isDashed
    }
}

/// 지금 보이는 계열이 무엇인지. 끈 것을 담는 이유는 계열 목록이 바뀌어도
/// (앱이 새 계열을 보내기 시작해도) 새 계열이 기본으로 보이게 하기 위해서다.
struct ChartSeriesSelection: Equatable {
    private var hidden: Set<String> = []

    init() {}

    func isVisible(_ id: String) -> Bool { !hidden.contains(id) }
    var isShowingAll: Bool { hidden.isEmpty }

    /// 켜고 끄기.
    mutating func toggle(_ id: String, among all: [ChartSeries]) {
        if hidden.contains(id) {
            hidden.remove(id)
        } else if all.count - hidden.count > 1 {
            hidden.insert(id)
        } else {
            showAll()
        }
    }

    /// 이 계열 하나만. "DAU만 보고 싶다"가 한 번에 되는 길이다.
    mutating func isolate(_ id: String, among all: [ChartSeries]) {
        let others = Set(all.map(\.id)).subtracting([id])
        hidden = hidden == others ? [] : others
    }

    mutating func showAll() { hidden.removeAll() }

    /// 보이는 것만 남긴 계열 목록 — 축 범위를 잡을 때 쓴다.
    func visible(in all: [ChartSeries]) -> [ChartSeries] {
        all.filter { isVisible($0.id) }
    }
}

/// 범례 겸 스위치. 누르면 그 계열이 켜지고 꺼지며, 길게 누르면 그것만 남는다.
struct ChartLegend: View {
    let series: [ChartSeries]
    @Binding var selection: ChartSeriesSelection

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 6) {
            ForEach(series) { item in
                Button {
                    selection.toggle(item.id, among: series)
                } label: {
                    chip(item)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("\(item.label)만 보기") { selection.isolate(item.id, among: series) }
                    Button("전체 보기") { selection.showAll() }
                }
                .accessibilityLabel(item.label)
                .accessibilityValue(selection.isVisible(item.id) ? "표시 중" : "숨김")
                .accessibilityAddTraits(selection.isVisible(item.id) ? [.isSelected] : [])
                .accessibilityHint("두 번 눌러 켜고 끕니다")
            }
            if !selection.isShowingAll {
                Button {
                    selection.showAll()
                } label: {
                    Text("전체 보기")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 켜진 계열은 제 색으로 꽉 찬 점, 꺼진 계열은 테두리만 남은 점.
    /// 색을 지우지 않고 비우기만 하는 이유: 다시 켤 때 어떤 색이 돌아오는지
    /// 미리 보여야 한다.
    private func chip(_ item: ChartSeries) -> some View {
        let isOn = selection.isVisible(item.id)
        return HStack(spacing: 4) {
            marker(item, isOn: isOn)
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isOn ? Color.secondary.opacity(0.10) : .clear, in: Capsule())
        .overlay {
            if !isOn { Capsule().strokeBorder(Color.secondary.opacity(0.20)) }
        }
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func marker(_ item: ChartSeries, isOn: Bool) -> some View {
        if item.isDashed {
            // 파선 계열은 점이 아니라 짧은 선분으로. 차트에서 그렇게 보이므로.
            Capsule()
                .fill(isOn ? item.color : .clear)
                .overlay { if !isOn { Capsule().strokeBorder(item.color.opacity(0.5)) } }
                .frame(width: 12, height: 3)
        } else {
            Circle()
                .fill(isOn ? item.color : .clear)
                .overlay { if !isOn { Circle().strokeBorder(item.color.opacity(0.5)) } }
                .frame(width: 7, height: 7)
        }
    }
}

//
//  FlowLayout.swift
//  FeedbackHubViewer
//
//  Lays children out in a row and wraps to the next line when they don't fit.
//
//  Rows of badges (project · version · device · email) used to be a single
//  `HStack` with `lineLimit(1)`, which quietly dropped whatever didn't fit on a
//  phone. Wrapping keeps every value on screen.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var size = CGSize(width: 0, height: 0)
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let item = fit(subview, within: maxWidth).size
            if lineWidth > 0 && lineWidth + spacing + item.width > maxWidth {
                size.width = max(size.width, lineWidth)
                size.height += lineHeight + lineSpacing
                lineWidth = item.width
                lineHeight = item.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + item.width
                lineHeight = max(lineHeight, item.height)
            }
        }
        size.width = max(size.width, lineWidth)
        size.height += lineHeight
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let item = fit(subview, within: bounds.width)
            if x > bounds.minX && x + item.size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: item.proposal)
            x += item.size.width + spacing
            lineHeight = max(lineHeight, item.size.height)
        }
    }

    /// 한 조각의 크기와, 그 크기로 그리게 할 제안.
    ///
    /// 보통은 `.unspecified` — 조각이 잰 그대로의 자연스러운 크기로 그린다.
    /// 측정한 크기를 되돌려 제안하면 레이블이 다시 배치되면서 글자를 떨구기
    /// 때문이다.
    ///
    /// 다만 **줄보다 넓은 조각**은 예외다. 그대로 두면 그 조각 하나가 줄
    /// 너비를 화면 밖까지 늘리고, 그 줄이 목록 전체를 밀어 양옆이 잘렸다
    /// (긴 이메일 주소 태그 하나면 충분했다). 그런 조각에는 줄 너비를 제안해
    /// 그 안에서 줄여 쓰거나 잘라 쓰게 한다 — 잘리는 것은 그 조각 하나다.
    private func fit(_ subview: LayoutSubviews.Element,
                     within limit: CGFloat) -> (size: CGSize, proposal: ProposedViewSize) {
        let ideal = subview.sizeThatFits(.unspecified)
        guard limit.isFinite, ideal.width > limit else { return (ideal, .unspecified) }
        let proposal = ProposedViewSize(width: limit, height: nil)
        return (subview.sizeThatFits(proposal), proposal)
    }
}

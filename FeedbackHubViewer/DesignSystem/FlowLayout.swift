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
            let item = subview.sizeThatFits(.unspecified)
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
            let item = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + item.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            // `.unspecified` so each child keeps the natural size it was
            // measured with; proposing the measured size back makes labels
            // re-lay out and drop their text.
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += item.width + spacing
            lineHeight = max(lineHeight, item.height)
        }
    }
}

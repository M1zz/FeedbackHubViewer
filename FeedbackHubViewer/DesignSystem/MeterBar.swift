//
//  MeterBar.swift
//  FeedbackHubViewer
//
//  One proportion, drawn as a bar. Distribution rows, funnel steps, flag shares
//  and the carrying-capacity gauge were four hand-rolled copies of the same
//  `GeometryReader { ZStack { Capsule; Capsule } }`.
//

import SwiftUI

struct MeterBar: View {
    /// 0...1. Values above 1 fill the bar and stop there — the number beside it
    /// is what tells the truth about an overflow.
    let ratio: Double
    var height: CGFloat = 6
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    // A floor of 2pt so a tiny-but-present share still reads as
                    // present rather than as an empty track.
                    .frame(width: max(2, geo.size.width * min(1, max(0, ratio))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

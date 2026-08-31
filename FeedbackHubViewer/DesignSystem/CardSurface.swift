//
//  CardSurface.swift
//  FeedbackHubViewer
//
//  The plate every card, tile and inset panel is drawn on. It was written out
//  by hand in seven places — a secondary background, a rounded rectangle, and
//  a hairline border at 15% — which is exactly the kind of thing that drifts
//  one radius at a time until no two cards match.
//

import SwiftUI

extension View {
    /// The standard raised surface: a secondary fill with an optional hairline
    /// border. `radius` is the only thing that varies — 12 for a card, 10 for a
    /// tile inside one, 8 for a note inside that.
    func cardSurface(radius: CGFloat = 12, bordered: Bool = true) -> some View {
        self
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.secondary.opacity(0.15))
                }
            }
    }
}

/// A titled card: a labelled heading and whatever goes under it. The shell for
/// every panel on the 통계 screen, and used from the diagnostics screens too.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }
}

/// An untitled card that owns its own heading — the project cards, whose first
/// line is an icon and a name rather than a label. The minimum height is what
/// keeps a grid of them from going ragged when one project has fewer numbers.
struct CardFrame<Content: View>: View {
    var minHeight: CGFloat = 140
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

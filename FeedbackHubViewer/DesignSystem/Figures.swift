//
//  Figures.swift
//  FeedbackHubViewer
//
//  Numbers with their names attached. Every screen shows a handful of counts,
//  and every screen had grown its own way of drawing one — `stat`, `figure`,
//  `MetricRow.Item`, `StatTile`, `SpecTile` were five spellings of "a big
//  rounded numeral with a caption".
//
//  Two shapes survive, because they are genuinely different things:
//
//   · `Figure` — a bare number in a row of numbers, no plate of its own.
//   · `StatTile` — a number that *is* the card, on its own surface.
//

import SwiftUI

/// The type face every count in the app is set in. Rounded and monospaced so a
/// column of them lines up and a changing digit doesn't shift its neighbours.
extension Font {
    static func figure(_ style: Font.TextStyle = .title3) -> Font {
        .system(style, design: .rounded).weight(.semibold).monospacedDigit()
    }
}

/// One number with a caption above and an optional note below — what a row of
/// headline counts is made of. No background: it belongs to whatever card it
/// sits in.
struct Figure: View {
    let title: String
    let value: String
    /// The small line under the number: last week's figure, a total, a date.
    var note: String? = nil
    var tint: Color = .primary
    var textStyle: Font.TextStyle = .title3
    /// Sits beside the number — a `DeltaLabel`, usually.
    var accessory: AnyView? = nil

    init(_ title: String, _ value: String, note: String? = nil,
         tint: Color = .primary, textStyle: Font.TextStyle = .title3) {
        self.title = title
        self.value = value
        self.note = note
        self.tint = tint
        self.textStyle = textStyle
    }

    /// The form that carries a delta beside the number.
    init<Accessory: View>(_ title: String, _ value: String, note: String? = nil,
                          tint: Color = .primary, textStyle: Font.TextStyle = .title3,
                          @ViewBuilder accessory: () -> Accessory) {
        self.init(title, value, note: note, tint: tint, textStyle: textStyle)
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Text(value)
                    .font(.figure(textStyle))
                    .foregroundStyle(tint)
                accessory
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        // A figure sits in a row of figures: it shrinks rather than wraps, so
        // the row keeps its shape when one number grows a digit.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// A count on its own plate — the grid at the top of the 통계 screen, and the
/// same tile wherever else a number needs to stand alone.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    let systemImage: String
    var tint: Color = .accentColor

    #if os(macOS)
    private let textStyle: Font.TextStyle = .title
    #else
    private let textStyle: Font.TextStyle = .title2
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.figure(textStyle))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.tilePadding)
        .cardSurface()
    }
}

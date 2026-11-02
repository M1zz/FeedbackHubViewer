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
                .font(.hubCaption2)
                .foregroundStyle(.secondary)
                // 이름은 두 줄까지 접힌다. 아래 `lineLimit(1)`은 숫자를 위한
                // 것이고(자릿수가 늘어도 줄을 바꾸지 않아야 한다), 이름까지
                // 한 줄로 묶으면 좁은 칸에서 "아직 나는 이슈"가 "아직…"이 되어
                // 무엇을 세는 숫자인지가 사라진다.
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(value)
                    .font(.figure(textStyle))
                    .foregroundStyle(tint)
                accessory
            }
            if let note {
                Text(note)
                    .font(.hubCaption2)
                    .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                .font(.hubCaption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.figure(textStyle))
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit).font(.hubCaption2).foregroundStyle(.secondary)
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

/// 글씨 크기 — 맥은 그대로 촘촘하게, 아이폰 · 아이패드는 본문(.body) 아래로 내려가지 않게.
///
/// 아이폰은 맥보다 화면에서 눈이 멀고, 작은 글씨(캡션 · 각주)는 손에 들고 읽기 어렵다. 그래서
/// 작은 글씨 자리는 아이폰에서 본문 크기로 키우고, 위계는 굵기와 색(.secondary)이 맡는다.
/// 다이내믹 타입을 따르므로 설정에서 글씨를 키우면 함께 커진다.
extension Font {
    static var hubCaption: Font { adaptive(.caption) }
    static var hubCaption2: Font { adaptive(.caption2) }
    static var hubFootnote: Font { adaptive(.footnote) }
    static var hubSubheadline: Font { adaptive(.subheadline) }
    static var hubCallout: Font { adaptive(.callout) }

    private static func adaptive(_ mac: Font) -> Font {
        #if os(macOS)
        return mac
        #else
        return .body
        #endif
    }
}

extension HierarchicalShapeStyle {
    /// 덜 중요한 설명 글. 맥은 세 번째 단계(.tertiary), 아이폰은 바깥에서 들고 읽어도 보이게
    /// 두 번째 단계(.secondary)로 한 단계 진하게.
    static var hubFaint: HierarchicalShapeStyle {
        #if os(macOS)
        return .tertiary
        #else
        return .secondary
        #endif
    }
}

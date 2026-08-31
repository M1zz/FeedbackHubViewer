//
//  Chips.swift
//  FeedbackHubViewer
//
//  The small capsules the app labels things with: a read-only tag, a selectable
//  filter, an unread count. All three were re-implemented per screen, which is
//  how a filter row on 진단 ended up a different height from the one on 이슈.
//

import SwiftUI

/// A read-only tag: a value with the word for what it is. Used for a feedback
/// row's project · version · device, and for the small grey labels on the
/// diagnostics screens.
struct Tag: View {
    let text: String
    var systemImage: String? = nil
    /// `nil` is the neutral grey tag. A colour tints the fill and the text
    /// together, which is how a 확인함 or a 크래시 원인 marks itself.
    var tint: Color? = nil
    var font: Font = .subheadline
    /// The dense form for a caption row, where a full-size tag would crowd the
    /// line it sits on.
    var isCompact = false

    var body: some View {
        // An explicit icon + text rather than `Label`: inside a custom layout
        // `Label` decides on its own that there is no room for the title and
        // renders the icon alone.
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(font)
        .fixedSize()
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 3)
        .background((tint ?? .secondary).opacity(tint == nil ? 0.12 : 0.14), in: Capsule())
        .foregroundStyle(tint ?? .secondary)
    }
}

/// One choice in a filter row: tap to narrow the list, tap the selected one's
/// neighbour to move. Selection is the accent fill, which is the only state
/// worth showing — a chip is never disabled, it is simply not the current one.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A wrapping row of `FilterChip`s bound to one selected value. The empty
/// string is the "전체" entry every filter row leads with.
struct FilterChipRow<Value: Hashable>: View {
    @Binding var selection: Value
    /// Title and the value it selects, in the order they should read.
    let choices: [(title: String, value: Value)]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(choices, id: \.value) { choice in
                FilterChip(title: choice.title, isSelected: selection == choice.value) {
                    selection = choice.value
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

/// The "아직 안 읽음" marker: a filled dot that keeps its space when read, so
/// rows don't shift as they are opened.
struct UnreadDot: View {
    let isUnread: Bool
    var diameter: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isUnread ? Color.accentColor : Color.clear)
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(isUnread ? "안 읽음" : "")
    }
}

/// The small status chip shown on list rows and cards. Nothing is drawn for
/// `pending`, so untouched rows stay as clean as they were.
struct StatusChip: View {
    let status: FeedbackStatus
    var showsLabel = true

    var body: some View {
        if status.isHandled {
            HStack(spacing: 3) {
                Image(systemName: status.systemImage)
                if showsLabel {
                    Text(status.label)
                }
            }
            .font(.caption2.weight(.medium))
            .fixedSize()
            .padding(.horizontal, showsLabel ? 6 : 3)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .accessibilityLabel(status.label)
        }
    }
}

/// A red-free count capsule for feedback still waiting on a decision.
struct PendingBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange, in: Capsule())
            .accessibilityLabel("확인 필요 \(count)건")
    }
}

/// A red count capsule for unread feedback, used on the project rows and cards.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .accessibilityLabel("안 읽음 \(count)건")
    }
}

struct StarRatingView: View {
    let rating: Int
    var maximum: Int = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maximum, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .foregroundStyle(index <= rating ? .yellow : .secondary)
                    .font(.subheadline)
            }
        }
        .accessibilityLabel("\(rating)점 / \(maximum)점")
    }
}

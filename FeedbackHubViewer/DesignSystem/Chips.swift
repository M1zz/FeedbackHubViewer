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
        //
        // 좁아지면 **아이콘부터 버린다**. 값이 태그의 내용이고 아이콘은 그
        // 값이 무엇인지 거드는 장식이라, 둘 중 하나만 남길 수 있다면 남아야
        // 하는 것은 값이다 — 접근성 글씨 크기에서 "🏷 두번알림"이 "🏷 …"이
        // 되던 자리에 "두번알림"이 온다.
        ViewThatFits(in: .horizontal) {
            label(withIcon: true)
            label(withIcon: false)
        }
        .font(font)
        // 제 너비를 **우기지 않는다**. 예전에는 `fixedSize()`로 이상적인 너비를
        // 요구했는데, 글씨를 키운 기기나 좁은 화면에서는 그 너비가 칸보다 넓어
        // 태그 하나가 줄을, 줄이 화면 전체를 밀어냈다 — 화면보다 넓어진 내용은
        // 가운데 놓인 채 **양옆이 똑같이 잘린다**. 자리가 있으면 제 너비대로,
        // 없으면 줄여 쓰다가 잘라 쓴다. 잘리는 것은 태그 하나로 끝난다.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .truncationMode(.tail)
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 3)
        .background((tint ?? .secondary).opacity(tint == nil ? 0.12 : 0.14), in: Capsule())
        .foregroundStyle(tint ?? .secondary)
    }

    @ViewBuilder
    private func label(withIcon: Bool) -> some View {
        HStack(spacing: 3) {
            if withIcon, let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
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
                // `Tag`와 같은 이유로 너비를 우기지 않는다.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
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
            // 여기서는 아이콘이 남는다. 태그와 반대인 이유는 이 칩의 내용이
            // 곧 아이콘(✓·✕)이기 때문이다 — 이름은 그 뜻을 풀어 쓴 것이라,
            // 자리가 없으면 이름을 접고 표시만 남기는 편이 읽힌다.
            ViewThatFits(in: .horizontal) {
                chip(withLabel: showsLabel)
                chip(withLabel: false)
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.tail)
            .padding(.horizontal, showsLabel ? 6 : 3)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .accessibilityLabel(status.label)
        }
    }

    private func chip(withLabel: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
            if withLabel { Text(status.label) }
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

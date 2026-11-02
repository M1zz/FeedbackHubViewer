//
//  CopyButton.swift
//  FeedbackHubViewer
//
//  A copy button that admits it worked.
//
//  Writing to the pasteboard produces no feedback of its own on either
//  platform, so the label does it: 복사 → 복사됨 for a moment, then back. The
//  text is captured at tap time, so a list row that scrolls away underneath it
//  changes nothing about what was copied.
//

import SwiftUI

struct CopyButton: View {
    let text: String
    var title: String = "복사"
    /// Compact form for a caption row: glyph only, borderless.
    var isCompact = false

    @State private var copied = false

    var body: some View {
        Button {
            Platform.copyToPasteboard(text)
            copied = true
        } label: {
            let label = Label(copied ? "복사됨" : title,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
            if isCompact {
                label.labelStyle(.iconOnly).font(.hubCaption)
            } else {
                label
            }
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .help(copied ? "복사했습니다" : title == "복사" ? "클립보드로 복사" : title)
        // Tied to `copied` rather than started inside the action: leaving the
        // view mid-countdown cancels the sleep instead of writing to state
        // that is already gone.
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// 신호등 줄 끝의 작은 복사 단추 — 앱 리포에서 연 Claude 에 붙여넣을 글.
struct ClaudeCopyIcon: View {
    let text: String

    var body: some View {
        CopyButton(text: text, title: "Claude에게 맡길 글 복사", isCompact: true)
            .font(.body)
            .frame(minWidth: 32, minHeight: 32)
    }
}

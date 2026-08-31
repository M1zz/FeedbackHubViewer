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
                label.labelStyle(.iconOnly).font(.caption)
            } else {
                label
            }
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .help(copied ? "복사했습니다" : "클립보드로 복사")
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

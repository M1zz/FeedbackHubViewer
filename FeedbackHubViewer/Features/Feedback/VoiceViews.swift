//
//  VoiceViews.swift
//  FeedbackHubViewer
//
//  한 문장 의견(LeeoKit `LeeoVoice`)을 피드백과 다르게 보이는 조각들.
//  피드백은 사용자가 스스로 쓴 글이고, 한 문장은 앱이 먼저 물어 받은 답이다 —
//  답만으로는 뜻이 서지 않으니 늘 받은 질문과 함께, 보라색으로 보인다.
//

import SwiftUI

extension Color {
    /// 한 문장 의견의 색. 피드백(파랑 · 회색)과 섞이지 않게.
    static let voice = Color.purple
}

/// "한 문장 의견" 표시와, 쓸모 질문이면 고른 정도.
struct VoiceTags: View {
    let feedback: Feedback
    var font: Font = .hubCaption2.weight(.medium)

    var body: some View {
        Tag(text: "한 문장 의견", systemImage: "quote.bubble.fill", tint: .voice, font: font)
        if let level = feedback.usefulness, let label = feedback.usefulnessLabel {
            Tag(text: String(repeating: "●", count: level) + String(repeating: "○", count: 3 - level) + " " + label,
                tint: level == 3 ? .green : .voice, font: font)
                .accessibilityLabel("쓸모 3단계 중 \(level), \(label)")
        }
    }
}

/// 그 사람이 받은 질문. 답 바로 위에 작게.
struct VoiceQuestionLine: View {
    let question: String
    var font: Font = .hubFootnote

    var body: some View {
        Text("물음  \(question)")
            .font(font)
            .foregroundStyle(Color.voice)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

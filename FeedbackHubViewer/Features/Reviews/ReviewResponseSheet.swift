//
//  ReviewResponseSheet.swift
//  FeedbackHubViewer
//
//  리뷰에 답을 쓰는 시트. 원문(과 번역)을 위에 두고 아래에서 쓴다 — 무엇에 답하는지를
//  보면서 써야 한다.
//
//  보내면 곧바로 App Store 에 올라간다(Apple 이 확인하는 동안 "게시 대기"). 그래서
//  보내기 전에 한 번 더 묻지는 않지만, 보내는 동안에는 시트를 닫지 못하게 한다 —
//  닫힌 뒤에 실패하면 무엇이 안 나갔는지 알 길이 없다.
//

import SwiftUI

struct ReviewResponseSheet: View {
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @Environment(\.dismiss) private var dismiss

    let review: CustomerReview
    let project: String

    @State private var text = ""
    @State private var isSending = false
    @State private var errorText: String?
    @FocusState private var isEditorFocused: Bool

    /// App Store Connect 가 받는 응답의 최대 글자 수.
    static let limit = 5970

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && text.count <= Self.limit && !isSending && trimmed != review.response?.responseBody }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    original
                    editor
                }
                .padding(ReviewLayout.padding)
            }
            .navigationTitle(review.response == nil ? "리뷰에 답하기" : "응답 고치기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("보내기") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSending)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 540, idealHeight: 620)
        #endif
        .onAppear {
            text = review.response?.responseBody ?? ""
            isEditorFocused = true
        }
    }

    private var original: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StarRatingView(rating: review.rating)
                Tag(text: review.territoryName, isCompact: true)
                Spacer(minLength: 4)
                Text(AppFormat.dateTime(review.createdDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CopyButton(text: review.fullText, isCompact: true)
            }
            if let title = review.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let nickname = review.reviewerNickname, !nickname.isEmpty {
                Text("— \(nickname)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TranslateToKoreanView(text: review.fullText)
                .font(.callout)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("응답")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $text)
                .font(.body)
                .focused($isEditorFocused)
                .disabled(isSending)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 180)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isEditorFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                                      lineWidth: isEditorFocused ? 2 : 1)
                )
            HStack {
                Text("리뷰를 쓴 사람의 언어로 답하는 것이 좋아요. 보내면 Apple 확인을 거쳐 App Store 에 올라갑니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(text.count) / \(Self.limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count > Self.limit ? .red : .secondary)
            }
        }
    }

    private func send() async {
        isSending = true
        errorText = nil
        defer { isSending = false }
        do {
            try await purchases.respond(to: review, in: project, text: trimmed)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

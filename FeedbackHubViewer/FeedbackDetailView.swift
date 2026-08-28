//
//  FeedbackDetailView.swift
//  FeedbackHubViewer
//
//  The right column: full text plus a table of every raw field on the record.
//

import SwiftUI

struct FeedbackDetailView: View {
    @EnvironmentObject private var store: FeedbackStore
    let feedback: Feedback
    /// Resolved project/app name (appId → appName mapping applied by the store).
    let projectLabel: String

    /// Roomier on a Mac window, tighter on a phone screen.
    #if os(macOS)
    private let contentPadding: CGFloat = 24
    private let fieldKeyWidth: CGFloat = 140
    #else
    private let contentPadding: CGFloat = 16
    private let fieldKeyWidth: CGFloat = 110
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                bigHandledButton

                Divider()

                if !feedback.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    section(title: "내용") {
                        Text(feedback.text)
                            .font(.title3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Feedback comes in whatever language its writer speaks;
                        // this puts Korean under it without leaving the app.
                        TranslateToKoreanView(text: feedback.text)
                    }
                }

                metadataGrid

                section(title: "모든 필드") {
                    VStack(spacing: 0) {
                        ForEach(Array(feedback.allFields.enumerated()), id: \.offset) { index, field in
                            HStack(alignment: .top, spacing: 12) {
                                Text(field.key)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: fieldKeyWidth, alignment: .leading)
                                Text(field.value.isEmpty ? "—" : field.value)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                            if index < feedback.allFields.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("상세")
        // Opening the detail is what counts as having seen the feedback, so the
        // unread badge for this record clears here on both platforms. 확인함 is
        // a separate, deliberate act — see the toolbar button below.
        .task(id: feedback.id) { store.markRead(feedback) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { handledButton }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The same action as the toolbar button, spelled out full width. This is
    /// the one thing you do after reading a piece of feedback, so it should not
    /// be a 20pt glyph in the corner.
    private var bigHandledButton: some View {
        let handled = store.isHandled(feedback)
        return Button {
            store.setHandled(feedback, !handled)
        } label: {
            Label(handled ? "확인 표시 해제하고 목록에 다시 보이기"
                          : "확인함으로 표시하고 목록에서 감추기",
                  systemImage: handled ? "arrow.uturn.backward" : "checkmark.circle.fill")
                .font(.headline)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(handled ? .gray : .green)
    }

    /// Marking is what takes the feedback out of the list; it is stored on this
    /// device, so it survives relaunches and never touches the hub's records.
    private var handledButton: some View {
        let handled = store.isHandled(feedback)
        return Button {
            store.setHandled(feedback, !handled)
        } label: {
            Label(handled ? "확인 해제" : "확인함",
                  systemImage: handled ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .help(handled ? "확인 표시를 지우고 목록에 다시 보이게 합니다"
                      : "확인한 피드백으로 표시하고 목록에서 감춥니다")
    }

    /// Plain-text rendering of the record, for sharing/copying from a phone.
    private var shareText: String {
        var lines = ["[\(projectLabel)] \(feedback.createdAtDisplay)"]
        if let rating = feedback.rating { lines.append("별점: \(rating)/5") }
        if let type = feedback.feedbackType, !type.isEmpty { lines.append("유형: \(type)") }
        lines.append("")
        lines.append(feedback.text)
        lines.append("")
        lines.append(contentsOf: feedback.allFields.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(projectLabel, systemImage: "square.grid.2x2")
                    .font(.title3.weight(.semibold))
                if let type = feedback.feedbackType, !type.isEmpty {
                    Text(type)
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.teal.opacity(0.15), in: Capsule())
                }
                if store.isHandled(feedback) {
                    Label("확인함", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            if let rating = feedback.rating {
                HStack(spacing: 8) {
                    StarRatingView(rating: rating)
                    Text("\(rating) / 5")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(feedback.createdAtDisplay)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataGrid: some View {
        let items: [(String, String)] = [
            ("앱 버전", feedback.appVersion ?? "—"),
            ("기기", feedback.deviceModel ?? "—"),
            ("OS", feedback.systemVersion ?? "—"),
            ("연락처", feedback.contactEmail ?? "—"),
            ("레코드 타입", feedback.recordType),
            ("Record ID", feedback.id)
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                   GridItem(.flexible(), alignment: .leading)],
                         alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    // Record IDs and device names are long; wrapping keeps the
                    // whole value readable and copyable.
                    Text(value)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }
}

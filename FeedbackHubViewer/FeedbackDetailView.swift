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

    /// The memo being typed. Seeded from the store when the record changes and
    /// written back as it is edited, so leaving the screen never loses it.
    @State private var noteDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Divider()

                triageSection

                if !feedback.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    section(title: "내용") {
                        Text(feedback.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        // unread badge for this record clears here on both platforms.
        .task(id: feedback.id) {
            store.markRead(feedback)
            noteDraft = store.note(for: feedback)
        }
        .onChange(of: noteDraft) { _, draft in
            guard draft != store.note(for: feedback) else { return }
            store.setNote(draft, for: feedback)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
            }
        }
        #endif
    }

    /// Plain-text rendering of the record, for sharing/copying from a phone.
    private var shareText: String {
        var lines = ["[\(projectLabel)] \(feedback.createdAtDisplay)"]
        if let rating = feedback.rating { lines.append("별점: \(rating)/5") }
        if let type = feedback.feedbackType, !type.isEmpty { lines.append("유형: \(type)") }
        lines.append("")
        lines.append(feedback.text)
        let status = store.status(of: feedback)
        if status.isHandled {
            let note = store.note(for: feedback)
            lines.append("처리: \(status.label)\(note.isEmpty ? "" : " — \(note)")")
        }
        lines.append("")
        lines.append(contentsOf: feedback.allFields.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
    }

    // MARK: - 처리

    /// Where the feedback is decided: 반영함 / 반영 안 함, plus a memo. The
    /// decision is kept on this device — the hub's records are read-only here
    /// (see `FeedbackTriage.swift`).
    private var triageSection: some View {
        let status = store.status(of: feedback)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("처리")
                    .font(.headline)
                Spacer(minLength: 8)
                if let decided = store.decidedAt(for: feedback) {
                    Text("\(AppFormat.dateTime(decided)) 처리")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Picker("처리 상태", selection: statusBinding) {
                // Text, not Label: a segmented control shows either a title or
                // an icon, and "반영 안 함" needs the words to be unambiguous.
                ForEach(FeedbackStatus.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("메모 (예: v1.4에 반영, 중복 피드백)", text: $noteDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Text(status.isHandled
                 ? "처리한 피드백은 목록에서 숨겨집니다. 목록 아래 '처리한 피드백 보기'로 다시 볼 수 있어요. 이 \(Platform.deviceNoun)에만 저장되고 CloudKit 레코드는 그대로입니다."
                 : "반영했거나 반영하지 않기로 했다면 위에서 표시해 두세요. 표시하면 목록에서 자동으로 빠집니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.tint.opacity(status.isHandled ? 0.08 : 0.05),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(status.isHandled ? status.tint.opacity(0.35) : Color.secondary.opacity(0.2))
        )
    }

    /// Reads and writes the decision straight through the store, so the picker
    /// can never drift out of sync with the list behind it.
    private var statusBinding: Binding<FeedbackStatus> {
        Binding(get: { store.status(of: feedback) },
                set: { status in
                    // Animated because the list behind this screen drops the
                    // row as soon as the decision lands.
                    withAnimation { store.setStatus(status, note: noteDraft, for: feedback) }
                })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(projectLabel, systemImage: "square.grid.2x2")
                    .font(.headline)
                if let type = feedback.feedbackType, !type.isEmpty {
                    Text(type)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.teal.opacity(0.15), in: Capsule())
                }
                StatusChip(status: store.status(of: feedback))
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
                .font(.subheadline)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Record IDs and device names are long; wrapping keeps the
                    // whole value readable and copyable.
                    Text(value)
                        .font(.callout)
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
                .font(.headline)
            content()
        }
    }
}

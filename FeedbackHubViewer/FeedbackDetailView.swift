//
//  FeedbackDetailView.swift
//  FeedbackHubViewer
//
//  The right column: full text plus a table of every raw field on the record.
//

import SwiftUI

struct FeedbackDetailView: View {
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

                Divider()

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
        lines.append("")
        lines.append(contentsOf: feedback.allFields.map { "\($0.key): \($0.value)" })
        return lines.joined(separator: "\n")
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
                    Text(value)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
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

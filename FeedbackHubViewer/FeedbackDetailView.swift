//
//  FeedbackDetailView.swift
//  FeedbackHubViewer
//
//  The right column: full text plus a table of every raw field on the record.
//

import SwiftUI

struct FeedbackDetailView: View {
    let feedback: Feedback

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
                                    .frame(width: 140, alignment: .leading)
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
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("상세")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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

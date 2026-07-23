//
//  FeedbackListView.swift
//  FeedbackHubViewer
//
//  The middle column: a searchable, sortable list of feedback rows.
//

import SwiftUI

struct FeedbackListView: View {
    @EnvironmentObject private var store: FeedbackStore
    @Binding var selection: Feedback.ID?

    var body: some View {
        List(selection: $selection) {
            if let error = store.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } else if store.filteredFeedback.isEmpty && !store.isLoading {
                Section {
                    Text(store.noticeMessage ?? "표시할 피드백이 없습니다.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            ForEach(store.filteredFeedback) { feedback in
                FeedbackRow(feedback: feedback)
                    .tag(feedback.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.isLoading && store.allFeedback.isEmpty {
                ProgressView("불러오는 중…")
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "피드백 검색")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("정렬", selection: $store.sortOption) {
                        ForEach(FeedbackStore.SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label("정렬: \(store.sortOption.rawValue)", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .navigationTitle("피드백")
        .navigationSubtitle("\(store.filteredFeedback.count)건 표시 / 전체 \(store.allFeedback.count)건")
    }
}

private struct FeedbackRow: View {
    let feedback: Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if let rating = feedback.rating {
                    StarRatingView(rating: rating)
                }
                Spacer()
                Text(feedback.createdAtDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(feedback.snippet)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if let version = feedback.appVersion, !version.isEmpty {
                    Badge(text: "v\(version)", systemImage: "app.badge")
                }
                if let device = feedback.deviceModel, !device.isEmpty {
                    Badge(text: device, systemImage: "iphone")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StarRatingView: View {
    let rating: Int
    var maximum: Int = 5

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...maximum, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .foregroundStyle(index <= rating ? .yellow : .secondary)
                    .font(.caption)
            }
        }
        .accessibilityLabel("\(rating)점 / \(maximum)점")
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

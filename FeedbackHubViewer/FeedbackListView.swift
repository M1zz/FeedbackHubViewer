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
        list
            .hubListStyle()
            .overlay {
                if store.isLoading && store.allFeedback.isEmpty {
                    ProgressView("불러오는 중…")
                }
            }
            .searchable(text: $store.searchText, placement: searchPlacement, prompt: "피드백 검색")
            .toolbar {
                ToolbarItem(placement: sortPlacement) {
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
            .hubNavigationSubtitle("\(store.filteredFeedback.count)건 표시 / 전체 \(store.allFeedback.count)건")
    }

    /// macOS selects a row and shows it in the detail column; iOS pushes the
    /// detail onto the navigation stack instead.
    @ViewBuilder
    private var list: some View {
        #if os(macOS)
        List(selection: $selection) {
            statusSection
            ForEach(store.filteredFeedback) { feedback in
                row(for: feedback).tag(feedback.id)
            }
        }
        #else
        List {
            statusSection
            ForEach(store.filteredFeedback) { feedback in
                NavigationLink {
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                } label: {
                    row(for: feedback)
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var statusSection: some View {
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
    }

    private func row(for feedback: Feedback) -> some View {
        FeedbackRow(feedback: feedback,
                    projectLabel: store.displayName(for: feedback.projectKey))
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .toolbar
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }

    private var sortPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        // The bottom bar is taken by the tab bar on iOS, so sorting lives in
        // the navigation bar next to refresh.
        .topBarTrailing
        #endif
    }
}

private struct FeedbackRow: View {
    let feedback: Feedback
    let projectLabel: String

    // A phone row has no detail column beside it, so it carries a little more
    // of the body text and every badge the record has.
    #if os(macOS)
    private let snippetLineLimit = 2
    #else
    private let snippetLineLimit = 3
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Badge(text: projectLabel, systemImage: "square.grid.2x2")
                if let rating = feedback.rating {
                    StarRatingView(rating: rating)
                }
                Spacer(minLength: 4)
                Text(feedback.createdAtDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(feedback.snippet)
                .font(.callout)
                .lineLimit(snippetLineLimit)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if let type = feedback.feedbackType, !type.isEmpty {
                    Badge(text: type, systemImage: "tag")
                }
                if let version = feedback.appVersion, !version.isEmpty {
                    Badge(text: "v\(version)", systemImage: "app.badge")
                }
                if let device = feedback.deviceModel, !device.isEmpty {
                    Badge(text: device, systemImage: "iphone")
                }
                if let email = feedback.contactEmail, !email.isEmpty {
                    Badge(text: email, systemImage: "envelope")
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, 3)
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

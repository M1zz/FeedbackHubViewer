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
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
            #else
            // Sorting lives above the list rather than in the window toolbar:
            // one more toolbar item pushes the stack's back button into the
            // overflow chevron, and the way back matters more.
            .safeAreaInset(edge: .top, spacing: 0) { macHeaderBar }
            #endif
            .navigationTitle(title)
            .hubNavigationSubtitle("\(store.filteredFeedback.count)건 표시 / 전체 \(store.allFeedback.count)건")
    }

    /// The list is always a scoped screen now, so it is named after its scope.
    private var title: String {
        guard let key = store.selectedProject else { return "전체 피드백" }
        return store.displayName(for: key)
    }

    private var sortMenu: some View {
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

    #if os(macOS)
    private var macHeaderBar: some View {
        HStack(spacing: 8) {
            if store.scopedUnreadCount > 0 {
                UnreadBadge(count: store.scopedUnreadCount)
                Text("안 읽음")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("모두 읽음") { store.markAllRead(project: store.selectedProject) }
                    .buttonStyle(.link)
                    .font(.callout)
            } else {
                Text("모두 확인했습니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            sortMenu
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
    #endif

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
                NavigationLink(value: feedback) {
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
                    projectLabel: store.displayName(for: feedback.projectKey),
                    isUnread: store.isUnread(feedback))
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .toolbar
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }

}

private struct FeedbackRow: View {
    let feedback: Feedback
    let projectLabel: String
    let isUnread: Bool

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
                UnreadDot(isUnread: isUnread)
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
                .fontWeight(isUnread ? .semibold : .regular)
                .lineLimit(snippetLineLimit)
                .foregroundStyle(.primary)

            // Wraps instead of dropping badges off the right edge: on a phone
            // an email plus a device name never fits on one line.
            FlowLayout(spacing: 6, lineSpacing: 4) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

/// The "아직 안 읽음" marker: a filled dot that keeps its space when read, so
/// rows don't shift as they are opened.
struct UnreadDot: View {
    let isUnread: Bool
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isUnread ? Color.accentColor : Color.clear)
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(isUnread ? "안 읽음" : "")
    }
}

/// A red count capsule for unread feedback, used on the project cards and the
/// statistics rows.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red, in: Capsule())
            .accessibilityLabel("안 읽음 \(count)건")
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
        // An explicit icon + text rather than `Label`: inside a custom layout
        // `Label` decides on its own that there is no room for the title and
        // renders the icon alone.
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption2)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
    }
}

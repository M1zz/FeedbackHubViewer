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

    /// A pending "표시된 항목 모두 …" request, awaiting confirmation. Marking
    /// dozens of records at once is worth one question.
    @State private var bulkStatus: FeedbackStatus?

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
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            #else
            // Sorting lives above the list rather than in the window toolbar:
            // one more toolbar item pushes the stack's back button into the
            // overflow chevron, and the way back matters more.
            .safeAreaInset(edge: .top, spacing: 0) { macHeaderBar }
            #endif
            .confirmationDialog(bulkPrompt,
                                isPresented: Binding(get: { bulkStatus != nil },
                                                     set: { if !$0 { bulkStatus = nil } }),
                                titleVisibility: .visible) {
                if let status = bulkStatus {
                    Button(status.actionLabel) {
                        withAnimation { store.setStatusForFiltered(status) }
                        bulkStatus = nil
                    }
                }
                Button("취소", role: .cancel) { bulkStatus = nil }
            }
            .navigationTitle(title)
            .hubNavigationSubtitle(subtitle)
    }

    /// "12건 표시 / 전체 40건 · 확인 필요 7건" — the second half is the point of
    /// the screen once triage starts.
    private var subtitle: String {
        var parts = ["\(store.filteredFeedback.count)건 표시 / 전체 \(store.allFeedback.count)건"]
        if store.scopedPendingCount > 0 {
            parts.append("확인 필요 \(store.scopedPendingCount)건")
        } else if !store.scopedFeedback.isEmpty {
            parts.append("모두 처리 완료")
        }
        return parts.joined(separator: " · ")
    }

    private var bulkPrompt: String {
        guard let status = bulkStatus else { return "" }
        return "표시된 \(store.filteredFeedback.count)건을 '\(status.label)'으로 표시할까요?"
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

    /// 처리 상태로 걸러 보기 + 표시된 항목 일괄 처리.
    private var filterMenu: some View {
        Menu {
            Picker("처리 상태", selection: $store.statusFilter) {
                ForEach(FeedbackStatusFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
            if !store.filteredFeedback.isEmpty {
                Divider()
                Section("표시된 \(store.filteredFeedback.count)건") {
                    Button {
                        bulkStatus = .applied
                    } label: {
                        Label("모두 반영함으로 표시", systemImage: FeedbackStatus.applied.systemImage)
                    }
                    Button {
                        bulkStatus = .dismissed
                    } label: {
                        Label("모두 반영 안 함으로 표시", systemImage: FeedbackStatus.dismissed.systemImage)
                    }
                }
            }
        } label: {
            Label("상태: \(store.statusFilter.label)", systemImage: store.statusFilter.systemImage)
        }
    }

    #if os(iOS)
    /// One toolbar button on a phone: a narrow navigation bar has no room for
    /// two menus beside the title.
    private var optionsMenu: some View {
        Menu {
            Picker("처리 상태", selection: $store.statusFilter) {
                ForEach(FeedbackStatusFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
            Picker("정렬", selection: $store.sortOption) {
                ForEach(FeedbackStore.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            if store.scopedUnreadCount > 0 {
                Button {
                    store.markAllRead(project: store.selectedProject)
                } label: {
                    Label("모두 읽음으로 표시", systemImage: "envelope.open")
                }
            }
            if !store.filteredFeedback.isEmpty {
                Section("표시된 \(store.filteredFeedback.count)건") {
                    Button {
                        bulkStatus = .applied
                    } label: {
                        Label("모두 반영함으로 표시", systemImage: FeedbackStatus.applied.systemImage)
                    }
                    Button {
                        bulkStatus = .dismissed
                    } label: {
                        Label("모두 반영 안 함으로 표시", systemImage: FeedbackStatus.dismissed.systemImage)
                    }
                }
            }
        } label: {
            Label("보기 설정", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
    #endif

    #if os(macOS)
    private var macHeaderBar: some View {
        HStack(spacing: 8) {
            if store.scopedPendingCount > 0 {
                PendingBadge(count: store.scopedPendingCount)
                Text("확인 필요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !store.scopedFeedback.isEmpty {
                Label("모두 처리했습니다", systemImage: FeedbackStatus.applied.systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if store.scopedUnreadCount > 0 {
                UnreadBadge(count: store.scopedUnreadCount)
                Button("모두 읽음") { store.markAllRead(project: store.selectedProject) }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            Spacer(minLength: 8)

            filterMenu
                .menuStyle(.borderlessButton)
                .fixedSize()

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
                triageAffordances(row(for: feedback).tag(feedback.id), for: feedback)
            }
            handledSwitch
        }
        // Rebuilt when the filter flips: rows swapped into a live List keep the
        // height the list measured for what was there before, which clips a
        // three-line row down to its first line.
        .id(store.statusFilter)
        #else
        List {
            statusSection
            ForEach(store.filteredFeedback) { feedback in
                triageAffordances(NavigationLink(value: feedback) { row(for: feedback) }, for: feedback)
            }
            handledSwitch
        }
        .id(store.statusFilter)
        #endif
    }

    /// The way back to what was already decided. Handled feedback leaves the
    /// list the moment it is marked, so this row is the only thing standing
    /// between the user and the impression that it was deleted.
    @ViewBuilder
    private var handledSwitch: some View {
        let showingPending = store.statusFilter == .pending
        if store.scopedHandledCount > 0 || !showingPending {
            Section {
                Button {
                    // Deliberately not animated: swapping the whole list
                    // contents mid-animation leaves rows stuck at the height
                    // they were measured with, showing only their first line.
                    store.statusFilter = showingPending ? .handled : .pending
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showingPending ? "checkmark.circle" : "arrow.uturn.backward")
                        Text(showingPending
                             ? "처리한 피드백 \(store.scopedHandledCount)건 보기"
                             : "확인 필요만 보기 (\(store.scopedPendingCount)건)")
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Swipe to decide, or right-click for the full set — the same three states
    /// the detail view offers, without opening it.
    private func triageAffordances<Content: View>(_ content: Content,
                                                  for feedback: Feedback) -> some View {
        let status = store.status(of: feedback)
        return content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                swipeButton(to: status == .applied ? .pending : .applied, for: feedback)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                swipeButton(to: status == .dismissed ? .pending : .dismissed, for: feedback)
            }
            .contextMenu {
                ForEach(FeedbackStatus.allCases.filter { $0 != status }) { option in
                    Button {
                        withAnimation { store.setStatus(option, for: feedback) }
                    } label: {
                        Label(option.actionLabel, systemImage: option.systemImage)
                    }
                }
                if store.isUnread(feedback) {
                    Divider()
                    Button {
                        store.markRead(feedback)
                    } label: {
                        Label("읽음으로 표시", systemImage: "envelope.open")
                    }
                }
            }
    }

    private func swipeButton(to status: FeedbackStatus, for feedback: Feedback) -> some View {
        Button {
            // The row usually leaves the list on the way out (the default
            // filter is 확인 필요), so let it animate rather than blink away.
            withAnimation { store.setStatus(status, for: feedback) }
        } label: {
            Label(status.label, systemImage: status.systemImage)
        }
        .tint(status == .dismissed ? .gray : status.tint)
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
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    /// An empty list after filtering is not the same thing as an empty hub —
    /// say which one it is, or the screen looks broken.
    private var emptyMessage: String {
        if let notice = store.noticeMessage { return notice }
        if store.scopedFeedback.isEmpty { return "표시할 피드백이 없습니다." }
        if store.statusFilter == .pending {
            return "확인이 필요한 피드백이 없습니다. 모두 처리했습니다."
        }
        return "'\(store.statusFilter.label)' 상태인 피드백이 없습니다."
    }

    private func row(for feedback: Feedback) -> some View {
        FeedbackRow(feedback: feedback,
                    projectLabel: store.displayName(for: feedback.projectKey),
                    isUnread: store.isUnread(feedback),
                    status: store.status(of: feedback),
                    note: store.note(for: feedback))
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
    let status: FeedbackStatus
    let note: String

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
                StatusChip(status: status)
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
                // Decided feedback steps back visually so what is left to do
                // stands out in a long list.
                .foregroundStyle(status.isHandled ? .secondary : .primary)

            if !note.isEmpty {
                Label(note, systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

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

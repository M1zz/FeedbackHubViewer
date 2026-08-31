//
//  FeedbackListView.swift
//  FeedbackHubViewer
//
//  The 피드백 section of a project screen: a searchable, sortable list of
//  feedback rows. Decided feedback (반영함 / 반영 안 함) folds out of the way
//  here — see `FeedbackTriage.swift` and `FeedbackStore.triage`. The screen's
//  title and scope belong to `ProjectSectionView`; this view owns only the list
//  and its own controls.
//

import SwiftUI

struct FeedbackListView: View {
    @EnvironmentObject private var store: FeedbackStore
    @Binding var selection: Feedback.ID?
    /// iOS only: the search field replaces the header row while it is open, so
    /// nothing takes up space until search is actually asked for.
    @State private var isSearching = false

    /// A pending "표시된 항목 모두 …" request, awaiting confirmation. Marking
    /// dozens of records at once is worth one question.
    @State private var bulkStatus: FeedbackStatus?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            list
                .hubListStyle()
                .overlay {
                    if store.isLoading && store.allFeedback.isEmpty {
                        ProgressView(store.refreshProgress?.text ?? "불러오는 중…")
                            .monospacedDigit()
                    }
                }
        }
        #if os(macOS)
        // The Mac has a window toolbar to keep it in; it costs no room there.
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "피드백 검색")
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
    }

    private var bulkPrompt: String {
        guard let status = bulkStatus else { return "" }
        return "표시된 \(store.filteredFeedback.count)건을 '\(status.label)'으로 표시할까요?"
    }

    // MARK: - Controls

    /// One bar on both platforms. Short, labelled buttons — the counts are
    /// already spelled out one level up in the section buttons, so this row
    /// carries the *actions* and nothing else.
    @ViewBuilder
    private var headerBar: some View {
        Group {
            #if os(iOS)
            if isSearching {
                searchField
            } else {
                actionRow
            }
            #else
            actionRow
            #endif
        }
        .font(.body)
        .hubHeaderBar(horizontalPadding: 14)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if store.scopedUnreadCount > 0 {
                Button {
                    store.markAllRead(project: store.selectedProject)
                } label: {
                    Label("모두 읽음", systemImage: "envelope.open")
                }
                .buttonStyle(.bordered)
            } else if store.scopedPendingCount > 0 {
                // 안 읽은 건 없지만 아직 결정이 남았다 — 남은 일이 무엇인지가
                // 이 줄에서 가장 중요한 정보다.
                HStack(spacing: 6) {
                    PendingBadge(count: store.scopedPendingCount)
                    Text("확인 필요")
                        .foregroundStyle(.secondary)
                }
            } else if !store.scopedFeedback.isEmpty {
                // Reaching zero is the point of the screen, so it gets to look
                // like an achievement instead of disabled grey text.
                Tag(text: "모두 처리했습니다", systemImage: "checkmark.seal.fill",
                    tint: .green, font: .body.weight(.semibold))
            }

            Spacer(minLength: 8)

            #if os(iOS)
            Button {
                isSearching = true
            } label: {
                Label("검색", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            #endif

            optionsMenu
                .fixedSize()
        }
        .lineLimit(1)
    }

    #if os(iOS)
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("피드백 검색", text: $store.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            Button("닫기") {
                store.searchText = ""
                isSearching = false
            }
            .buttonStyle(.borderless)
        }
    }
    #endif

    /// 정렬 · 처리 상태 · 필터 · 일괄 처리를 한 메뉴에 모은다. 좁은 화면에
    /// 메뉴를 둘로 나눌 자리가 없다.
    private var optionsMenu: some View {
        Menu {
            Picker("정렬", selection: $store.sortOption) {
                ForEach(FeedbackStore.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Section("처리 상태") {
                Picker("처리 상태", selection: $store.statusFilter) {
                    ForEach(FeedbackStatusFilter.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                }
                if !store.filteredFeedback.isEmpty {
                    Button {
                        bulkStatus = .applied
                    } label: {
                        Label("표시된 \(store.filteredFeedback.count)건 모두 반영함",
                              systemImage: FeedbackStatus.applied.systemImage)
                    }
                    Button {
                        bulkStatus = .dismissed
                    } label: {
                        Label("표시된 \(store.filteredFeedback.count)건 모두 반영 안 함",
                              systemImage: FeedbackStatus.dismissed.systemImage)
                    }
                }
            }

            Section("필터") {
                Picker("앱 버전", selection: $store.selectedVersion) {
                    Text("전체 버전").tag(String?.none)
                    ForEach(store.availableVersions, id: \.self) { version in
                        Text("v\(version)").tag(String?.some(version))
                    }
                }
                Picker("최소 별점", selection: $store.minimumRating) {
                    Text("전체 별점").tag(0)
                    ForEach((1...5).reversed(), id: \.self) { r in
                        Text("\(r)점 이상").tag(r)
                    }
                }
                if hasActiveFilters {
                    Button {
                        store.selectedVersion = nil
                        store.minimumRating = 0
                        store.searchText = ""
                    } label: {
                        Label("필터 초기화", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Label(hasActiveFilters ? "정렬 · 필터 사용 중" : "정렬 · 필터",
                  systemImage: hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                .font(.body)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    private var hasActiveFilters: Bool {
        store.selectedVersion != nil || store.minimumRating > 0 || !store.searchText.isEmpty
    }

    // MARK: - List

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
                triageAffordances(row(for: feedback), for: feedback)
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
                        setStatus(option, for: feedback)
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
            setStatus(status, for: feedback)
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
        let status = store.status(of: feedback)
        return HStack(spacing: 6) {
            FeedbackRow(feedback: feedback,
                        projectLabel: store.displayName(for: feedback.projectKey),
                        isUnread: store.isUnread(feedback),
                        status: status,
                        note: store.note(for: feedback))
                #if os(iOS)
                // A plain tap target rather than a `NavigationLink`: a link
                // inside the row would draw its own chevron next to the List's,
                // and the row needs room for the decide button beside it.
                .contentShape(Rectangle())
                .onTapGesture { store.path.append(feedback) }
                #endif

            #if os(iOS)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            #endif

            decideButton(for: feedback, status: status)
        }
    }

    /// The one-tap affordance every row carries: 반영함으로 표시, or back to
    /// 확인 필요 if it is already decided. 반영 안 함 stays on the swipe and the
    /// context menu — a row has space for the common case, not for both.
    private func decideButton(for feedback: Feedback, status: FeedbackStatus) -> some View {
        Button {
            setStatus(status.isHandled ? .pending : .applied, for: feedback)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: status.isHandled ? status.systemImage : "circle")
                    .font(.title2)
                Text(status.isHandled ? status.label : "반영함")
                    .font(.caption2)
            }
            .foregroundStyle(status.isHandled ? status.tint : Color.secondary)
            .frame(width: 54, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(status.isHandled ? "확인 필요로 되돌리고 목록에 다시 보이게 합니다"
                               : "반영함으로 표시하고 목록에서 감춥니다")
        .accessibilityLabel(status.isHandled ? "확인 필요로 되돌리기" : "반영함으로 표시")
    }

    /// Deciding the selected row hides it, and a `List` fills the gap by moving
    /// its selection to the neighbour — which would open that feedback and mark
    /// it read behind the user's back. Drop the selection instead.
    private func setStatus(_ status: FeedbackStatus, for feedback: Feedback) {
        if status.isHandled && store.statusFilter == .pending && selection == feedback.id {
            selection = nil
        }
        // The row usually leaves the list on the way out (the default filter is
        // 확인 필요), so let it animate rather than blink away.
        withAnimation { store.setStatus(status, for: feedback) }
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

    /// The full timestamp fits on a Mac; a phone row gets "3일 전" so the date
    /// never eats the space the project name needs.
    private var dateLabel: String {
        #if os(macOS)
        feedback.createdAtDisplay
        #else
        feedback.createdAtRelative
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                UnreadDot(isUnread: isUnread)
                Tag(text: projectLabel, systemImage: "square.grid.2x2")
                if let rating = feedback.rating {
                    StarRatingView(rating: rating)
                }
                StatusChip(status: status)
                Spacer(minLength: 4)
                Text(dateLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(feedback.snippet)
                .font(.body)
                .fontWeight(isUnread ? .semibold : .regular)
                .lineLimit(snippetLineLimit)
                // Decided feedback steps back visually so what is left to do
                // stands out in a long list.
                .foregroundStyle(status.isHandled ? .secondary : .primary)

            if !note.isEmpty {
                Label(note, systemImage: "text.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Wraps instead of dropping badges off the right edge: on a phone
            // an email plus a device name never fits on one line.
            FlowLayout(spacing: 6, lineSpacing: 4) {
                if let type = feedback.feedbackType, !type.isEmpty {
                    Tag(text: type, systemImage: "tag")
                }
                if let version = feedback.appVersion, !version.isEmpty {
                    Tag(text: "v\(version)", systemImage: "app.badge")
                }
                if let device = feedback.deviceModel, !device.isEmpty {
                    Tag(text: device, systemImage: "iphone")
                }
                if let email = feedback.contactEmail, !email.isEmpty {
                    Tag(text: email, systemImage: "envelope")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

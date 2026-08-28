//
//  FeedbackListView.swift
//  FeedbackHubViewer
//
//  The 피드백 section of a project screen: a searchable, sortable list of
//  feedback rows. Confirmed ("확인함") feedback is folded out of the way here —
//  see `FeedbackStore.handledIDs`. The screen's title and scope belong to
//  `ProjectSectionView`; this view owns only the list and its own controls.
//

import SwiftUI

struct FeedbackListView: View {
    @EnvironmentObject private var store: FeedbackStore
    @Binding var selection: Feedback.ID?
    /// iOS only: the search field replaces the header row while it is open, so
    /// nothing takes up space until search is actually asked for.
    @State private var isSearching = false

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
            } else {
                // Reaching zero is the point of the screen, so it gets to look
                // like an achievement instead of disabled grey text.
                Label("모두 읽었습니다", systemImage: "checkmark.seal.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 8)

            if handledCount > 0 {
                Button {
                    store.showHandled.toggle()
                } label: {
                    Label("확인함 \(handledCount)", systemImage: store.showHandled ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .help(store.showHandled ? "확인한 피드백을 다시 감춥니다" : "확인해서 감춘 피드백을 봅니다")
            }

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

    private var handledCount: Int { store.scopedHandledCount }

    private var optionsMenu: some View {
        Menu {
            Picker("정렬", selection: $store.sortOption) {
                ForEach(FeedbackStore.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Section("확인함") {
                Toggle(isOn: $store.showHandled) {
                    Label("확인한 피드백도 보기", systemImage: "checkmark.circle")
                }
                if handledCount > 0 {
                    Button {
                        store.clearHandled(project: store.selectedProject)
                    } label: {
                        Label("확인 표시 모두 해제 (\(handledCount)건)", systemImage: "arrow.uturn.backward")
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
                row(for: feedback).tag(feedback.id)
            }
        }
        #else
        List {
            statusSection
            ForEach(store.filteredFeedback) { feedback in
                row(for: feedback)
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
                if handledCount > 0 && !store.showHandled {
                    // Nothing left *because* it was all dealt with reads very
                    // differently from nothing having arrived.
                    Button {
                        store.showHandled = true
                    } label: {
                        Label("확인한 \(handledCount)건만 남아 있습니다 · 보기",
                              systemImage: "checkmark.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(store.noticeMessage ?? "표시할 피드백이 없습니다.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }

    private func row(for feedback: Feedback) -> some View {
        let handled = store.isHandled(feedback)
        return HStack(spacing: 6) {
            FeedbackRow(feedback: feedback,
                        projectLabel: store.displayName(for: feedback.projectKey),
                        isUnread: store.isUnread(feedback),
                        isHandled: handled)
                #if os(iOS)
                // A plain tap target rather than a `NavigationLink`: a link
                // inside the row would draw its own chevron next to the List's,
                // and the row needs room for the check-off button beside it.
                .contentShape(Rectangle())
                .onTapGesture { store.path.append(feedback) }
                #endif

            #if os(iOS)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            #endif

            handledButton(for: feedback, handled: handled)
        }
        .swipeActions(edge: .trailing) {
            Button {
                setHandled(feedback, !handled)
            } label: {
                Label(handled ? "확인 해제" : "확인함",
                      systemImage: handled ? "arrow.uturn.backward" : "checkmark.circle")
            }
            .tint(handled ? .gray : .green)
        }
        .contextMenu {
            Button {
                setHandled(feedback, !handled)
            } label: {
                Label(handled ? "확인 표시 해제" : "확인함으로 표시하고 감추기",
                      systemImage: handled ? "arrow.uturn.backward" : "checkmark.circle")
            }
        }
    }

    /// The check-off box every row carries: an empty circle to tick, a filled
    /// green one to untick. A swipe or a context menu can do the same thing,
    /// but neither is visible, and this is the one action a triaged list needs.
    private func handledButton(for feedback: Feedback, handled: Bool) -> some View {
        Button {
            setHandled(feedback, !handled)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: handled ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                Text(handled ? "확인함" : "확인")
                    .font(.caption2)
            }
            .foregroundStyle(handled ? Color.green : Color.secondary)
            .frame(width: 54, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(handled ? "확인 표시를 지우고 목록에 다시 보이게 합니다"
                      : "확인한 피드백으로 표시하고 목록에서 감춥니다")
        .accessibilityLabel(handled ? "확인 해제" : "확인함으로 표시")
    }

    /// Marking the selected row hides it, and a `List` fills the gap by moving
    /// its selection to the neighbour — which would open that feedback and mark
    /// it read behind the user's back. Drop the selection instead.
    private func setHandled(_ feedback: Feedback, _ handled: Bool) {
        if handled && selection == feedback.id { selection = nil }
        store.setHandled(feedback, handled)
    }

}

private struct FeedbackRow: View {
    let feedback: Feedback
    let projectLabel: String
    let isUnread: Bool
    let isHandled: Bool

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
                Badge(text: projectLabel, systemImage: "square.grid.2x2")
                if let rating = feedback.rating {
                    StarRatingView(rating: rating)
                }
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
                .foregroundStyle(isHandled ? .secondary : .primary)

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
        .padding(.vertical, 8)
    }
}

/// The "아직 안 읽음" marker: a filled dot that keeps its space when read, so
/// rows don't shift as they are opened.
struct UnreadDot: View {
    let isUnread: Bool
    var diameter: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isUnread ? Color.accentColor : Color.clear)
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(isUnread ? "안 읽음" : "")
    }
}

/// A red count capsule for unread feedback, used on the project rows and cards.
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
        HStack(spacing: 2) {
            ForEach(1...maximum, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .foregroundStyle(index <= rating ? .yellow : .secondary)
                    .font(.subheadline)
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
        .font(.subheadline)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(.secondary)
    }
}

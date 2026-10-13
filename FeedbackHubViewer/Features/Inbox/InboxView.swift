//
//  InboxView.swift
//  FeedbackHubViewer
//
//  "할 일" — 전체 프로젝트를 고르면 처음 보이는 화면. 모든 앱에 걸쳐 아직 손대지 않은
//  것만 한 목록에 모은다: 답장하지 않은 스토어 리뷰, 처리하지 않은 버그 리포트,
//  처리하지 않은 피드백. 앱마다 묶고, 앱 안에서는 뱃지와 같은 순서(`AttentionKind`) —
//  리뷰가 맨 위. 앱마다 다섯 줄까지 보이고 나머지는 "더 보기".
//
//  "버그 리포트"는 앱이 `type` 을 bug 로 보낸 피드백이다(`Feedback.isBugReport`).
//  진단(크래시)은 넣지 않는다 — 처리했다고 표시할 상태가 없어서, 한 번 들어오면 영영
//  "할 일"로 남는다. 진단은 진단 탭에서 묶어 본다.
//
//  처리하면(반영함 · 반영 안 함, 답장 보내기) 그 자리에서 빠진다.
//

import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    /// 맥은 고른 피드백을 오른쪽 상세 칸에 연다(`SplitRootView`).
    @Binding var selection: Feedback.ID?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "전체"
        case reviews = "리뷰"
        case bugs = "버그"
        case feedback = "피드백"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var replying: ReviewItem?
    /// "더 보기"로 다 펼친 앱.
    @State private var expanded: Set<String> = []

    struct ReviewItem: Identifiable {
        let project: String
        let review: CustomerReview
        var id: String { review.id }
    }

    // MARK: 모으기

    private var unansweredReviews: [ReviewItem] {
        purchases.reviewFeeds
            .filter { !store.hiddenProjects.contains($0.key) }
            .flatMap { key, feed in
                feed.reviews.filter { $0.response == nil }.map { ReviewItem(project: key, review: $0) }
            }
            .sorted { $0.review.createdDate > $1.review.createdDate }
    }

    /// 처리하지 않은 피드백 전부, 새것부터. 버그와 나머지로 나눈다.
    private var pending: (bugs: [Feedback], others: [Feedback]) {
        let items = store.feedback(for: nil)
            .filter { !store.status(of: $0).isHandled }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return (items.filter(\.isBugReport), items.filter { !$0.isBugReport })
    }

    var body: some View {
        let reviews = unansweredReviews
        let pending = pending

        list(reviews: reviews, bugs: pending.bugs, others: pending.others)
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar(reviews: reviews.count, bugs: pending.bugs.count, others: pending.others.count)
            }
            .task(id: store.projectCounts.count) { await loadReviews() }
            .sheet(item: $replying) { item in
                ReviewResponseSheet(review: item.review, project: item.project)
                    .environmentObject(purchases)
            }
    }

    private func filterBar(reviews: Int, bugs: Int, others: Int) -> some View {
        Picker("보기", selection: $filter) {
            ForEach(Filter.allCases) { option in
                Text(label(option, reviews: reviews, bugs: bugs, others: others)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .hubHeaderBar(verticalPadding: 8)
    }

    private func label(_ option: Filter, reviews: Int, bugs: Int, others: Int) -> String {
        switch option {
        case .all: "전체 \(reviews + bugs + others)"
        case .reviews: "리뷰 \(reviews)"
        case .bugs: "버그 \(bugs)"
        case .feedback: "피드백 \(others)"
        }
    }

    // MARK: 목록

    @ViewBuilder
    private func list(reviews: [ReviewItem], bugs: [Feedback], others: [Feedback]) -> some View {
        let showsReviews = filter == .all || filter == .reviews
        let showsBugs = filter == .all || filter == .bugs
        let showsOthers = filter == .all || filter == .feedback
        let isEmpty = (!showsReviews || reviews.isEmpty) && (!showsBugs || bugs.isEmpty)
            && (!showsOthers || others.isEmpty)

        // 보이는 행이 바뀌면 목록을 새로 만든다. 살아 있는 `List` 에 행을 바꿔 넣으면
        // 전에 재 둔 높이를 그대로 써서(리뷰가 늦게 들어올 때, 필터를 바꿀 때) 여러 줄짜리
        // 행이 첫 줄만 남고 서로 겹친다 — `FeedbackListView` 와 같은 까닭.
        let rowsKey = rowsKey(reviews: showsReviews ? reviews : [],
                              feedback: (showsBugs ? bugs : []) + (showsOthers ? others : []))

        #if os(macOS)
        List(selection: $selection) {
            sections(reviews: showsReviews ? reviews : nil,
                     bugs: showsBugs ? bugs : nil,
                     others: showsOthers ? others : nil,
                     isEmpty: isEmpty)
        }
        .hubListStyle()
        .id(rowsKey)
        #else
        List {
            sections(reviews: showsReviews ? reviews : nil,
                     bugs: showsBugs ? bugs : nil,
                     others: showsOthers ? others : nil,
                     isEmpty: isEmpty)
        }
        .hubListStyle()
        .id(rowsKey)
        #endif
    }

    private func rowsKey(reviews: [ReviewItem], feedback: [Feedback]) -> Int {
        var hasher = Hasher()
        hasher.combine(filter)
        hasher.combine(purchases.isConfigured)
        // "더 보기"로 펼치고 접어도 보이는 행이 바뀐다.
        for project in expanded.sorted() { hasher.combine(project) }
        for item in reviews { hasher.combine(item.id) }
        for item in feedback { hasher.combine(item.id) }
        return hasher.finalize()
    }

    /// 한 앱의 남은 일. 리뷰 → 버그 → 피드백 순.
    private struct AppGroup: Identifiable {
        let project: String
        let reviews: [ReviewItem]
        let bugs: [Feedback]
        let others: [Feedback]
        var id: String { project }
        var total: Int { reviews.count + bugs.count + others.count }
    }

    /// 앱마다 묶는다. 답 안 한 리뷰가 많은 앱이 먼저, 같으면 남은 일이 많은 앱.
    private func groups(reviews: [ReviewItem], bugs: [Feedback], others: [Feedback]) -> [AppGroup] {
        let reviewsByApp = Dictionary(grouping: reviews, by: \.project)
        let bugsByApp = Dictionary(grouping: bugs, by: \.projectKey)
        let othersByApp = Dictionary(grouping: others, by: \.projectKey)
        let keys = Set(reviewsByApp.keys).union(bugsByApp.keys).union(othersByApp.keys)
        return keys.map { key in
            AppGroup(project: key, reviews: reviewsByApp[key] ?? [],
                     bugs: bugsByApp[key] ?? [], others: othersByApp[key] ?? [])
        }
        .sorted { a, b in
            if a.reviews.count != b.reviews.count { return a.reviews.count > b.reviews.count }
            if a.total != b.total { return a.total > b.total }
            return store.displayName(for: a.project)
                .localizedStandardCompare(store.displayName(for: b.project)) == .orderedAscending
        }
    }

    /// 앱 하나에 처음 보이는 줄 수. 한 앱의 오래된 리뷰 수백 건이 다른 앱을 밀어내지 않게.
    private static let collapsedLimit = 5

    @ViewBuilder
    private func sections(reviews: [ReviewItem]?, bugs: [Feedback]?, others: [Feedback]?,
                          isEmpty: Bool) -> some View {
        if isEmpty {
            Section {
                Label("남은 일이 없습니다. 모두 답하고 처리했습니다.", systemImage: "checkmark.seal")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }

        if reviews != nil, !purchases.isConfigured {
            Section {
                HStack {
                    Text("App Store Connect 키를 넣으면 모든 앱의 리뷰가 여기에 모입니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    OpenSettingsButton(title: "설정 열기")
                        .font(.body)
                }
            }
        }

        ForEach(groups(reviews: reviews ?? [], bugs: bugs ?? [], others: others ?? [])) { group in
            Section {
                appRows(group)
            } header: {
                appHeader(group)
            }
        }
    }

    @ViewBuilder
    private func appRows(_ group: AppGroup) -> some View {
        let isExpanded = expanded.contains(group.project)
        let limit = isExpanded ? Int.max : Self.collapsedLimit
        let reviews = Array(group.reviews.prefix(limit))
        let bugs = Array(group.bugs.prefix(max(limit - reviews.count, 0)))
        let others = Array(group.others.prefix(max(limit - reviews.count - bugs.count, 0)))

        ForEach(reviews) { reviewRow($0) }
        ForEach(bugs) { feedbackRow($0) }
        ForEach(others) { feedbackRow($0) }

        let hidden = group.total - reviews.count - bugs.count - others.count
        if hidden > 0 || (isExpanded && group.total > Self.collapsedLimit) {
            Button {
                if isExpanded { expanded.remove(group.project) } else { expanded.insert(group.project) }
            } label: {
                Label(isExpanded ? "접기" : "\(hidden)건 더 보기",
                      systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.body)
            }
            .buttonStyle(.borderless)
        }
    }

    private func appHeader(_ group: AppGroup) -> some View {
        var parts: [String] = []
        if !group.reviews.isEmpty { parts.append("리뷰 \(group.reviews.count)") }
        if !group.bugs.isEmpty { parts.append("버그 \(group.bugs.count)") }
        if !group.others.isEmpty { parts.append("피드백 \(group.others.count)") }
        return HStack(spacing: 8) {
            Text(store.displayName(for: group.project))
                .font(.headline)
            Text(parts.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("앱 열기") { store.open(project: group.project, section: .feedback) }
                .buttonStyle(.borderless)
                .font(.body)
        }
        .textCase(nil)
    }

    // MARK: 리뷰 한 줄

    private func reviewRow(_ item: ReviewItem) -> some View {
        let review = item.review
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Tag(text: store.displayName(for: item.project), systemImage: "square.grid.2x2")
                StarRatingView(rating: review.rating)
                if review.isNew {
                    Tag(text: "새 리뷰", systemImage: "circle.fill", tint: .red)
                }
                Spacer(minLength: 4)
                Text(AppFormat.dateTime(review.createdDate))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let title = review.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .lineLimit(3)
            }
            HStack {
                Text(review.territoryName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    replying = item
                } label: {
                    Label("답장 쓰기", systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.bordered)
                .font(.body)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: 피드백 한 줄

    private func feedbackRow(_ feedback: Feedback) -> some View {
        HStack(spacing: 6) {
            FeedbackRow(feedback: feedback,
                        projectLabel: store.displayName(for: feedback.projectKey),
                        isUnread: store.isUnread(feedback),
                        status: store.status(of: feedback),
                        note: store.note(for: feedback))
                #if os(iOS)
                .contentShape(Rectangle())
                .onTapGesture { store.path.append(feedback) }
                #endif

            Button {
                decide(.applied, feedback)
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "circle")
                        .font(.title2)
                    Text("반영함")
                        .font(.body)
                }
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("반영함으로 표시하고 할 일에서 뺍니다")
            .accessibilityLabel("반영함으로 표시")
        }
        .tag(feedback.id)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { decide(.applied, feedback) } label: {
                Label(FeedbackStatus.applied.label, systemImage: FeedbackStatus.applied.systemImage)
            }
            .tint(FeedbackStatus.applied.tint)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { decide(.dismissed, feedback) } label: {
                Label(FeedbackStatus.dismissed.label, systemImage: FeedbackStatus.dismissed.systemImage)
            }
            .tint(.gray)
        }
        .contextMenu {
            ForEach([FeedbackStatus.applied, .dismissed]) { option in
                Button { decide(option, feedback) } label: {
                    Label(option.actionLabel, systemImage: option.systemImage)
                }
            }
        }
    }

    /// 처리한 행은 목록에서 빠진다. 고른 채로 빠지면 `List` 가 옆 행으로 고름을
    /// 옮겨 그것을 몰래 읽음으로 만드니, 고름을 먼저 푼다(`FeedbackListView` 와 같은 까닭).
    private func decide(_ status: FeedbackStatus, _ feedback: Feedback) {
        if selection == feedback.id { selection = nil }
        withAnimation { store.setStatus(status, for: feedback) }
    }

    // MARK: 리뷰 받기

    private func loadReviews() async {
        await purchases.loadReviews(bundleIDs: store.projectCounts.map(\.key))
    }
}

extension Feedback {
    /// 앱이 `type` 을 bug(또는 버그)로 보낸 피드백.
    var isBugReport: Bool {
        guard let type = feedbackType?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return type.contains("bug") || type.contains("버그")
    }
}

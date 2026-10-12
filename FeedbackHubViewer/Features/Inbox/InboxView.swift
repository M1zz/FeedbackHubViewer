//
//  InboxView.swift
//  FeedbackHubViewer
//
//  "할 일" — 전체 프로젝트를 고르면 처음 보이는 화면. 모든 앱에 걸쳐 아직 손대지 않은
//  것만 한 목록에 모은다: 답장하지 않은 스토어 리뷰, 처리하지 않은 버그 리포트,
//  처리하지 않은 피드백. 순서는 뱃지와 같다(`AttentionKind`) — 리뷰가 맨 위.
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
        for item in reviews { hasher.combine(item.id) }
        for item in feedback { hasher.combine(item.id) }
        return hasher.finalize()
    }

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

        if let reviews {
            if !purchases.isConfigured {
                Section("답장하지 않은 리뷰") {
                    HStack {
                        Text("App Store Connect 키를 넣으면 모든 앱의 리뷰가 여기에 모입니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        OpenSettingsButton(title: "설정 열기")
                            .font(.body)
                    }
                }
            } else if !reviews.isEmpty {
                Section {
                    ForEach(reviews) { item in
                        reviewRow(item)
                    }
                } header: {
                    header("답장하지 않은 리뷰", count: reviews.count, systemImage: AttentionKind.review.systemImage)
                }
            }
        }

        if let bugs, !bugs.isEmpty {
            Section {
                ForEach(bugs) { feedbackRow($0) }
            } header: {
                header("처리하지 않은 버그 리포트", count: bugs.count, systemImage: "ladybug.fill")
            }
        }

        if let others, !others.isEmpty {
            Section {
                ForEach(others) { feedbackRow($0) }
            } header: {
                header("처리하지 않은 피드백", count: others.count, systemImage: AttentionKind.feedback.systemImage)
            }
        }
    }

    private func header(_ title: String, count: Int, systemImage: String) -> some View {
        Label("\(title) \(count)건", systemImage: systemImage)
            .font(.headline)
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

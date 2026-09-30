//
//  ReviewsView.swift
//  FeedbackHubViewer
//
//  "리뷰" 섹션 — ReviewManager 를 통째로 옮겨 온 자리.
//
//  한 앱을 고르면 그 앱의 App Store 리뷰를 읽고(목록) 숫자로 본다(통계). 목록에서는
//  걸러 보고, 번역하고, 복사하고, 답을 달고 고치고 지운다. 전체 프로젝트에서는 리뷰
//  하나하나가 아니라 **어느 앱을 먼저 볼지** — 위험 · 기회 점수(`ReviewPriorityView`) —
//  를 보여 준다. 스무 개 앱의 리뷰를 한 목록에 섞으면 무엇부터 할지가 안 보인다.
//
//  ReviewManager 에서 옮기지 않은 것: 앱 목록(여기서는 프로젝트가 그 자리다), 키 입력
//  온보딩(설정에 이미 있다), 다운로드 · 판매 · 노출 카드(앱 내 구입 · 키워드 섹션에 이미
//  있다), 데모 모드(샘플 데이터를 진짜와 한 화면에 섞을 이유가 없다).
//

import SwiftUI

struct ReviewsView: View {
    @EnvironmentObject private var purchases: AppStoreConnectStore
    /// nil == 전체 프로젝트.
    let project: String?

    var body: some View {
        if !purchases.isConfigured {
            ScrollView {
                Card(title: "App Store Connect 연결 안 됨", systemImage: "key") {
                    Text("설정에서 App Store Connect API 키(Issuer ID · Key ID · .p8)를 넣으면 앱마다 스토어 리뷰를 읽고, 여기서 바로 답을 달 수 있습니다. 답을 달려면 키 역할이 Admin · App Manager · Customer Support 중 하나여야 해요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    OpenSettingsButton(title: "설정 열기")
                        .buttonStyle(.borderedProminent)
                        .font(.body)
                }
                .padding(ReviewLayout.padding)
            }
        } else if let project {
            ProjectReviewsView(project: project)
                // 앱을 바꾸면 거르기 · 검색 · 펼침을 새로 시작한다.
                .id(project)
        } else {
            ReviewPriorityView()
        }
    }
}

enum ReviewLayout {
    #if os(macOS)
    static let padding: CGFloat = 16
    static let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    #else
    static let padding: CGFloat = 12
    static let tileColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    #endif

    static func ratingTint(_ rating: Int) -> Color {
        switch rating {
        case 5: return .green
        case 4: return .blue
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}

// MARK: - 거르기 · 정렬

enum ReviewFilter: Hashable, Identifiable {
    case all, unanswered, answered, new
    case rating(Int)

    static let allCases: [ReviewFilter] = [.all, .unanswered, .answered, .new] + (1...5).reversed().map { .rating($0) }

    var id: String { label }

    var label: String {
        switch self {
        case .all: return "전체"
        case .unanswered: return "답 안 함"
        case .answered: return "답함"
        case .new: return "새 리뷰 (24시간)"
        case .rating(let stars): return "별 \(stars)개"
        }
    }

    func matches(_ review: CustomerReview) -> Bool {
        switch self {
        case .all: return true
        case .unanswered: return review.response == nil
        case .answered: return review.response != nil
        case .new: return review.isNew
        case .rating(let stars): return review.rating == stars
        }
    }
}

enum ReviewSort: String, CaseIterable, Identifiable {
    case newest = "최신순"
    case oldest = "오래된순"
    case ratingHigh = "별점 높은순"
    case ratingLow = "별점 낮은순"
    var id: String { rawValue }

    func sorted(_ reviews: [CustomerReview]) -> [CustomerReview] {
        switch self {
        case .newest: return reviews.sorted { $0.createdDate > $1.createdDate }
        case .oldest: return reviews.sorted { $0.createdDate < $1.createdDate }
        case .ratingHigh: return reviews.sorted { ($0.rating, $0.createdDate) > ($1.rating, $1.createdDate) }
        case .ratingLow: return reviews.sorted { ($0.rating, $1.createdDate) < ($1.rating, $0.createdDate) }
        }
    }
}

// MARK: - 한 앱

private struct ProjectReviewsView: View {
    @EnvironmentObject private var purchases: AppStoreConnectStore
    let project: String

    enum Mode: String, CaseIterable, Identifiable {
        case list = "목록"
        case stats = "통계"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .list
    @State private var filter: ReviewFilter = .all
    @State private var sort: ReviewSort = .newest
    @State private var searchText = ""
    @State private var editing: CustomerReview?
    @State private var deleting: CustomerReview?
    @State private var actionError: String?

    private var feed: ReviewFeed { purchases.reviewFeeds[project] ?? ReviewFeed() }

    private var shown: [CustomerReview] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matched = feed.reviews.filter { review in
            guard filter.matches(review) else { return false }
            guard !query.isEmpty else { return true }
            return [review.title, review.body, review.reviewerNickname, review.response?.responseBody]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return sort.sorted(matched)
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Group {
                switch mode {
                case .list: list
                case .stats: ReviewStatsView(reviews: feed.reviews)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await purchases.loadReviews(bundleID: project)
            await purchases.loadVersion(bundleID: project)
        }
        .sheet(item: $editing) { review in
            ReviewResponseSheet(review: review, project: project)
                .environmentObject(purchases)
        }
        .confirmationDialog("이 리뷰에 단 응답을 지울까요?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible,
                            presenting: deleting) { review in
            Button("응답 지우기", role: .destructive) {
                Task { await delete(review) }
            }
        } message: { _ in
            Text("App Store 에서 바로 내려갑니다. 지운 글은 되살릴 수 없어요.")
        }
        .alert("응답을 지우지 못했습니다",
               isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func delete(_ review: CustomerReview) async {
        do {
            try await purchases.deleteResponse(of: review, in: project)
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: 머리

    private var modeBar: some View {
        HStack(spacing: 10) {
            Picker("보기", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 8)

            if feed.isLoading {
                ProgressView().controlSize(.small)
            } else if let fetched = feed.fetchedAt {
                Text("\(AppFormat.relative(fetched)) 받음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("마지막으로 App Store Connect 에서 리뷰를 받은 때. 그 사이에는 저장해 둔 리뷰를 보여 줍니다.")
            }
            Button {
                Task { await purchases.loadReviews(bundleID: project, force: true) }
            } label: {
                Label("다시 받기", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("리뷰를 App Store Connect 에서 다시 받습니다")
            .disabled(feed.isLoading)
        }
        .hubHeaderBar(verticalPadding: 8)
    }

    // MARK: 목록

    @ViewBuilder
    private var list: some View {
        if feed.reviews.isEmpty {
            if feed.isLoading {
                ProgressView("리뷰를 받는 중…")
                    .font(.body)
            } else if let error = feed.error {
                ScrollView {
                    Card(title: "리뷰를 받지 못했습니다", systemImage: "exclamationmark.triangle") {
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("리뷰는 키 역할이 Admin · App Manager · Customer Support · Developer · Marketing 중 하나면 읽힙니다. 스토어에 아직 안 낸 앱이면 App Store Connect 에서 못 찾아요.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(ReviewLayout.padding)
                }
            } else {
                ContentUnavailableView("리뷰가 없습니다", systemImage: "star.bubble",
                                       description: Text("이 앱에는 아직 App Store 리뷰가 없어요."))
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    summary
                    controls
                    if let error = feed.error {
                        Label("새로 받지 못해 저장해 둔 리뷰를 보여 줍니다 — \(error)", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let shown = self.shown
                    if shown.isEmpty {
                        Text("조건에 맞는 리뷰가 없습니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        Text(shown.count == feed.reviews.count ? "\(shown.count)건" : "\(shown.count)건 표시 / 전체 \(feed.reviews.count)건")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(shown) { review in
                            ReviewCard(review: review,
                                       onRespond: { editing = review },
                                       onDelete: { deleting = review })
                        }
                    }
                }
                .padding(ReviewLayout.padding)
            }
        }
    }

    /// 버전 상태 · 평균 · 답 안 한 수. ReviewManager 의 툴바 숫자들.
    private var summary: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if let version = purchases.versions[project] {
                Tag(text: "v\(version.version) · \(version.stateLabel)", systemImage: "shippingbox",
                    tint: version.tone == .live ? .green : (version.tone == .blocked ? .red : .orange))
            }
            if let average = feed.average {
                Tag(text: String(format: "평균 %.2f", average), systemImage: "star.fill", tint: .yellow)
            }
            Tag(text: "리뷰 \(AppFormat.count(feed.reviews.count))건", systemImage: "text.bubble")
            let answered = feed.reviews.count - feed.unanswered
            Tag(text: "답함 \(answered)/\(feed.reviews.count)", systemImage: "checkmark.bubble",
                tint: feed.unanswered == 0 ? .green : nil)
            let fresh = feed.reviews.filter(\.isNew).count
            if fresh > 0 {
                Tag(text: "새 리뷰 \(fresh)건", systemImage: "sparkles", tint: .red)
            }
        }
    }

    private var controls: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Picker("거르기", selection: $filter) {
                ForEach(ReviewFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .fixedSize()
            Picker("정렬", selection: $sort) {
                ForEach(ReviewSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            TextField("제목 · 본문 · 닉네임 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
        }
        .pickerStyle(.menu)
    }
}

// MARK: - 리뷰 한 건

struct ReviewCard: View {
    let review: CustomerReview
    let onRespond: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let title = review.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .textSelection(.enabled)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(.body)
                    .lineLimit(isExpanded ? nil : 4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if body.count > 180 {
                    Button(isExpanded ? "접기" : "더 보기") {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            TranslateToKoreanView(text: review.fullText)
                .font(.callout)

            if let nickname = review.reviewerNickname, !nickname.isEmpty {
                Text("— \(nickname)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let response = review.response {
                responseBox(response)
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }

    private var header: some View {
        FlowLayout(spacing: 6, lineSpacing: 4) {
            StarRatingView(rating: review.rating)
            Tag(text: review.territoryName, systemImage: "globe", isCompact: true)
            if review.isNew {
                Tag(text: "새 리뷰", systemImage: "circle.fill", tint: .red, isCompact: true)
            } else if review.isWaitingForResponse {
                Tag(text: "답 필요", systemImage: "exclamationmark.bubble", tint: .orange, isCompact: true)
            }
            Text(AppFormat.dateTime(review.createdDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func responseBox(_ response: ReviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("개발자 응답", systemImage: "arrowshape.turn.up.left.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Tag(text: response.stateLabel, tint: response.isPublished ? .green : .orange, isCompact: true)
                Spacer(minLength: 4)
                Text(AppFormat.dateTime(response.lastModifiedDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(response.responseBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                CopyButton(text: response.responseBody, title: "응답 복사")
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            CopyButton(text: review.fullText, title: "리뷰 복사")
                .font(.caption)
            Spacer(minLength: 8)
            if review.response != nil {
                Button(role: .destructive, action: onDelete) {
                    Label("응답 지우기", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                Button(action: onRespond) {
                    Label("응답 고치기", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: onRespond) {
                    Label("답하기", systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

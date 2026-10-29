//
//  MarketingView.swift
//  FeedbackHubViewer
//
//  마케팅 칸 — 만들어 둔 자료(카드뉴스 · 영상 · 글)의 목록. 누르면 그 내용을 본다.
//

import SwiftUI

struct MarketingView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var marketing = MarketingStore.shared

    /// nil == 전체 앱.
    let project: String?

    @State private var adding: MarketingItem?

    var body: some View {
        let items = marketing.items(for: project)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("자료 \(items.count)개")
                        .font(.title2.weight(.bold))
                    Spacer()
                    if let project {
                        Button {
                            adding = MarketingItem(project: project, kind: .cardNews,
                                                   channel: MarketingItem.Kind.cardNews.suggestedChannels[0], title: "")
                        } label: {
                            Label("추가", systemImage: "plus")
                        }
                        .font(.body)
                    }
                }
                if items.isEmpty {
                    Text("아직 자료가 없어요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if project == nil {
                    // 전체 앱은 앱마다 한 카드.
                    ForEach(Dictionary(grouping: items, by: \.project).sorted { $0.key < $1.key }, id: \.key) { app, appItems in
                        Card(title: store.displayName(for: app), systemImage: "megaphone") {
                            rows(appItems)
                        }
                    }
                } else {
                    // 레딧은 서브마다 글이 다르다 — 어디에 무엇을 올릴지 따로 모아 둔다.
                    let reddit = items.filter { $0.subreddit != nil }
                    if !reddit.isEmpty {
                        Card(title: "레딧 · 하루에 한 곳씩", systemImage: "bubble.left.and.bubble.right") {
                            rows(reddit)
                        }
                    }
                    Card(title: "자료", systemImage: "megaphone") {
                        rows(items.filter { $0.subreddit == nil })
                    }
                }
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationDestination(for: MarketingItem.self) { item in
            MarketingDetailView(id: item.id)
        }
        .sheet(item: $adding) { item in
            MarketingItemEditor(item: item) { adding = nil }
                .environmentObject(store)
                .environmentObject(keywords)
        }
        .task(id: Set(items.map(\.project))) {
            await StoreIcons.shared.resolve(items.map(\.project), keywords: keywords)
        }
    }

    private func rows(_ items: [MarketingItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    MarketingRow(item: item)
                }
                .buttonStyle(.plain)
                if item.id != items.last?.id { Divider() }
            }
        }
    }
}

/// 자료 한 줄 — 종류 · 주제 · 채널.
struct MarketingRow: View {
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    let item: MarketingItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIcon(url: icons.url(for: item.project, keywords: keywords),
                    symbol: item.kind.systemImage, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "(주제 없음)" : item.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Label("\(item.channel) \(item.kind.label)", systemImage: item.kind.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.stage == .posted {
                Label("올림", systemImage: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// 지시문에 붙일 것을 가게들에서 모은다.
@MainActor
enum MarketingContextBuilder {
    static func make(project: String, store: FeedbackStore, connect: AppStoreConnectStore,
                     keywords: KeywordStore, news: NewsStore) -> MarketingContext {
        let storeApp = keywords.storeApp(for: project)
        let locales = connect.metadata[project]?.value?.live.locales ?? [:]
        let text = locales["ko"] ?? locales.first { $0.key.hasPrefix("ko") }?.value ?? locales["en-US"] ?? locales.values.first
        let reviews = (connect.reviewFeeds[project]?.reviews ?? [])
            .filter { $0.rating >= 4 && !($0.body ?? "").isEmpty }
            .sorted { $0.createdDate > $1.createdDate }
            .prefix(5)
            .map { review in
                let body = (review.body ?? "").replacingOccurrences(of: "\n", with: " ")
                return "★\(review.rating) " + (body.count > 200 ? String(body.prefix(200)) + "…" : body)
            }
        let ranked = keywords.standings(for: project).filter(\.isRanked)
            .sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
            .prefix(8)
            .map { "\($0.keyword.term) \($0.rank ?? 0)위" }
        let recent = news.items.filter { $0.project == project }
            .sorted { $0.date > $1.date }
            .prefix(6)
            .map { $0.body.isEmpty ? $0.title : "\($0.title) — \($0.body)" }
        let installs = store.usage(for: project).installs
        return MarketingContext(appName: store.displayName(for: project),
                                storeName: storeApp?.name,
                                subtitle: text?.subtitle,
                                promotionalText: text?.promotionalText,
                                storeKeywords: text?.keywords,
                                storeURL: storeApp?.storeURL,
                                rankedKeywords: Array(ranked),
                                goodReviews: Array(reviews),
                                news: Array(recent),
                                installs: installs > 0 ? installs : nil)
    }
}

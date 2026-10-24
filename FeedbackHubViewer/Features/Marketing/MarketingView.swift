//
//  MarketingView.swift
//  FeedbackHubViewer
//
//  마케팅 칸 — 지금 무엇을 해야 하나가 맨 위, 그 아래 올렸는지 묻기, 기획, 진행 중인 활동.
//
//  다른 칸처럼 판정이 먼저다(허브 화면의 원칙). "올렸는지 답할 것 2개 · 이번 주 올릴 것 1개"
//  를 읽고 나면 어디를 누를지 안다. 지난 활동은 접어 둔다.
//

import SwiftUI

struct MarketingView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var design: DesignDocsStore
    @ObservedObject private var marketing = MarketingStore.shared

    /// nil == 전체 앱.
    let project: String?

    @State private var editing: MarketingItem?
    @State private var pastedPlan = ""
    @State private var planProject: String?
    @State private var importMessage: String?

    var body: some View {
        let items = marketing.items(for: project)
        let awaiting = items.filter { $0.needsConfirmation() }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                verdict(items, awaiting: awaiting)
                if !awaiting.isEmpty { confirmCard(awaiting) }
                // 채비(숙성도) · 배포 · 캠페인 — 한 앱이면 세 카드, 전체면 앱마다 한 줄.
                if let project {
                    MarketingReadinessCard(project: project)
                    MarketingDistributionCard(project: project)
                    MarketingCampaignCard(project: project)
                } else {
                    MarketingOverviewCard()
                }
                planCard
                boardCard(items.filter { $0.stage.isOpen && !$0.needsConfirmation() })
                pastCard(items.filter { !$0.stage.isOpen })
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { item in
            MarketingItemEditor(item: item) { editing = nil }
                .environmentObject(store)
                .environmentObject(connect)
                .environmentObject(keywords)
                .environmentObject(news)
        }
        .task(id: design.workspace) {
            await PortfolioStore.shared.load(workspace: design.workspace)
        }
        .task(id: Set(items.map(\.project))) {
            await StoreIcons.shared.resolve(items.map(\.project), keywords: keywords)
        }
        .task(id: project) {
            // 지시문에 스토어 문구 · 리뷰를 붙이려면 받아 둔 게 있어야 한다.
            if let project, connect.isConfigured {
                await connect.loadMetadata(bundleID: project)
                await connect.loadReviews(bundleID: project)
            }
        }
    }

    private var appKeys: [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject }
    }

    // MARK: - 판정

    private func verdict(_ items: [MarketingItem], awaiting: [MarketingItem]) -> some View {
        let open = items.filter { $0.stage.isOpen }
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let thisWeek = open.filter { item in
            guard let at = item.plannedAt else { return false }
            return at > Date() && at <= weekEnd
        }
        let empty = open.filter { !$0.hasMaterial }

        let headline: String
        let detail: String
        let tint: Color
        if !awaiting.isEmpty {
            headline = "올렸는지 답할 것 \(awaiting.count)개"
            detail = "올리기로 한 때가 지났어요. 아래에서 올렸는지 알려 주세요."
            tint = .red
        } else if open.isEmpty {
            headline = "잡힌 마케팅이 없어요"
            detail = "Claude 에게 2주 계획을 맡기거나, 활동을 직접 추가하세요."
            tint = .secondary
        } else if !empty.isEmpty {
            headline = "자료가 빈 활동 \(empty.count)개"
            detail = "누르면 Claude 에게 초안을 맡길 글이 있어요."
            tint = .orange
        } else {
            headline = thisWeek.isEmpty ? "다 준비됐어요" : "이번 주 올릴 것 \(thisWeek.count)개"
            detail = "때가 되면 알림으로 올렸는지 물어볼게요."
            tint = .green
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
            Text("진행 중 \(open.count) · 이번 주 \(thisWeek.count) · 자료 빈 것 \(empty.count) · 올라감 \(items.filter { $0.stage == .posted }.count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 올렸나요?

    private func confirmCard(_ awaiting: [MarketingItem]) -> some View {
        Card(title: "올렸나요?", systemImage: "questionmark.bubble") {
            VStack(spacing: 0) {
                ForEach(awaiting) { item in
                    ConfirmRow(item: item, showsApp: project == nil) { editing = item }
                    if item.id != awaiting.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: - 기획

    private var planCard: some View {
        Card(title: "기획", systemImage: "lightbulb") {
            let target = project ?? planProject
            if project == nil {
                Picker("앱", selection: $planProject) {
                    Text("앱 고르기").tag(String?.none)
                    ForEach(appKeys, id: \.self) { Text(store.displayName(for: $0)).tag(Optional($0)) }
                }
                .font(.body)
            }
            if let target {
                let context = MarketingContextBuilder.make(project: target, store: store, connect: connect,
                                                           keywords: keywords, news: news)
                HStack(spacing: 12) {
                    CopyButton(text: MarketingPrompt.plan(context), title: "Claude 에게 2주 계획 맡길 글 복사")
                        .font(.body)
                    Spacer()
                    Button {
                        editing = MarketingItem(project: target, kind: .cardNews,
                                                channel: MarketingItem.Kind.cardNews.suggestedChannels[0], title: "")
                    } label: {
                        Label("직접 추가", systemImage: "plus")
                    }
                    .font(.body)
                }
                Text("스토어 문구 · 검색 순위 · 좋은 리뷰 · 최근 소식을 붙여 둡니다. Claude 의 답(JSON)을 아래에 붙여 넣으면 활동으로 들어와요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GrowingTextField("Claude 의 답을 여기에 붙여 넣기", text: $pastedPlan, minLines: 3, monospaced: true)
                HStack {
                    if let importMessage {
                        Text(importMessage).font(.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("계획 들이기") {
                        if let planned = MarketingImport.plan(pastedPlan, project: target) {
                            marketing.add(planned)
                            importMessage = "활동 \(planned.count)개를 들였어요."
                            pastedPlan = ""
                        } else {
                            importMessage = "JSON 배열을 찾지 못했어요. Claude 의 답을 그대로 붙여 넣어 주세요."
                        }
                    }
                    .disabled(pastedPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("어느 앱의 마케팅을 짤지 고르세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 진행 중

    @ViewBuilder
    private func boardCard(_ items: [MarketingItem]) -> some View {
        if !items.isEmpty {
            Card(title: "진행 중", systemImage: "list.bullet.rectangle") {
                ForEach([MarketingItem.Stage.planned, .preparing, .ready]) { stage in
                    let inStage = items.filter { $0.stage == stage }
                    if !inStage.isEmpty {
                        Text("\(stage.label) \(inStage.count)")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(inStage) { item in
                            Button { editing = item } label: {
                                MarketingRow(item: item, showsApp: project == nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pastCard(_ items: [MarketingItem]) -> some View {
        if !items.isEmpty {
            Card(title: "지난 활동", systemImage: "clock.arrow.circlepath") {
                DisclosureGroup("올라감 \(items.filter { $0.stage == .posted }.count) · 안 올림 \(items.filter { $0.stage == .skipped }.count)") {
                    ForEach(items.reversed()) { item in
                        Button { editing = item } label: {
                            MarketingRow(item: item, showsApp: project == nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.body)
            }
        }
    }
}

/// 활동 한 줄 — 종류 · 주제 · 채널과 날짜 · 지금 할 일.
struct MarketingRow: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    let item: MarketingItem
    var showsApp = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 앱 아이콘이 먼저 — 여러 앱이 섞인 목록은 이름보다 아이콘으로 빨리 갈린다.
            // 종류(카드뉴스 · 영상 · 글)는 아이콘 귀퉁이에 작게.
            AppIcon(url: icons.url(for: item.project, keywords: keywords),
                    symbol: item.kind.systemImage, size: 36)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 5, y: 5)
                        .accessibilityHidden(true)
                }
                .padding(.top, 2)
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "(주제 없음)" : item.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(([showsApp ? store.displayName(for: item.project) : nil,
                        "\(item.channel) \(item.kind.label)",
                        item.plannedAt.map(AppFormat.dateTime)]).compactMap { $0 }.joined(separator: " · "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(item.nextStep())
                    .font(.body)
                    .foregroundStyle(item.needsConfirmation() ? .red : item.hasMaterial ? Color.secondary : .orange)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// "올렸나요?" 한 줄 — 올렸어요(주소는 붙여도 되고 안 붙여도 된다) · 아직 · 안 올림.
private struct ConfirmRow: View {
    @EnvironmentObject private var store: FeedbackStore
    @ObservedObject private var marketing = MarketingStore.shared
    let item: MarketingItem
    let showsApp: Bool
    let open: () -> Void

    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                MarketingRow(item: item, showsApp: showsApp)
            }
            .buttonStyle(.plain)
            TextField("올린 글 주소(있으면)", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
            HStack(spacing: 10) {
                Button("올렸어요") { marketing.markPosted(item.id, url: url) }
                    .buttonStyle(.borderedProminent)
                Button("아직 — 내일 다시") { marketing.snooze(item.id) }
                    .buttonStyle(.bordered)
                Button("안 올릴래요") { marketing.skip(item.id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .font(.body)
        }
        .padding(.vertical, 8)
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

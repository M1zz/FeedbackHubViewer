//
//  LeadsView.swift
//  FeedbackHubViewer
//
//  질문 찾기 칸 — 레딧에서 "이런 앱 없나요?" 를 묻는 글. 답할 만한 질문이 맨 위, 글마다 원문 ·
//  답글 초안 맡길 글 · 답했어요 · 상관없음. 답은 사람이 직접 단다(`RedditLead` 머리말).
//

import SwiftUI

struct LeadsView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var leads = LeadStore.shared
    @ObservedObject private var icons = StoreIcons.shared
    /// nil == 전체 앱.
    let project: String?

    @State private var editing = false
    /// 이 화면을 열 때 안 본 질문 — 뱃지가 센 것. 열자마자 본 것으로 넘어가도 "새" 가 남는다.
    @State private var fresh: Set<String> = []

    private var appKeys: [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject && leads.queries(for: $0) != nil }
    }

    var body: some View {
        let open = leads.open(for: project)
        let decided = leads.decided(for: project)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                verdict(open: open)
                if let problem = leads.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RedditKeyCard()
                if let project { settings(project) }
                ForEach(open) { lead in
                    LeadCard(lead: lead, showsApp: project == nil, isFresh: fresh.contains(lead.id))
                }
                if !decided.isEmpty {
                    Card(title: "처리한 질문", systemImage: "checkmark.circle") {
                        DisclosureGroup("답함 \(decided.filter { $0.status == .replied }.count) · 상관없음 \(decided.filter { $0.status == .dismissed }.count)") {
                            ForEach(decided) { lead in
                                HStack {
                                    Image(systemName: lead.status == .replied ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundStyle(lead.status == .replied ? .green : .secondary)
                                    Link(lead.title, destination: lead.url).font(.body).lineLimit(1)
                                }
                            }
                        }
                        .font(.body)
                    }
                }
                Text("허브는 질문을 찾아 모으기만 해요. 자동으로 답글을 달면 레딧 정책(스팸)에 걸려 계정과 앱 링크가 막힐 수 있어서, 답은 직접 달아요.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: project) {
            fresh = leads.unseenIDs(for: project)
            leads.markViewed(project: project)
            await leads.searchIfStale(project.map { [$0] } ?? appKeys)
            fresh.formUnion(leads.unseenIDs(for: project))
            leads.markViewed(project: project)
        }
        .sheet(isPresented: $editing) {
            if let project {
                LeadQueriesSheet(project: project, initial: leads.queries(for: project)) { editing = false }
                    .environmentObject(store)
            }
        }
    }

    private func verdict(open: [RedditLead]) -> some View {
        let running = !leads.searching.isEmpty
        let last = project.flatMap { leads.searchedAt[$0] }
        return VStack(alignment: .leading, spacing: 4) {
            let questions = open.filter { $0.isQuestion == true }.count
            Text(open.isEmpty ? "답할 만한 글이 없어요" : "질문 \(questions)개 · 관련 글 \(open.count - questions)개")
                .font(.title2.weight(.bold))
                .foregroundStyle(open.isEmpty ? Color.secondary : .red)
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.small)
                    Text("레딧에서 찾는 중… \(leads.searching.map { store.displayName(for: $0) }.joined(separator: ", "))")
                } else if let last {
                    Text("최근 6개월 · \(AppFormat.relative(last)) 찾음")
                } else {
                    Text(open.isEmpty ? "최근 6개월 레딧 글 중 앱 · 방법을 묻는 질문만 모아요" : "최근 6개월")
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func settings(_ project: String) -> some View {
        if let queries = leads.queries(for: project) {
            DisclosureGroup("검색어 \(queries.queries.count + queries.queriesKo.count)개 · 서브레딧 \(queries.subreddits.count)개") {
                VStack(alignment: .leading, spacing: 6) {
                    Text((queries.queries + queries.queriesKo).joined(separator: " · "))
                        .font(.body)
                    Text(queries.subreddits.map { "r/\($0)" }.joined(separator: " · "))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("고치기") { editing = true }
                        Button("지금 찾기") { Task { await leads.search(project) } }
                            .disabled(leads.searching.contains(project))
                    }
                    .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
        } else {
            Text("이 앱의 검색어가 없어요.").font(.body).foregroundStyle(.secondary)
        }
    }
}

/// 질문 하나.
private struct LeadCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var leads = LeadStore.shared
    let lead: RedditLead
    let showsApp: Bool
    var isFresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFresh {
                Tag(text: "새 질문", systemImage: "circle.fill", tint: .red, font: .body)
            }
            Text([lead.isQuestion == true ? "질문" : "관련 글", showsApp ? store.displayName(for: lead.project) : nil, lead.subreddit,
                  lead.date.map(AppFormat.relative), "검색어: \(lead.query)"]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(.secondary)
            Text(lead.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !lead.snippet.isEmpty {
                Text(lead.snippet)
                    .font(.body)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Link("원문 열기", destination: lead.url)
                let context = MarketingContextBuilder.make(project: lead.project, store: store, connect: connect,
                                                           keywords: keywords, news: news)
                CopyButton(text: MarketingPrompt.redditReply(lead, context: context), title: "답글 초안 맡길 글 복사")
                Spacer()
                Button("답했어요") { leads.decide(lead.id, .replied) }
                    .buttonStyle(.borderedProminent)
                Button("상관없음") { leads.decide(lead.id, .dismissed) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .font(.body)
        }
        .padding(Platform.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// 검색어 · 서브레딧 고치기. 쉼표로 나눈다.
private struct LeadQueriesSheet: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String
    let close: () -> Void
    @State private var english: String
    @State private var korean: String
    @State private var subreddits: String

    init(project: String, initial: LeadQueries?, close: @escaping () -> Void) {
        self.project = project
        self.close = close
        _english = State(initialValue: (initial?.queries ?? []).joined(separator: ", "))
        _korean = State(initialValue: (initial?.queriesKo ?? []).joined(separator: ", "))
        _subreddits = State(initialValue: (initial?.subreddits ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("영어 검색어 (서브레딧 안에서)") { TextField("text expander iphone, …", text: $english, axis: .vertical) }
                Section("한국어 검색어 (레딧 전체)") { TextField("단축키 키보드 앱, …", text: $korean, axis: .vertical) }
                Section("서브레딧 (r/ 없이)") { TextField("iphone, productivity, …", text: $subreddits, axis: .vertical) }
            }
            .font(.body)
            .navigationTitle("\(store.displayName(for: project)) · 질문 찾기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let split = { (text: String) in
                            text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        }
                        LeadStore.shared.setQueries(LeadQueries(queries: split(english), queriesKo: split(korean),
                                                                subreddits: split(subreddits)), for: project)
                        close()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 380)
        #endif
    }
}

/// 레딧 API 키 — 없으면 만드는 법과 넣는 칸, 있으면 한 줄.
private struct RedditKeyCard: View {
    @State private var isConfigured = RedditAPI.isConfigured
    @State private var clientID = ""
    @State private var secret = ""
    @State private var showsForm = false

    var body: some View {
        if isConfigured && !showsForm {
            HStack {
                Label("레딧 API 로 찾아요", systemImage: "checkmark.seal")
                    .font(.body)
                    .foregroundStyle(.green)
                Spacer()
                Button("키 바꾸기") { showsForm = true }
                    .buttonStyle(.borderless)
                    .font(.body)
            }
        } else {
            Card(title: "레딧 API 키 (무료 · 한 번만)", systemImage: "key") {
                Text("키 없이 찾으면 레딧이 자주 막고 결과도 엉뚱해요. 개인용 앱을 하나 만들면 정확하게, 막히지 않고 찾아요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. reddit.com/prefs/apps 에서 \"create another app…\"")
                    Text("2. 종류는 script, 이름은 아무거나, redirect uri 는 http://localhost")
                    Text("3. 만든 앱 이름 아래 짧은 글자(client id)와 secret 을 아래에")
                }
                .font(.body)
                Link("reddit.com/prefs/apps 열기", destination: URL(string: "https://www.reddit.com/prefs/apps")!)
                    .font(.body)
                TextField("client id", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                SecureField("secret", text: $secret)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                HStack {
                    Button("저장") {
                        RedditKeychain.save(RedditCredentials(clientID: clientID.trimmingCharacters(in: .whitespaces),
                                                              secret: secret.trimmingCharacters(in: .whitespaces)))
                        isConfigured = RedditAPI.isConfigured
                        showsForm = false
                        clientID = ""
                        secret = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientID.isEmpty || secret.isEmpty)
                    if isConfigured {
                        Button("취소") { showsForm = false }
                        Spacer()
                        Button("키 지우기", role: .destructive) {
                            RedditKeychain.delete()
                            isConfigured = false
                            showsForm = false
                        }
                    }
                }
                .font(.body)
            }
        }
    }
}

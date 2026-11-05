//
//  MarketingDetailView.swift
//  FeedbackHubViewer
//
//  자료 하나의 내용 — 카드뉴스 장들, 영상 대본, 글 · 캡션. 복사하거나 그림으로 내보낸다.
//

import SwiftUI

struct MarketingDetailView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var marketing = MarketingStore.shared

    /// 고친 뒤에도 최신 내용을 보이도록 id 로 가게에서 읽는다.
    let id: UUID

    @State private var english = false
    @State private var editing: MarketingItem?
    @State private var icon: CGImage?
    @State private var exported: [URL] = []
    @State private var isExporting = false

    var body: some View {
        if let item = marketing.item(id) {
            content(item)
        } else {
            Text("지워진 자료예요.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func content(_ item: MarketingItem) -> some View {
        let appName = store.displayName(for: item.project)
        // 한쪽 언어로만 쓴 글(레딧은 영어뿐)은 고를 것 없이 그 언어로.
        let bilingual = item.kind != .post || (!item.body.isEmpty && !item.bodyEn.isEmpty)
        let showsEnglish = bilingual ? english : item.body.isEmpty
        let text = showsEnglish ? item.bodyEn : item.body
        let script = showsEnglish ? item.scriptEn : item.script

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "(주제 없음)" : item.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(appName) · \(item.channel) \(item.kind.label)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let subreddit = item.subreddit {
                    reddit(item, subreddit: subreddit)
                }

                if bilingual {
                    Picker("언어", selection: $english) {
                        Text("한국어").tag(false)
                        Text("English").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: english) { exported = [] }
                }

                if item.kind == .cardNews, !item.slides.isEmpty {
                    slides(item, appName: appName)
                }
                if item.kind == .video {
                    textCard("대본", systemImage: "video", text: script)
                }
                textCard(item.subreddit != nil ? "본문" : item.kind == .post ? "글" : "캡션",
                         systemImage: "text.alignleft", text: text)
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(appName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("편집") { editing = item }
            }
        }
        .sheet(item: $editing) { item in
            MarketingItemEditor(item: item) {
                editing = nil
                exported = []
            }
            .environmentObject(store)
            .environmentObject(keywords)
        }
        .task(id: item.project) {
            icon = await StoreIcons.shared.image(for: item.project, keywords: keywords)
        }
    }

    // MARK: - 레딧

    /// 어디에 · 어떤 제목으로 · 무엇을 지킬지. 복사하고 글쓰기 화면을 열어 붙여 넣으면 된다.
    private func reddit(_ item: MarketingItem, subreddit: String) -> some View {
        Card(title: "r/\(subreddit)", systemImage: "bubble.left.and.bubble.right") {
            if !item.angle.isEmpty {
                Text(item.angle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("제목").font(.headline)
            Text(item.title)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                CopyButton(text: item.title, title: "제목 복사")
                if let url = item.redditSubmitURL {
                    Link(destination: url) { Label("글쓰기 열기", systemImage: "arrow.up.right.square") }
                }
                Spacer()
                Button {
                    var next = item
                    let posted = item.stage == .posted
                    next.stage = posted ? .ready : .posted
                    next.postedAt = posted ? nil : Date()
                    marketing.save(next)
                } label: {
                    Label(item.stage == .posted ? "올림" : "올렸어요",
                          systemImage: item.stage == .posted ? "checkmark.circle.fill" : "circle")
                }
                .foregroundStyle(item.stage == .posted ? .green : .accentColor)
            }
            .font(.body)
        }
    }

    // MARK: - 카드뉴스

    private func slides(_ item: MarketingItem, appName: String) -> some View {
        let scale = 0.28
        return Card(title: "카드뉴스 \(item.slides.count)장", systemImage: "square.stack") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(item.slides.enumerated()), id: \.element.id) { index, slide in
                        CardNewsSlideView(slide: slide.localized(english: english), index: index, total: item.slides.count,
                                          appName: appName, theme: CardNewsTheme.of(item), icon: icon, english: english)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: CardNewsSlideView.size.width * scale,
                                   height: CardNewsSlideView.size.height * scale, alignment: .topLeading)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack {
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                } else if exported.isEmpty {
                    Button {
                        Task {
                            isExporting = true
                            exported = await CardNewsExport.render(item, appName: appName, icon: icon, english: english)
                            isExporting = false
                        }
                    } label: { Label("그림 만들기", systemImage: "photo.on.rectangle") }
                } else {
                    ShareLink(items: exported) { Label("\(exported.count)장 공유", systemImage: "square.and.arrow.up") }
                }
            }
            .font(.body)
        }
    }

    // MARK: - 글

    @ViewBuilder
    private func textCard(_ title: String, systemImage: String, text: String) -> some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Card(title: title, systemImage: systemImage) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    CopyButton(text: text, title: "\(title) 복사").font(.body)
                }
            }
        }
    }
}

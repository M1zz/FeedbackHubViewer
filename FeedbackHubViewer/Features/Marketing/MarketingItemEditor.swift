//
//  MarketingItemEditor.swift
//  FeedbackHubViewer
//
//  자료 하나를 고친다 — 무엇을 · 어디에, 그리고 내용(카드뉴스 장들 · 대본 · 글).
//
//  고친 것은 "저장" 을 눌러야 남는다. 대본을 고치다 시트를 실수로 닫아도 반쯤 고친 글이
//  다른 기기로 넘어가지 않게.
//

import SwiftUI

struct MarketingItemEditor: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var marketing = MarketingStore.shared

    @State private var draft: MarketingItem
    let close: () -> Void

    @State private var confirmsDelete = false
    /// 미리보기 · 그림에 넣을 앱 아이콘.
    @State private var icon: CGImage?
    /// 고치고 보는 언어. 마케팅 자료는 한국어 · 영어 두 판을 든다.
    @State private var english = false

    init(item: MarketingItem, close: @escaping () -> Void) {
        _draft = State(initialValue: item)
        self.close = close
    }

    private var isNew: Bool { marketing.item(draft.id) == nil }
    private var appName: String { store.displayName(for: draft.project) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    planSection
                    languagePicker
                    switch draft.kind {
                    case .cardNews: cardNewsSection
                    case .video: videoSection
                    case .post: EmptyView()
                    }
                    captionSection
                    deleteButton
                }
                .padding(Platform.cardPadding)
            }
            .navigationTitle(isNew ? "새 자료 · \(appName)" : appName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        marketing.save(draft)
                        close()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 640, idealHeight: 820)
        #endif
        .task(id: draft.project) {
            icon = await StoreIcons.shared.image(for: draft.project, keywords: keywords)
        }
    }

    // MARK: - 무엇을 · 어디에

    private var planSection: some View {
        Card(title: "자료", systemImage: "megaphone") {
            Picker("종류", selection: $draft.kind) {
                ForEach(MarketingItem.Kind.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .font(.body)

            TextField("무엇을 알리나 — 한 줄", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.body)

            HStack {
                TextField("어디에 올리나", text: $draft.channel)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                Menu("고르기") {
                    ForEach(draft.kind.suggestedChannels, id: \.self) { channel in
                        Button(channel) { draft.channel = channel }
                    }
                }
                .fixedSize()
                .font(.body)
            }
        }
    }

    // MARK: - 언어

    private var languagePicker: some View {
        Picker("언어", selection: $english) {
            Text("한국어").tag(false)
            Text("English").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var scriptBinding: Binding<String> { english ? $draft.scriptEn : $draft.script }
    private var bodyBinding: Binding<String> { english ? $draft.bodyEn : $draft.body }

    // MARK: - 카드뉴스

    private var cardNewsSection: some View {
        Card(title: "카드뉴스 \(draft.slides.count)장", systemImage: "square.stack") {
            Picker("색", selection: Binding(get: { draft.theme ?? 0 }, set: { draft.theme = $0 })) {
                ForEach(CardNewsTheme.all) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .font(.body)

            if !draft.slides.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(draft.slides.enumerated()), id: \.element.id) { index, slide in
                            CardNewsSlideView(slide: slide.localized(english: english), index: index, total: draft.slides.count,
                                              appName: appName, theme: CardNewsTheme.of(draft), icon: icon, english: english)
                                .scaleEffect(0.2, anchor: .topLeading)
                                .frame(width: CardNewsSlideView.size.width * 0.2,
                                       height: CardNewsSlideView.size.height * 0.2, alignment: .topLeading)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            ForEach($draft.slides) { $slide in
                let index = draft.slides.firstIndex { $0.id == slide.id } ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(index + 1)장").font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            draft.slides.removeAll { $0.id == slide.id }
                        } label: { Label("빼기", systemImage: "minus.circle") }
                        .buttonStyle(.borderless)
                        .font(.body)
                    }
                    TextField(english ? "Headline" : "큰 글씨", text: english ? $slide.headlineEn : $slide.headline)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                    GrowingTextField(english ? "Body" : "작은 글씨", text: english ? $slide.textEn : $slide.text, minLines: 2)
                }
            }

            Button {
                draft.slides.append(.init(headline: "", text: ""))
            } label: { Label("장 더하기", systemImage: "plus") }
            .font(.body)
        }
    }

    // MARK: - 영상

    private var videoSection: some View {
        Card(title: "영상 대본", systemImage: "video") {
            Text("장면마다 [시간] 화면 / 자막 / 내레이션. 화면 녹화로 찍을 수 있게.")
                .font(.body)
                .foregroundStyle(.secondary)
            GrowingTextField(english ? "[0-2s] Screen: … / Caption: … / VO: …" : "[0-2초] 화면: … / 자막: … / 내레이션: …",
                             text: scriptBinding, minLines: 8)
            HStack {
                Spacer()
                CopyButton(text: scriptBinding.wrappedValue, title: english ? "영어 대본 복사" : "대본 복사").font(.body)
            }
        }
    }

    // MARK: - 글 · 캡션

    private var captionSection: some View {
        Card(title: draft.kind == .post ? "글" : "캡션", systemImage: "text.alignleft") {
            GrowingTextField(draft.kind == .post ? (english ? "Post" : "본문") : (english ? "Caption · hashtags" : "캡션 · 해시태그"),
                             text: bodyBinding,
                             minLines: draft.kind == .post ? 10 : 4)
            HStack {
                Text("\(bodyBinding.wrappedValue.count)자")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: bodyBinding.wrappedValue,
                           title: (english ? "영어 " : "") + (draft.kind == .post ? "글 복사" : "캡션 복사")).font(.body)
            }
        }
    }

    // MARK: - 지우기

    @ViewBuilder
    private var deleteButton: some View {
        if !isNew {
            Button("이 자료 지우기", role: .destructive) { confirmsDelete = true }
                .buttonStyle(.borderless)
                .font(.body)
                .confirmationDialog("이 자료를 지울까요?", isPresented: $confirmsDelete) {
                    Button("지우기", role: .destructive) {
                        marketing.delete(draft.id)
                        close()
                    }
                }
        }
    }
}

/// 글이 늘면 같이 늘어나는 여러 줄 입력칸.
///
/// `TextEditor` 는 그 자체가 스크롤 뷰라, 바깥 `ScrollView` 안에 두면 마우스가 그 위에 있을 때
/// 휠을 가로챈다 — 화면이 멈춘 것처럼 안 내려갔다. 이 칸은 제 스크롤이 없고 글만큼 키가
/// 자라서, 휠은 늘 바깥 화면이 받는다.
struct GrowingTextField: View {
    let placeholder: String
    @Binding var text: String
    var minLines = 3
    var monospaced = false

    init(_ placeholder: String, text: Binding<String>, minLines: Int = 3, monospaced: Bool = false) {
        self.placeholder = placeholder
        _text = text
        self.minLines = minLines
        self.monospaced = monospaced
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(minLines...)
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .body.monospaced() : .body)
    }
}

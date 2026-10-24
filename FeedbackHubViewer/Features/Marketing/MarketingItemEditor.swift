//
//  MarketingItemEditor.swift
//  FeedbackHubViewer
//
//  활동 하나를 기획부터 올린 뒤까지. 위에서 아래로 일의 순서다 — 무엇을 · 어디에 · 언제,
//  자료(Claude 에게 맡기고 답을 붙여 넣거나 직접), 그리고 올렸는지.
//
//  고친 것은 "저장" 을 눌러야 남는다. 대본을 고치다 시트를 실수로 닫아도 반쯤 고친 글이
//  다른 기기로 넘어가지 않게.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MarketingItemEditor: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var marketing = MarketingStore.shared

    @State private var draft: MarketingItem
    let close: () -> Void

    @State private var pastedMaterial = ""
    @State private var materialMessage: String?
    @State private var exported: [URL] = []
    @State private var isExporting = false
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
                    materialSection
                    languagePicker
                    switch draft.kind {
                    case .cardNews: cardNewsSection
                    case .video: videoSection
                    case .post: EmptyView()
                    }
                    captionSection
                    campaignSection
                    postedSection
                }
                .padding(Platform.cardPadding)
            }
            .navigationTitle(isNew ? "새 마케팅 · \(appName)" : appName)
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

    // MARK: - 기획

    private var planSection: some View {
        Card(title: "기획", systemImage: "lightbulb") {
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

            Text("누구에게 · 왜 지금 · 무엇을 느끼게")
                .font(.body)
                .foregroundStyle(.secondary)
            GrowingTextField("예: 복사 붙여넣기를 하루에 수십 번 하는 직장인에게, 이 앱이면 3초로 끝난다는 걸", text: $draft.angle, minLines: 2)

            Toggle("올릴 때 정하기", isOn: Binding(
                get: { draft.plannedAt != nil },
                set: { on in
                    draft.plannedAt = on
                        ? Calendar.current.date(bySettingHour: 10, minute: 0, second: 0,
                                                of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                        : nil
                }))
                .font(.body)
            if let planned = draft.plannedAt {
                DatePicker("올릴 때", selection: Binding(get: { planned }, set: { draft.plannedAt = $0; draft.snoozedUntil = nil }))
                    .font(.body)
                Text("이때 알림으로 올렸는지 물어볼게요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Picker("단계", selection: $draft.stage) {
                ForEach(MarketingItem.Stage.allCases) { Text($0.label).tag($0) }
            }
            .font(.body)
        }
    }

    // MARK: - 자료

    private var materialSection: some View {
        Card(title: "자료 · Claude 에게 맡기기", systemImage: "wand.and.stars") {
            let context = MarketingContextBuilder.make(project: draft.project, store: store, connect: connect,
                                                       keywords: keywords, news: news)
            CopyButton(text: MarketingPrompt.material(draft, context: context),
                       title: "\(draft.kind.label) 초안 맡길 글 복사")
                .font(.body)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Claude 에 붙여 넣고, 받은 답을 그대로 아래에 붙여 넣으면 \(draft.kind == .cardNews ? "장들과 캡션이" : draft.kind == .video ? "대본과 캡션이" : "본문이") 채워져요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GrowingTextField("Claude 의 답을 여기에 붙여 넣기", text: $pastedMaterial, minLines: 3, monospaced: true)
            HStack {
                if let materialMessage {
                    Text(materialMessage).font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                Button("답 들이기") {
                    if MarketingImport.material(pastedMaterial, into: &draft) {
                        pastedMaterial = ""
                        exported = []
                        materialMessage = "채웠어요. 다듬고 저장하세요."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - 언어

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("언어", selection: $english) {
                Text("한국어").tag(false)
                Text("English").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: english) { exported = [] }
            if draft.lacksEnglish {
                Label("영어판이 비어 있어요 — 위의 \"초안 맡길 글\" 은 두 판을 함께 받아요", systemImage: "globe")
                    .font(.body)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var scriptBinding: Binding<String> { english ? $draft.scriptEn : $draft.script }
    private var bodyBinding: Binding<String> { english ? $draft.bodyEn : $draft.body }

    // MARK: - 카드뉴스

    private var cardNewsSection: some View {
        Card(title: "카드뉴스 \(draft.slides.count)장", systemImage: "square.stack") {
            Picker("색", selection: Binding(get: { draft.theme ?? 0 }, set: { draft.theme = $0; exported = [] })) {
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
                            exported = []
                        } label: { Label("빼기", systemImage: "minus.circle") }
                        .buttonStyle(.borderless)
                        .font(.body)
                    }
                    TextField(english ? "Headline" : "큰 글씨", text: english ? $slide.headlineEn : $slide.headline)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                    GrowingTextField(english ? "Body" : "작은 글씨", text: english ? $slide.textEn : $slide.text, minLines: 2)
                }
                .onChange(of: slide) { exported = [] }
            }

            HStack(spacing: 12) {
                Button {
                    draft.slides.append(.init(headline: "", text: ""))
                } label: { Label("장 더하기", systemImage: "plus") }
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                } else if exported.isEmpty {
                    Button {
                        Task {
                            isExporting = true
                            exported = await CardNewsExport.render(draft, appName: appName, icon: icon, english: english)
                            isExporting = false
                        }
                    } label: { Label("그림 만들기", systemImage: "photo.on.rectangle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.slides.isEmpty)
                } else {
                    ShareLink(items: exported) { Label("\(exported.count)장 공유", systemImage: "square.and.arrow.up") }
                    #if os(macOS)
                    Button { saveToFolder() } label: { Label("폴더에 저장", systemImage: "folder") }
                    #endif
                }
            }
            .font(.body)
        }
    }

    #if os(macOS)
    /// 고른 폴더에 "앱이름-주제" 폴더를 만들어 장들을 넣고 Finder 에서 보여 준다.
    private func saveToFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "여기에 저장"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let name = "\(appName)-\(draft.title)".replacingOccurrences(of: "/", with: "-").prefix(60)
        let folder = base.appendingPathComponent(String(name), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in exported {
            let target = folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
    #endif

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
            if draft.hasMaterial, draft.stage == .preparing || draft.stage == .planned {
                Button("자료 완성으로") { draft.stage = .ready }
                    .buttonStyle(.bordered)
                    .font(.body)
            }
        }
    }

    // MARK: - 캠페인

    private var campaignSection: some View {
        Card(title: "캠페인 링크", systemImage: "scope") {
            if marketing.providerToken.isEmpty {
                ProviderTokenField()
            } else if let trackId = keywords.trackId(for: draft.project) {
                let link = MarketingCampaign.link(trackId: trackId, providerToken: marketing.providerToken,
                                                  campaignToken: draft.campaignToken)
                Text("이 링크로 들어온 다운로드는 마케팅 칸의 \"캠페인 추적\" 에 \(draft.campaignToken) 로 잡혀요.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(link)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    CopyButton(text: link, title: "링크 복사").font(.body)
                    Spacer()
                    let replaced = MarketingCampaign.replacingStoreLinks(in: draft.body, trackId: trackId, with: link)
                    let replacedEn = MarketingCampaign.replacingStoreLinks(in: draft.bodyEn, trackId: trackId, with: link)
                    Button("글 속 스토어 링크를 이걸로 바꾸기(두 판 모두)") {
                        draft.body = replaced
                        draft.bodyEn = replacedEn
                    }
                    .font(.body)
                    .disabled(replaced == draft.body && replacedEn == draft.bodyEn)
                }
            } else {
                Text("이 앱이 App Store 와 이어지지 않아 캠페인 링크를 만들 수 없어요.")
                    .font(.body).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 올렸나

    private var postedSection: some View {
        Card(title: "올렸나요?", systemImage: "checkmark.seal") {
            TextField("올린 글 주소", text: $draft.postURL)
                .textFieldStyle(.roundedBorder)
                .font(.body)
            HStack(spacing: 10) {
                if draft.stage == .posted {
                    Label("올라감" + (draft.postedAt.map { " · \(AppFormat.dateTime($0))" } ?? ""),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let url = URL(string: draft.postURL), !draft.postURL.isEmpty {
                        Link("열기", destination: url)
                    }
                } else {
                    Button("올렸어요") {
                        draft.stage = .posted
                        draft.postedAt = Date()
                        marketing.save(draft)
                        close()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Spacer()
                if !isNew {
                    Button("지우기", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(.borderless)
                }
            }
            .font(.body)
            .confirmationDialog("이 활동을 지울까요?", isPresented: $confirmsDelete) {
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

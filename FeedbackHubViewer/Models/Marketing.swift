//
//  Marketing.swift
//  FeedbackHubViewer
//
//  마케팅 활동 하나 — 기획하고, 자료(카드뉴스 · 영상 · 글)를 준비하고, 올리고, 올렸는지
//  확인받는 데까지.
//
//  허브가 지금까지 보여 준 것은 전부 "일어난 일" 이었다. 마케팅은 내가 **할 일** 이라 결이
//  다르다. 그래서 한 활동이 거치는 단계(`Stage`)를 분명히 두고, 날짜가 지났는데 올렸다는
//  말이 없으면 앱이 먼저 묻는다(`needsConfirmation`). 묻고 답을 받아야 "올라갔다" 가 된다 —
//  날짜가 지났다고 저절로 올라간 것으로 치지 않는다.
//
//  자료의 초안은 Claude 에게 맡긴다. 이 앱이 아는 것(스토어 문구 · 키워드 순위 · 좋은 리뷰 ·
//  소식)을 붙여 지시문을 복사하고, Claude 의 답(JSON)을 붙여 넣으면 칸이 채워진다
//  (`MarketingPrompt`, `MarketingImport`). 키워드 칸을 다시 짤 때와 같은 길이다.
//

import Foundation

struct MarketingItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var project: String
    var kind: Kind
    /// 어디에 올리나 — 인스타그램, 유튜브 쇼츠, 스레드, 레딧 …
    var channel: String
    /// 무엇을 알리나 — 한 줄.
    var title: String
    /// 기획: 누구에게, 왜 지금, 무엇을 느끼게.
    var angle = ""
    /// 올리기로 한 때.
    var plannedAt: Date?
    var stage: Stage = .planned
    /// 카드뉴스의 장들.
    var slides: [Slide] = []
    /// 카드뉴스 색 묶음(`CardNewsTheme.all` 의 자리). nil 이면 첫 번째.
    var theme: Int?
    /// 영상 대본 · 장면.
    var script = ""
    /// 영어판 영상 대본. 마케팅은 늘 영어판이 있어야 한다(해외 채널 · X).
    var scriptEn = ""
    /// 글 본문, 또는 카드뉴스 · 영상에 붙일 캡션.
    var body = ""
    /// 영어판 글 · 캡션.
    var bodyEn = ""
    /// 올린 글의 주소.
    var postURL = ""
    var postedAt: Date?
    /// "아직이에요" 를 누르면 이때까지 다시 묻지 않는다.
    var snoozedUntil: Date?
    /// 지운 것도 시각과 함께 남긴다 — 다른 기기에 지웠다는 사실을 전하려고(`ReviewStateSync` 와 같은 까닭).
    var isDeleted = false
    var createdAt = Date()
    var updatedAt = Date()

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case cardNews, video, post
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cardNews: "카드뉴스"
            case .video: "영상"
            case .post: "글"
            }
        }
        var systemImage: String {
            switch self {
            case .cardNews: "square.stack"
            case .video: "video"
            case .post: "text.alignleft"
            }
        }
        /// 이 종류에 흔히 맞는 곳.
        var suggestedChannels: [String] {
            switch self {
            case .cardNews: ["인스타그램", "스레드", "링크드인", "네이버 블로그"]
            case .video: ["유튜브 쇼츠", "인스타그램 릴스", "틱톡"]
            case .post: ["스레드", "X", "레딧", "네이버 블로그", "브런치", "디스콰이엇", "긱뉴스"]
            }
        }
    }

    enum Stage: String, Codable, CaseIterable, Identifiable {
        /// 무엇을 할지만 정했다.
        case planned
        /// 자료를 만드는 중.
        case preparing
        /// 자료가 다 됐다 — 올리기만 하면 된다.
        case ready
        /// 올라갔다(내가 그렇다고 답했다).
        case posted
        /// 안 올리기로 했다.
        case skipped
        var id: String { rawValue }
        var label: String {
            switch self {
            case .planned: "기획"
            case .preparing: "준비 중"
            case .ready: "자료 완성"
            case .posted: "올라감"
            case .skipped: "안 올림"
            }
        }
        var isOpen: Bool { self != .posted && self != .skipped }
    }

    struct Slide: Codable, Identifiable, Hashable {
        var id = UUID()
        var headline: String
        var text: String
        /// 영어판. 비어 있으면 영어 카드는 한국어를 그대로 쓴다.
        var headlineEn = ""
        var textEn = ""

        init(id: UUID = UUID(), headline: String, text: String, headlineEn: String = "", textEn: String = "") {
            self.id = id
            self.headline = headline
            self.text = text
            self.headlineEn = headlineEn
            self.textEn = textEn
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            headlineEn = try c.decodeIfPresent(String.self, forKey: .headlineEn) ?? ""
            textEn = try c.decodeIfPresent(String.self, forKey: .textEn) ?? ""
        }

        /// 그 언어로 보일 장. 영어가 비었으면 한국어.
        func localized(english: Bool) -> Slide {
            guard english, !(headlineEn.isEmpty && textEn.isEmpty) else { return self }
            return Slide(id: id, headline: headlineEn, text: textEn)
        }
    }

    // MARK: - 판정

    /// 올리기로 한 때가 지났는데 올렸다는 말이 없다 — 앱이 물어야 할 것.
    func needsConfirmation(now: Date = Date()) -> Bool {
        guard stage.isOpen, !isDeleted, let plannedAt, plannedAt <= now else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        return true
    }

    /// 자료가 비었나. 종류마다 무엇이 있어야 하는지가 다르다.
    var hasMaterial: Bool {
        switch kind {
        case .cardNews: !slides.isEmpty
        case .video: !(script + scriptEn).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .post: !(body + bodyEn).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 채널이 "r/SideProject" 처럼 서브레딧이면 그 이름. 레딧 글은 서브마다 다르게 쓴다.
    var subreddit: String? {
        channel.hasPrefix("r/") ? String(channel.dropFirst(2)) : nil
    }

    /// 그 서브레딧의 글쓰기 화면.
    var redditSubmitURL: URL? {
        subreddit.flatMap { URL(string: "https://www.reddit.com/r/\($0)/submit") }
    }

    /// 영어판이 비었나 — 마케팅 자료는 영어판이 있어야 한다.
    var lacksEnglish: Bool {
        switch kind {
        case .cardNews: slides.isEmpty || slides.contains { $0.headlineEn.isEmpty } || bodyEn.isEmpty
        case .video: scriptEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .post: bodyEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 이 활동에 지금 할 일 한 줄 — 목록이 판정 대신 보여 준다.
    func nextStep(now: Date = Date()) -> String {
        if needsConfirmation(now: now) { return "올렸나요? 답해 주세요" }
        if stage.isOpen, hasMaterial, lacksEnglish { return "영어판 채우기 — 마케팅 자료는 영어판이 있어야 해요" }
        switch stage {
        case .planned: return hasMaterial ? "자료를 다듬어 완성으로" : "자료 만들기 — Claude 에게 초안 맡기기"
        case .preparing: return hasMaterial ? "자료를 다듬어 완성으로" : "자료 채우기"
        case .ready: return plannedAt.map { "\(AppFormat.relative($0)) 올리기" } ?? "올릴 날 정하기"
        case .posted: return postURL.isEmpty ? "올린 주소 붙이기" : "올라감"
        case .skipped: return "안 올림"
        }
    }
}

// MARK: - 너그럽게 읽기

extension MarketingItem {
    /// 칸이 빠져 있어도 읽는다. 다른 기기의 옛 버전이 쓴 것(새 칸이 없다)이나 번들의 시드가
    /// 한 칸 때문에 통째로 버려지지 않게 — 자동 생성 디코딩은 기본값이 있어도 키를 요구한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        project = try c.decode(String.self, forKey: .project)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .post
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        angle = try c.decodeIfPresent(String.self, forKey: .angle) ?? ""
        plannedAt = try c.decodeIfPresent(Date.self, forKey: .plannedAt)
        stage = (try? c.decodeIfPresent(Stage.self, forKey: .stage)) ?? .planned
        slides = try c.decodeIfPresent([Slide].self, forKey: .slides) ?? []
        theme = try c.decodeIfPresent(Int.self, forKey: .theme)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        scriptEn = try c.decodeIfPresent(String.self, forKey: .scriptEn) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        bodyEn = try c.decodeIfPresent(String.self, forKey: .bodyEn) ?? ""
        postURL = try c.decodeIfPresent(String.self, forKey: .postURL) ?? ""
        postedAt = try c.decodeIfPresent(Date.self, forKey: .postedAt)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

// MARK: - 번들의 시드

/// 처음 채워 둔 활동들(`marketing-seed.json`). 앱마다 카드뉴스 · 영상 · 글을 다 써 둔 것이다.
///
/// 날짜는 ISO 문자열로 적는다(손으로 읽고 고치기 쉽게). 고친 시각을 시드를 만든 날로 박아
/// 두어서, 어느 기기에서 고친 것이든 시드보다 늦다 — 두 번째 기기가 시드를 들일 때 첫 기기에서
/// "올렸어요" 한 것을 덮지 않는다.
enum MarketingSeed {
    /// 시드를 바꿀 때마다 올린다. 2026-10-24: 모든 활동에 영어판. 2026-10-24b: 세끼 영어 이름 Sekki.
    /// 2026-10-25: 클립키보드 자료 13개 더함(템플릿 · 클립보드 · 링크드인 카드뉴스, 릴스 · 틱톡 · 쇼츠, PH · HN · 긱뉴스 · 클리앙 · 루리웹 · 스레드 · 레딧).
    /// 2026-10-25b: 클립키보드 레딧을 서브마다(채널 "r/…"): SideProject · iosapps · apphunt · productivity · freelance · digitalnomad.
    /// 2026-10-26: 나머지 앱 25개도 레딧을 서브마다 3~4곳으로(첫 글은 r/SideProject, 옛 "레딧" 글을 바꿈).
    /// 2026-10-26b: 오늘 올린 인스타 카드뉴스 · 스레드 글을 "올림" 으로(시드의 단계도 따라감).
    /// 2026-10-26c: 계좌번호 카드뉴스를 실제 앱 화면이 든 6장으로 다시 올린 대로.
    /// 2026-10-27: 오늘 올린 클립키보드 인스타 카드뉴스(이름만 다른 답장) · 스레드 글(출근 보고 스택).
    /// 2026-10-28: 오늘 올린 골드위크 인스타 카드뉴스(내년 설, 연차 하루로 닷새) · 스레드 글(마지막으로 쉰 날).
    /// 2026-10-29: 오늘 올린 두번알림 인스타 글(중요한 순간은 끝나기 전에) · 스레드 글(타이머가 땡 울리면 이미 늦다).
    static let version = "2026-10-29"
    static let fileName = "marketing-seed"
    /// 처음 시드를 만든 날. 시드에서 온 활동의 만든 시각 · 고친 시각이 이것이다.
    static let firstStamp = ISO8601DateFormatter().date(from: "2026-10-22T00:00:00Z") ?? .distantPast
    /// 시드를 새 판으로 바꿀 때 쓰는 고친 시각 — 첫 시드보다 1초 늦다. 사람이 고친 것은 무엇이든
    /// 이보다 늦으므로, 다른 기기와 합칠 때 시드의 새 판이 사람의 손을 덮지 않는다.
    static let refreshStamp = firstStamp.addingTimeInterval(1)

    private struct Entry: Decodable {
        let id: UUID
        let project: String
        let kind: String
        let channel: String
        let title: String
        let angle: String?
        let plannedAt: String?
        let stage: String?
        let slides: [MarketingItem.Slide]?
        let script: String?
        let body: String?
        let scriptEn: String?
        let bodyEn: String?
        let theme: Int?
    }

    static func load() -> [MarketingItem] {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let iso = ISO8601DateFormatter()
        let stamp = firstStamp
        return entries.map { entry in
            var item = MarketingItem(project: entry.project,
                                     kind: MarketingItem.Kind(rawValue: entry.kind) ?? .post,
                                     channel: entry.channel, title: entry.title)
            item.id = entry.id
            item.angle = entry.angle ?? ""
            item.plannedAt = entry.plannedAt.flatMap(iso.date(from:))
            item.stage = entry.stage.flatMap(MarketingItem.Stage.init(rawValue:)) ?? .ready
            item.slides = entry.slides ?? []
            item.script = entry.script ?? ""
            item.body = entry.body ?? ""
            item.scriptEn = entry.scriptEn ?? ""
            item.bodyEn = entry.bodyEn ?? ""
            // 영어로만 쓴 시드(레딧 글)는 영어 칸으로 옮긴다 — 한국어 칸에 영어가 있으면 영어판이 빈 것으로 보인다.
            if item.bodyEn.isEmpty, !item.body.isEmpty, item.body.range(of: "[가-힣]", options: .regularExpression) == nil {
                item.bodyEn = item.body
                item.body = ""
            }
            item.theme = entry.theme
            item.createdAt = stamp
            item.updatedAt = stamp
            return item
        }
    }
}

// MARK: - Claude 에게 넘길 글

/// 지시문에 붙일, 이 앱이 아는 것.
struct MarketingContext {
    var appName: String
    var storeName: String?
    var subtitle: String?
    var promotionalText: String?
    var storeKeywords: String?
    var storeURL: URL?
    var rankedKeywords: [String] = []
    var goodReviews: [String] = []
    var news: [String] = []
    var installs: Int?

    /// 지시문 앞머리 — 이 앱이 무엇이고 지금 무슨 일이 있나.
    var brief: String {
        var lines = ["앱: \(appName)"]
        if let storeName, storeName != appName { lines.append("스토어 이름: \(storeName)") }
        if let subtitle, !subtitle.isEmpty { lines.append("부제: \(subtitle)") }
        if let promotionalText, !promotionalText.isEmpty { lines.append("프로모션 문구: \(promotionalText)") }
        if let storeKeywords, !storeKeywords.isEmpty { lines.append("스토어 키워드 칸: \(storeKeywords)") }
        if let storeURL { lines.append("스토어 링크: \(storeURL.absoluteString)") }
        if let installs, installs > 0 { lines.append("누적 설치(허브 기준): \(installs)대") }
        if !rankedKeywords.isEmpty { lines.append("검색 순위에 잡힌 키워드: " + rankedKeywords.joined(separator: ", ")) }
        if !goodReviews.isEmpty {
            lines.append("좋은 리뷰(사용자의 말 그대로):")
            lines += goodReviews.map { "- \($0)" }
        }
        if !news.isEmpty {
            lines.append("최근 이 앱에 일어난 일:")
            lines += news.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

enum MarketingPrompt {
    static let dateFormat = "yyyy-MM-dd"

    /// 2주 치 마케팅 계획을 받는 지시문. 답은 붙여 넣으면 활동으로 들어오는 JSON.
    static func plan(_ context: MarketingContext, today: Date = Date()) -> String {
        """
        1인 개발자의 iOS 앱 마케팅을 기획해 줘. 광고비 없이 할 수 있는 것만.

        \(context.brief)

        오늘은 \(day(today))이야. 앞으로 2주 동안 할 마케팅 활동을 4~6개 짜 줘.
        - 종류는 cardNews(카드뉴스), video(짧은 세로 영상), post(글) 중 하나
        - 채널은 한국 사용자가 많은 곳 위주로(인스타그램, 스레드, 유튜브 쇼츠, 네이버 블로그, 디스콰이엇 등). 해외도 노릴 만하면 레딧 · X
        - 활동마다 "누구에게 무엇을 왜 지금" 을 angle 에 두세 문장으로
        - 위의 좋은 리뷰 · 최근 일어난 일을 소재로 쓸 수 있으면 써
        - 하루에 하나 이하로 날짜를 흩어

        답은 설명 없이 아래 JSON 배열 하나만:
        [{"kind":"cardNews","channel":"인스타그램","title":"한 줄 주제","angle":"누구에게 무엇을 왜 지금","date":"\(day(today))"}]
        """
    }

    /// 활동 하나의 자료 초안을 받는 지시문.
    static func material(_ item: MarketingItem, context: MarketingContext) -> String {
        let head = """
        1인 개발자의 iOS 앱을 알리는 \(item.kind.label)를 만들어 줘. 올릴 곳: \(item.channel).

        \(context.brief)

        주제: \(item.title)
        기획: \(item.angle.isEmpty ? "(없음 — 주제에 맞게)" : item.angle)

        말투는 광고 같지 않게, 써 본 사람이 친구에게 알려 주듯. 과장 · 이모지 남발 금지.
        한국어판과 영어판을 둘 다 만들어 줘. 영어판은 번역투가 아니라 영어권 사람이 쓴 것처럼 다시 쓰고,
        영어권 채널 관습(짧은 문장, 해시태그 적게)에 맞춰.
        """
        switch item.kind {
        case .cardNews:
            return head + """


            카드뉴스는 5~7장. 첫 장은 멈춰 서게 하는 한 줄, 마지막 장은 앱 이름과 "App Store 에서 검색" 안내.
            장마다 headline 은 15자 안팎, text 는 두세 줄. 게시글 캡션과 해시태그 5개도.
            답은 설명 없이 아래 JSON 하나만:
            {"slides":[{"headline":"...","text":"...","headlineEn":"...","textEn":"..."}],"caption":"캡션 본문\\n\\n#해시태그","captionEn":"English caption\\n\\n#hashtag"}
            """
        case .video:
            return head + """


            30초 안팎의 세로 영상. 처음 2초 안에 멈춰 서게 하고, 화면 녹화 위주로 찍을 수 있게.
            장면마다 [시간] 화면에 보이는 것 / 자막 / 내레이션 으로. 올릴 때 쓸 캡션도.
            답은 설명 없이 아래 JSON 하나만:
            {"script":"[0-2초] 화면: ... / 자막: ... / 내레이션: ...\\n[2-6초] ...","scriptEn":"[0-2s] Screen: ... / Caption: ... / VO: ...","caption":"...","captionEn":"..."}
            """
        case .post:
            return head + """


            \(item.channel)에 맞는 길이와 형식으로. 첫 줄에서 읽을 이유를 주고, 끝에 앱 링크 자리를 [링크]로.
            답은 설명 없이 아래 JSON 하나만:
            {"body":"한국어 글","bodyEn":"English post"}
            """
        }
    }

    /// 레딧 질문에 다는 답글 초안. 도움이 먼저, 앱은 그다음 — 그리고 만든 사람이라고 밝힌다.
    static func redditReply(_ lead: RedditLead, context: MarketingContext) -> String {
        """
        레딧 \(lead.subreddit) 에 올라온 질문에 답글을 달려고 해. 나는 아래 앱을 혼자 만든 개발자야.

        질문 제목: \(lead.title)
        질문 본문(앞부분): \(lead.snippet.isEmpty ? "(본문 없음)" : lead.snippet)
        글 주소: \(lead.url.absoluteString)

        \(context.brief)

        답글 규칙:
        - 질문에 먼저 진짜로 답한다. 내 앱이 맞지 않는 질문이면 "이 질문에는 내 앱이 맞지 않다"고 말해 줘 — 억지로 끼워 넣지 않는다
        - 내 앱을 말할 때는 반드시 "I made this" 처럼 만든 사람이라고 밝힌다
        - 광고 말투 · 과장 · 이모지 금지. 레딧 사람이 쓰는 말투로, 120단어 안
        - 앱이 실제로 하는 일만. 질문한 사람의 상황에 어떻게 맞는지 한두 문장으로
        - 링크는 맨 끝에 한 번만, 서브레딧이 링크를 싫어할 것 같으면 "App Store에서 앱 이름 검색" 으로
        - 다른 좋은 방법(내장 기능 · 다른 앱)이 있으면 같이 알려 준다 — 그래야 믿는다

        답은 두 판으로:
        영어 답글:
        (그대로 붙여 넣을 영어 답글)

        한국어 뜻:
        (위 답글을 한국어로)
        """
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }
}

// MARK: - Claude 의 답 들이기

enum MarketingImport {
    struct PlannedItem: Decodable {
        let kind: String?
        let channel: String?
        let title: String
        let angle: String?
        let date: String?
    }

    struct Material: Decodable {
        struct Slide: Decodable { let headline: String?; let text: String?; let headlineEn: String?; let textEn: String? }
        let slides: [Slide]?
        let caption: String?
        let captionEn: String?
        let script: String?
        let scriptEn: String?
        let body: String?
        let bodyEn: String?
    }

    /// 계획 JSON → 활동들. 앞뒤 말이나 코드 울타리가 붙어 있어도 배열만 골라 읽는다.
    static func plan(_ text: String, project: String) -> [MarketingItem]? {
        guard let json = slice(text, open: "[", close: "]"),
              let planned = try? JSONDecoder().decode([PlannedItem].self, from: Data(json.utf8)),
              !planned.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = MarketingPrompt.dateFormat
        return planned.map { entry in
            let kind = entry.kind.flatMap(MarketingItem.Kind.init(rawValue:)) ?? .post
            // 날짜만 오면 오전 10시에 올리는 것으로 — 자정에 "올렸나요?" 를 묻지 않게.
            let date = entry.date.flatMap(formatter.date(from:))
                .flatMap { Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }
            return MarketingItem(project: project, kind: kind,
                                 channel: entry.channel ?? kind.suggestedChannels[0],
                                 title: entry.title, angle: entry.angle ?? "", plannedAt: date)
        }
    }

    /// 자료 JSON → 활동에 채운다. JSON 이 아니면 글 그대로 본문(영상이면 대본)으로.
    static func material(_ text: String, into item: inout MarketingItem) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let json = slice(trimmed, open: "{", close: "}"),
           let material = try? JSONDecoder().decode(Material.self, from: Data(json.utf8)) {
            if let slides = material.slides, !slides.isEmpty {
                item.slides = slides.map { .init(headline: $0.headline ?? "", text: $0.text ?? "",
                                                 headlineEn: $0.headlineEn ?? "", textEn: $0.textEn ?? "") }
            }
            if let script = material.script, !script.isEmpty { item.script = script }
            if let script = material.scriptEn, !script.isEmpty { item.scriptEn = script }
            if let body = material.body ?? material.caption, !body.isEmpty { item.body = body }
            if let body = material.bodyEn ?? material.captionEn, !body.isEmpty { item.bodyEn = body }
        } else if item.kind == .video {
            item.script = trimmed
        } else {
            item.body = trimmed
        }
        if item.stage == .planned { item.stage = .preparing }
        return true
    }

    private static func slice(_ text: String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open), let end = text.lastIndex(of: close), start < end else { return nil }
        return String(text[start...end])
    }
}

// MARK: - 캠페인

/// Apple 캠페인 링크 — 스토어 링크에 제공자 토큰(`pt`)과 캠페인 토큰(`ct`)을 붙이면 App Store
/// Connect 분석 리포트의 `Campaign` 칸에 그 이름으로 다운로드 · 조회가 남는다. 마케팅 활동마다
/// 토큰을 달아 두면 "어느 글이 사람을 데려왔나" 를 셀 수 있다.
///
/// `pt` 는 계정마다 하나다. App Store Connect → 앱 → 분석 → 획득 → 캠페인 → "캠페인 링크 생성"
/// 에서 만든 링크의 `pt=` 뒤 숫자. 없으면 `ct` 만 붙여서는 아무것도 세지 않는다.
enum MarketingCampaign {
    /// "인스타그램" → "ig". 토큰은 영문 · 숫자 · 하이픈만, 40자 안.
    static func channelSlug(_ channel: String) -> String {
        let known: [(String, String)] = [
            ("인스타", "ig"), ("instagram", "ig"), ("스레드", "threads"), ("threads", "threads"),
            ("레딧", "reddit"), ("reddit", "reddit"), ("디스콰이엇", "disquiet"), ("블로그", "blog"),
            ("브런치", "brunch"), ("긱뉴스", "geeknews"), ("쇼츠", "shorts"), ("유튜브", "youtube"),
            ("릴스", "reels"), ("틱톡", "tiktok"), ("링크드인", "linkedin"), ("페이스북", "facebook"),
            ("카카오", "kakao"), ("오픈채팅", "kakao"), ("product hunt", "producthunt"),
        ]
        let lower = channel.lowercased()
        if lower == "x" || lower.hasPrefix("x ") || lower.contains("트위터") || lower.contains("twitter") { return "x" }
        if lower.hasPrefix("r/") { return "reddit" }
        if let hit = known.first(where: { lower.contains($0.0) }) { return hit.1 }
        let ascii = lower.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return ascii.isEmpty ? "etc" : String(ascii.prefix(12))
    }

    static func link(trackId: Int, providerToken: String, campaignToken: String) -> String {
        "https://apps.apple.com/app/id\(trackId)?pt=\(providerToken)&ct=\(campaignToken)&mt=8"
    }

    /// 글 속의 스토어 링크를 캠페인 링크로. 같은 앱 링크만 바꾼다(id 가 같은 것) — 다른 앱을
    /// 소개한 링크까지 내 캠페인으로 세면 안 된다.
    static func replacingStoreLinks(in text: String, trackId: Int, with link: String) -> String {
        let pattern = #"https?://apps\.apple\.com/[^\s)\]"'<>]*id\#(trackId)[^\s)\]"'<>]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range,
                                              withTemplate: NSRegularExpression.escapedTemplate(for: link))
    }
}

extension MarketingItem {
    /// 이 활동의 캠페인 토큰 — "ig-1a2b3c". 활동 id 에서 뽑아 늘 같다.
    var campaignToken: String {
        "\(MarketingCampaign.channelSlug(channel))-\(id.uuidString.prefix(6).lowercased())"
    }
}

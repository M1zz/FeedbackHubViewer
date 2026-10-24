//
//  WebMentions.swift
//  FeedbackHubViewer
//
//  바깥에서 내 앱 이야기를 찾는다 — 웹 기사 · 블로그(Google 뉴스)와 레딧. 열쇠도 계정도
//  필요 없다.
//
//   · Google 뉴스: `news.google.com/rss/search?q="검색어"` — 한국어판과 영어판을 따로 묻는다.
//     같은 기사가 두 판에 다 나오면 주소로 하나만 남긴다.
//   · 레딧: `www.reddit.com/search.rss?q="검색어"&sort=new` — 글 제목 · 본문 검색(Atom).
//     JSON 검색(`search.json`)은 로그인 없는 요청을 403 으로 막는다. RSS 는 열려 있지만
//     몇 번 잇달아 부르면 429 를 주므로, 레딧만은 앱 사이에 간격을 두고(`redditSpacing`)
//     막히면 그 회차는 건너뛴다 — 6시간 뒤에 다시 본다.
//
//  앱 이름이 흔한 낱말이면 엉뚱한 글이 섞인다. 그래서 검색어는 따옴표로 묶어 통째로 찾고,
//  돌아온 제목 · 요약에 검색어가 실제로 있는 것만 남긴다. 그래도 섞이면 앱마다 검색어를
//  바꾼다(`NewsStore.searchTerms`).
//

import Foundation

struct WebMention: Codable, Hashable {
    let title: String
    let url: URL
    /// "Google 뉴스 · 매체 이름", "r/iphone".
    let source: String
    let date: Date?
    /// 어떤 검색어로 찾았나.
    let term: String
}

enum WebMentions {

    /// 레딧 요청 사이 간격.
    static let redditSpacing: Duration = .seconds(3)

    /// 이보다 오래된 글은 소식이 아니다.
    static let maxAge: TimeInterval = 30 * 24 * 3600

    /// 한 앱의 검색어들로 찾은 것 전부, 새것부터. 한 곳이 실패해도 나머지는 돌려준다.
    static func search(terms: [String], now: Date = Date()) async -> [WebMention] {
        var found: [WebMention] = []
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            async let korean = googleNews(trimmed, language: "ko", region: "KR")
            async let english = googleNews(trimmed, language: "en-US", region: "US")
            found += await korean + english
            found += await reddit(trimmed)
            try? await Task.sleep(for: redditSpacing)
        }
        var seen: Set<URL> = []
        return found
            .filter { mention in
                guard let date = mention.date else { return true }
                return now.timeIntervalSince(date) <= maxAge
            }
            .filter { seen.insert($0.url).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - Google 뉴스

    private static func googleNews(_ term: String, language: String, region: String) async -> [WebMention] {
        var components = URLComponents(string: "https://news.google.com/rss/search")!
        let lang = language.split(separator: "-").first.map(String.init) ?? language
        components.queryItems = [
            URLQueryItem(name: "q", value: "\"\(term)\""),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "gl", value: region),
            URLQueryItem(name: "ceid", value: "\(region):\(lang)")
        ]
        guard let url = components.url, let data = await fetch(url) else { return [] }
        return RSSItems.parse(data).compactMap { item in
            guard let link = URL(string: item.link), mentions(term, in: item.title + " " + item.description) else { return nil }
            // Google 뉴스 제목은 "기사 제목 - 매체" 꼴이다.
            let outlet = item.source ?? item.title.components(separatedBy: " - ").last ?? "웹"
            let title = item.source.map { item.title.replacingOccurrences(of: " - \($0)", with: "") } ?? item.title
            return WebMention(title: title, url: link, source: outlet, date: item.date, term: term)
        }
    }

    // MARK: - 레딧

    private static func reddit(_ term: String) async -> [WebMention] {
        var components = URLComponents(string: "https://www.reddit.com/search.rss")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\"\(term)\""),
            URLQueryItem(name: "sort", value: "new")
        ]
        guard let url = components.url, let data = await fetch(url) else { return [] }
        return RSSItems.parse(data).compactMap { item in
            guard let link = URL(string: item.link), mentions(term, in: item.title + " " + item.description) else { return nil }
            return WebMention(title: item.title, url: link, source: item.source ?? "Reddit", date: item.date, term: term)
        }
    }

    // MARK: - 공통

    /// 따옴표 검색도 비슷한 말을 섞어 돌려준다. 글에 검색어가 실제로 있는 것만.
    static func mentions(_ term: String, in text: String) -> Bool {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }

    static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // 레딧은 이름 없는 요청을 막는다.
        request.setValue("macos:com.Ysoup.FeedbackHubViewer:1.0 (app news)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            print("❌ [WebMentions.fetch] \(url.host() ?? "") \(error.localizedDescription)")
            return nil
        }
    }
}

/// RSS 2.0 의 `<item>` 과 Atom 의 `<entry>` 만 읽는 작은 파서. Atom 은 링크를 `href` 속성에,
/// 레딧은 게시판 이름을 `<category label="r/…">` 에 둔다.
final class RSSItems: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var description = ""
        var source: String?
        var date: Date?
    }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let reader = RSSItems()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.items
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" || elementName == "entry" { current = Item() }
        if elementName == "link", let href = attributeDict["href"] { current?.link = href }
        if elementName == "category", let label = attributeDict["label"] { current?.source = label }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "item", "entry":
            if let current { items.append(current) }
            current = nil
        case "title": current?.title = value
        // Atom 의 <link/> 는 비어 있다 — 속성에서 이미 읽었다.
        case "link": if !value.isEmpty { current?.link = value }
        // 요약은 HTML 조각으로 온다. 검색어가 들었는지만 볼 것이라 태그는 그대로 둔다.
        case "description", "content": current?.description = value
        case "source": current?.source = value.isEmpty ? nil : value
        case "pubDate": current?.date = Self.dateFormatter.date(from: value)
        case "published": current?.date = Self.isoFormatter.date(from: value)
        // 레딧 Atom 은 published 가 없고 updated 만 있을 때가 있다.
        case "updated": if current?.date == nil { current?.date = Self.isoFormatter.date(from: value) }
        default: break
        }
        text = ""
    }
}

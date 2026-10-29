//
//  RSSItems.swift
//  FeedbackHubViewer
//
//  RSS · Atom 을 받아 글 목록으로 읽는다. 질문 찾기가 레딧 API 키 없이 찾을 때 쓴다.
//

import Foundation

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

    static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // 레딧은 이름 없는 요청을 막는다.
        request.setValue("macos:com.Ysoup.FeedbackHubViewer:1.0 (lead search)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            print("❌ [RSSItems.fetch] \(url.host() ?? "") \(error.localizedDescription)")
            return nil
        }
    }

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

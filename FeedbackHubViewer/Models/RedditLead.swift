//
//  RedditLead.swift
//  FeedbackHubViewer
//
//  레딧에서 "이런 앱 없나요?" 를 묻는 글 — 내 앱이 답이 될 수 있는 질문.
//
//  자동으로 답글을 달지 않는다. 자동 홍보는 레딧 정책(스팸 · 플랫폼 조작)에 걸리고, 걸리면
//  계정과 앱 링크 도메인까지 막힌다. 허브는 질문을 찾아 모으고 답글 초안을 맡길 글을 만들 뿐,
//  답은 사람이 직접 단다.
//
//  찾는 법: 앱마다 그 앱이 푸는 필요를 사람이 묻는 말로 적은 검색어(`LeadQueries`)로 레딧
//  최근 글을 찾고(서브레딧을 정해 두면 그 안에서), 제목 · 본문이 질문 꼴인 것만 남긴다.
//

import Foundation

struct RedditLead: Codable, Identifiable, Hashable {
    /// "프로젝트|레딧 글 id" — 같은 글이 두 앱의 질문일 수 있다.
    let id: String
    let project: String
    let postID: String
    let title: String
    /// 본문 앞부분(태그 뺀 것).
    let snippet: String
    let url: URL
    /// "r/iphone"
    let subreddit: String
    let date: Date?
    /// 어떤 검색어로 찾았나.
    let query: String
    /// 앱 · 방법을 묻는 꼴인가. 아니어도(쓰는 법 공유 · 불평) 답글로 도울 수 있어 남기되 뒤에 둔다.
    var isQuestion: Bool?
    let foundAt: Date
    var status: Status = .new
    /// 질문 찾기 칸에서 본 적이 있나 — 사이드바 뱃지가 센다.
    var viewed = false
    var updatedAt: Date

    enum Status: String, Codable {
        /// 답할지 정하지 않았다.
        case new
        /// 답글을 달았다.
        case replied
        /// 내 앱과 상관없다.
        case dismissed
    }
}

/// 앱마다 질문을 찾을 검색어와 서브레딧.
struct LeadQueries: Codable, Hashable {
    var queries: [String]
    var queriesKo: [String]
    var subreddits: [String]

    private struct Entry: Decodable {
        let project: String
        let queries: [String]
        let queriesKo: [String]?
        let subreddits: [String]?
    }

    /// 번들의 기본값(`lead-queries.json`). 사용자가 고친 것은 `LeadStore` 가 따로 든다.
    static let defaults: [String: LeadQueries] = {
        guard let url = Bundle.main.url(forResource: "lead-queries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(entries.map {
            ($0.project.lowercased(), LeadQueries(queries: $0.queries, queriesKo: $0.queriesKo ?? [], subreddits: $0.subreddits ?? []))
        }, uniquingKeysWith: { a, _ in a })
    }()
}

enum RedditLeadSearch {
    /// 이만큼 지난 글은 답해도 늦었다 — 레딧은 6개월 지난 글에 댓글을 막는다. 앱을 찾는 질문은
    /// 한 달에 몇 개 안 올라와서, 그 안이면 다 답할 거리다.
    static let maxAge: TimeInterval = 180 * 24 * 3600

    /// 질문 꼴인가 — 제목의 물음표, 또는 제목 · 본문의 앱 · 방법을 찾는 말.
    static func isQuestion(title: String, body: String) -> Bool {
        if title.contains("?") { return true }
        let text = title + " " + body
        let pattern = #"\bapps? (for|to|that)\b|\bany (good )?apps?\b|\blooking for\b|\brecommend|\bsuggestions?\b|\balternative|\bis there (an?|any)\b|\bneed an? app\b|\bbest (app|way)\b|\bhow (do|can|should) (i|you)\b|추천|없나요|있나요|어떤 앱|뭐 쓰|쓸만한"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 한 앱의 검색어로 찾은 글들. 레딧 API 키가 있으면 API 로, 없으면 RSS 로(막히면 그 검색어는
    /// 건너뛴다). 앞의 것이 실패했으면 까닭을 돌려준다.
    static func search(project: String, queries: LeadQueries, now: Date = Date()) async -> (leads: [RedditLead], problem: String?) {
        var found: [String: RedditLead] = [:]
        var problem: String?
        let subs = queries.subreddits.map { $0.replacingOccurrences(of: "r/", with: "") }.filter { !$0.isEmpty }
        let plan = queries.queries.map { ($0, subs) } + queries.queriesKo.map { ($0, [String]()) }
        let useAPI = RedditAPI.isConfigured

        func add(id postID: String, title: String, body: String, subreddit: String, url: URL, date: Date?, query: String) {
            guard isRelevant(query: query, title: title, body: body, subreddits: subs) else { return }
            if let date, now.timeIntervalSince(date) > maxAge { return }
            let id = "\(project)|\(postID)"
            guard found[id] == nil else { return }
            found[id] = RedditLead(id: id, project: project, postID: postID, title: title,
                                   snippet: String(body.prefix(600)), url: url, subreddit: subreddit, date: date,
                                   query: query, isQuestion: isQuestion(title: title, body: String(body.prefix(400))),
                                   foundAt: now, updatedAt: now)
        }

        for (query, inSubs) in plan {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if useAPI {
                do {
                    for post in try await RedditAPI.shared.search(trimmed, subreddits: inSubs) where !post.closed {
                        add(id: post.id, title: post.title, body: post.body, subreddit: post.subreddit,
                            url: post.url, date: post.created, query: trimmed)
                    }
                } catch {
                    problem = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(1))
            } else {
                guard let url = searchURL(trimmed, subreddits: inSubs) else { continue }
                if let data = await WebMentions.fetch(url) {
                    for item in RSSItems.parse(data) {
                        guard let link = URL(string: item.link), let postID = postID(link) else { continue }
                        add(id: postID, title: item.title, body: plainText(item.description),
                            subreddit: item.source ?? "Reddit", url: link, date: item.date, query: trimmed)
                    }
                } else {
                    problem = "레딧이 요청을 막았어요(키 없이 찾는 RSS 는 자주 막힙니다). 레딧 API 키를 넣으면 막히지 않아요."
                }
                try? await Task.sleep(for: .seconds(6))
            }
        }
        return (Array(found.values), problem)
    }

    /// 흔해서 아무 글에나 있는 말 — 관련 있는지 가를 때 세지 않는다.
    private static let generic: Set<String> = [
        "app", "apps", "iphone", "ipad", "ios", "mac", "macos", "apple", "watch", "best", "good", "for", "the",
        "and", "with", "free", "to", "a", "an", "of", "in", "on", "앱", "어플", "아이폰", "추천",
    ]

    /// 검색어의 핵심 낱말이 글에 절반 넘게 있고, 그중 하나는 제목에 있나. 레딧 검색은 낱말
    /// 하나만 맞아도 돌려준다("text expander iphone" 에 iMessage 오류 글) — 그래서 다시 거른다.
    /// 전부를 요구하면 질문을 다르게 적은 사람(“snippet app” 대신 “text shortcut app”)을 놓친다.
    static func isRelevant(query: String, title: String, body: String, subreddits: [String] = []) -> Bool {
        // 서브레딧 이름에 든 말은 그 안의 글 어디에나 있다(r/Teachers 의 "teacher").
        let local = Set(subreddits.flatMap { name -> [String] in
            let low = name.lowercased()
            return [low, low.hasSuffix("s") ? String(low.dropLast()) : low]
        })
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init).filter { !generic.contains($0) && !local.contains($0) && $0.count >= 2 }
        guard !words.isEmpty else { return true }
        // 끝이 조금 다른 꼴(timer / timers, snippet / snippets)도 맞는 것으로.
        func has(_ word: String, in text: String) -> Bool {
            text.contains(word) || (word.count > 4 && text.contains(String(word.dropLast())))
        }
        let lowTitle = title.lowercased(), all = (title + " " + body).lowercased()
        let hits = words.filter { has($0, in: all) }.count
        // 핵심 낱말이 둘 이하면 다, 셋 이상이면 둘 넘게 — 그리고 하나는 제목에.
        let needed = words.count <= 2 ? words.count : max(2, (words.count + 1) / 2)
        return hits >= needed && words.contains { has($0, in: lowTitle) }
    }

    private static func searchURL(_ query: String, subreddits: [String]) -> URL? {
        let base = subreddits.isEmpty ? "https://www.reddit.com/search.rss"
            : "https://www.reddit.com/r/\(subreddits.joined(separator: "+"))/search.rss"
        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            // RSS 의 관련순은 실측에서 더 엉뚱했다 — 최신순으로 받고 `isRelevant` 로 거른다.
            URLQueryItem(name: "sort", value: "new"),
            URLQueryItem(name: "t", value: "year"),
        ] + (subreddits.isEmpty ? [] : [URLQueryItem(name: "restrict_sr", value: "on")])
        return components?.url
    }

    /// ".../comments/abc123/title/" → "abc123"
    static func postID(_ url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "comments"), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    /// 레딧 RSS 본문은 HTML 조각이다. 태그와 흔한 엔티티만 걷어 읽을 수 있게.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "submitted by.*$", with: "", options: .regularExpression)
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

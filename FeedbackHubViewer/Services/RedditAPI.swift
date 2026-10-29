//
//  RedditAPI.swift
//  FeedbackHubViewer
//
//  레딧 공식 API 로 검색한다 — 질문 찾기(`RedditLeadSearch`)가 쓴다.
//
//  로그인 없는 RSS 검색은 몇 번만 불러도 429 로 막히고(실측: 네 번 중 세 번), 관련순 결과도
//  엉뚱했다. API 는 분당 100번까지 받아 주고, 글 본문 전체 · 보관 여부(6개월 지나 댓글이 막힌
//  글)까지 준다. 쓰려면 레딧 계정에서 개인용 "script" 앱을 하나 만들어 client id 와 secret 을
//  넣는다 — 사용자 로그인 없이 앱만으로 읽는 방식(client credentials)이라 비밀번호는 필요 없다.
//
//  키는 App Store Connect 키처럼 iCloud 키체인에 둔다(다른 기기에서도 쓰게).
//

import Foundation

struct RedditCredentials: Codable, Equatable {
    var clientID: String
    var secret: String
}

enum RedditKeychain {
    private static let service = "com.Ysoup.FeedbackHubViewer.reddit"
    private static let account = "script-app"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func load() -> RedditCredentials? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(RedditCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: RedditCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// API 검색 결과 한 글.
struct RedditPost {
    let id: String
    let title: String
    let body: String
    /// "r/iphone"
    let subreddit: String
    let url: URL
    let created: Date
    /// 보관됐거나 잠겨 댓글을 달 수 없다.
    let closed: Bool
    let comments: Int
}

actor RedditAPI {
    static let shared = RedditAPI()

    enum Failure: LocalizedError {
        case noCredentials
        case auth(Int)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noCredentials: "레딧 API 키가 없습니다."
            case .auth(let code): "레딧 API 키를 확인하세요 (인증 HTTP \(code))."
            case .http(let code): "레딧 검색이 응답하지 않았습니다 (HTTP \(code))."
            }
        }
    }

    private var token: (value: String, expires: Date)?
    /// 레딧은 알아볼 수 있는 이름을 요구한다 — "플랫폼:앱 id:버전 (by u/이름)".
    private static let userAgent = "macos:com.Ysoup.FeedbackHubViewer:1.0 (lead search)"

    /// 키가 있나. 없으면 RSS 로 찾는다.
    static var isConfigured: Bool { RedditKeychain.load() != nil }

    private func accessToken() async throws -> String {
        if let token, token.expires > Date().addingTimeInterval(60) { return token.value }
        guard let credentials = RedditKeychain.load() else { throw Failure.noCredentials }
        var request = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        request.httpMethod = "POST"
        request.httpBody = Data("grant_type=client_credentials".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let basic = Data("\(credentials.clientID):\(credentials.secret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["access_token"] as? String else { throw Failure.auth(status) }
        let seconds = (object["expires_in"] as? Double) ?? 3600
        token = (value, Date().addingTimeInterval(seconds))
        return value
    }

    /// 지난 1년 글을 최신순으로(최대 100개). `subreddits` 가 있으면 그 안에서만.
    func search(_ query: String, subreddits: [String]) async throws -> [RedditPost] {
        let token = try await accessToken()
        let base = subreddits.isEmpty ? "https://oauth.reddit.com/search"
            : "https://oauth.reddit.com/r/\(subreddits.joined(separator: "+"))/search"
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "new"),
            URLQueryItem(name: "t", value: "year"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "type", value: "link"),
            URLQueryItem(name: "raw_json", value: "1"),
        ] + (subreddits.isEmpty ? [] : [URLQueryItem(name: "restrict_sr", value: "true")])
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { self.token = nil }
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let listing = object["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]] else { throw Failure.http(status) }
        return children.compactMap { child in
            guard let post = child["data"] as? [String: Any],
                  let id = post["id"] as? String,
                  let title = post["title"] as? String,
                  let permalink = post["permalink"] as? String,
                  let url = URL(string: "https://www.reddit.com" + permalink) else { return nil }
            return RedditPost(
                id: id, title: title, body: (post["selftext"] as? String) ?? "",
                subreddit: (post["subreddit_name_prefixed"] as? String) ?? "Reddit", url: url,
                created: Date(timeIntervalSince1970: (post["created_utc"] as? Double) ?? 0),
                closed: (post["archived"] as? Bool) == true || (post["locked"] as? Bool) == true,
                comments: (post["num_comments"] as? Int) ?? 0)
        }
    }
}

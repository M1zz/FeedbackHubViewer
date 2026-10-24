//
//  AppStoreSearch.swift
//  FeedbackHubViewer
//
//  The App Store, read through the only door Apple leaves open: the public
//  iTunes Search API.
//
//  Two endpoints carry everything the 키워드 screen shows:
//
//    lookup?bundleId=a,b,c  — the hub already knows every app's bundle id, so
//      one request turns all of them into App Store apps. This is what links
//      "com.Ysoup.TokenMemo" in the CloudKit data to "클립키보드" in the store.
//
//    search?term=…&limit=200 — the store's own search results, in order. Where
//      an app sits in that list is its rank for that keyword.
//
//  The saving that shapes everything here: **one search covers every app you
//  own.** A single request for "클립보드" returns 200 results, and the position
//  of each of your twenty apps is read out of that one list, along with the
//  competitors above them. So the cost of a check is 키워드 × 국가, never
//  앱 × 키워드 — which is the difference between a minute and an hour once you
//  have twenty apps on the store.
//
//  What this API cannot give, and no honest screen should invent:
//
//   - 검색량. Apple publishes none. Every ASO tool's volume figure is a model,
//     not a measurement, so this one shows none rather than a made-up number.
//   - 부제(subtitle). Not in the response; only the name and the description.
//   - Google Play. No official API at all — a different problem entirely.
//
//  And one caveat worth keeping in view: the Search API's ordering is a very
//  good proxy for App Store search ranking, not a guarantee of it. It is the
//  same proxy every tool at this price uses.
//

import Foundation

/// One app as the App Store describes it.
struct StoreApp: Identifiable, Codable, Hashable {
    /// `trackId` — the App Store's own identifier, and the key everything here
    /// is filed under. Stable across renames, unlike the name.
    let id: Int
    let bundleId: String?
    let name: String
    let sellerName: String?
    let genres: [String]
    let averageRating: Double?
    let ratingCount: Int
    let version: String?
    let releasedAt: Date?
    let iconURL: URL?

    var storeURL: URL? { URL(string: "https://apps.apple.com/app/id\(id)") }
}

/// The iTunes Search API, rate-limited and decoded.
///
/// An actor so the interval below actually holds: a check fires one request per
/// keyword and they must queue rather than race.
actor AppStoreDirectory {

    static let shared = AppStoreDirectory()

    /// How deep a search reads. 200 is the endpoint's own ceiling, and it is
    /// also about as far down as a rank still means anything.
    static let searchDepth = 200

    enum Failure: LocalizedError {
        case throttled
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .throttled:
                return "App Store 검색 요청이 잠시 제한되었습니다. 잠시 후 다시 시도하세요."
            case .badResponse(let code):
                return "App Store가 응답하지 않았습니다 (HTTP \(code))."
            }
        }
    }

    /// Turn bundle ids into store apps. Comma-separated, so the hub's whole app
    /// list costs one request per storefront.
    func lookup(bundleIds: [String], country: String) async throws -> [StoreApp] {
        guard !bundleIds.isEmpty else { return [] }
        var results: [StoreApp] = []
        // Twenty at a time: the endpoint takes a comma-separated list, but a
        // long enough URL comes back rejected rather than truncated.
        for chunk in stride(from: 0, to: bundleIds.count, by: 20).map({
            Array(bundleIds[$0..<min($0 + 20, bundleIds.count)])
        }) {
            let items = try await get(path: "lookup", query: [
                "bundleId": chunk.joined(separator: ","),
                "country": country,
                "entity": "software",
            ])
            results.append(contentsOf: items)
        }
        return results
    }

    /// App Store id 로 바로. 번들 ID 가 어긋난 앱을 스토어 링크로 이을 때 쓴다.
    func lookup(ids: [Int], country: String) async throws -> [StoreApp] {
        guard !ids.isEmpty else { return [] }
        return try await get(path: "lookup", query: [
            "id": ids.map(String.init).joined(separator: ","),
            "country": country,
        ])
    }

    /// The store's search results for a term, in the order the store returns
    /// them. Position in this list is what "순위" means everywhere else.
    func search(term: String, country: String) async throws -> [StoreApp] {
        try await get(path: "search", query: [
            "term": term,
            "country": country,
            "entity": "software",
            "limit": String(Self.searchDepth),
        ])
    }

    // MARK: - Transport

    private func get(path: String, query: [String: String]) async throws -> [StoreApp] {
        try await pace()
        var components = URLComponents(string: "https://itunes.apple.com/\(path)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        // Without a plausible agent the endpoint sometimes answers a bare 403.
        request.setValue("FeedbackHubViewer/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 403 { await ITunesGate.shared.backOff() }
            throw http.statusCode == 403 ? Failure.throttled : Failure.badResponse(http.statusCode)
        }
        return try Self.decode(data)
    }

    /// 차트 피드와 같은 줄에 선다(`ITunesGate`).
    private func pace() async throws {
        try await ITunesGate.shared.wait()
    }

    /// Decoded by hand rather than with `Codable`.
    ///
    /// The response is a loose bag: a field can be missing on one app and
    /// present on the next, `averageUserRating` arrives as a number or not at
    /// all, and a strict decoder that threw on any of it would drop the whole
    /// page of results over one odd app. Everything here is optional-tolerant
    /// on purpose — a result missing a name is skipped, and nothing else is.
    private static func decode(_ data: Data) throws -> [StoreApp] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = root?["results"] as? [[String: Any]] ?? []
        return results.compactMap { item in
            guard let id = item["trackId"] as? Int,
                  let name = item["trackName"] as? String else { return nil }
            return StoreApp(
                id: id,
                bundleId: item["bundleId"] as? String,
                name: name,
                sellerName: item["sellerName"] as? String,
                genres: item["genres"] as? [String] ?? [],
                averageRating: item["averageUserRating"] as? Double,
                ratingCount: item["userRatingCount"] as? Int ?? 0,
                version: item["version"] as? String,
                releasedAt: (item["currentVersionReleaseDate"] as? String).flatMap(iso.date(from:)),
                iconURL: (item["artworkUrl100"] as? String).flatMap(URL.init(string:)))
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// `itunes.apple.com` 의 문지기. 키워드 검색 · 앱 조회 · 차트 피드는 길은 달라도 같은 주소라
/// 한도도 하나다 — 주소 하나에 분에 스무 번 남짓, 넘으면 읽을 수 있는 오류 대신 403 을 준다.
/// 차트 피드를 여섯 개씩 한꺼번에 받으면 열 번째쯤부터 다 403 이 오고, 그 피드의 순위는 통째로
/// 빠진다. 그래서 셋 다 이 줄에 선다.
///
/// 차례를 미리 잡아 두는 방식이라 여럿이 동시에 불러도 3초씩 벌어진다. 403 을 한 번 받으면
/// 줄 전체가 잠시 쉰다 — 막힌 동안 더 두드리면 막힘이 길어진다.
actor ITunesGate {

    static let shared = ITunesGate()

    /// 요청 사이 간격. 긴 확인이 한도 아래에 넉넉히 머문다.
    static let interval: TimeInterval = 3
    /// 403 을 받은 뒤 줄 전체가 쉬는 시간.
    static let coolDown: TimeInterval = 60

    private var nextSlot = Date.distantPast

    /// 내 차례가 올 때까지 기다린다.
    func wait() async throws {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(Self.interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    /// 막혔다 — 다음 차례를 `coolDown` 뒤로 민다.
    func backOff() {
        nextSlot = max(nextSlot, Date().addingTimeInterval(Self.coolDown))
    }
}

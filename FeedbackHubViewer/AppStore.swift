//
//  AppStore.swift
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
    /// The store listing's description. Kept because keyword suggestions read
    /// it; not shown in full anywhere.
    let listing: String?

    var storeURL: URL? { URL(string: "https://apps.apple.com/app/id\(id)") }
}

/// The iTunes Search API, rate-limited and decoded.
///
/// An actor so the interval below actually holds: a check fires one request per
/// keyword and they must queue rather than race.
actor AppStoreDirectory {

    static let shared = AppStoreDirectory()

    /// Apple throttles this endpoint at roughly twenty requests a minute per
    /// address, and answers a burst with 403s rather than an error you can read.
    /// Three seconds keeps a long check comfortably under that, and a check runs
    /// in the background anyway — nobody is watching it tick.
    private static let minimumInterval: TimeInterval = 3

    /// How deep a search reads. 200 is the endpoint's own ceiling, and it is
    /// also about as far down as a rank still means anything.
    static let searchDepth = 200

    private var lastRequest = Date.distantPast

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
            throw http.statusCode == 403 ? Failure.throttled : Failure.badResponse(http.statusCode)
        }
        return try Self.decode(data)
    }

    /// Hold each request `minimumInterval` after the last. Measured from when
    /// the previous one *started*, so a slow response does not add to the wait.
    private func pace() async throws {
        let wait = Self.minimumInterval - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()
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
                iconURL: (item["artworkUrl100"] as? String).flatMap(URL.init(string:)),
                listing: item["description"] as? String)
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// The storefronts a check can ask about. Not an exhaustive list of Apple's —
/// the ones an indie developer plausibly tracks, plus whatever the user types.
enum Storefront {
    /// (code, label) pairs offered in the picker.
    static let common: [(code: String, name: String)] = [
        ("kr", "대한민국"), ("us", "미국"), ("jp", "일본"), ("gb", "영국"),
        ("de", "독일"), ("fr", "프랑스"), ("ca", "캐나다"), ("au", "호주"),
        ("cn", "중국"), ("tw", "대만"), ("hk", "홍콩"), ("sg", "싱가포르"),
        ("mx", "멕시코"), ("br", "브라질"), ("es", "스페인"), ("it", "이탈리아"),
        ("in", "인도"), ("id", "인도네시아"), ("th", "태국"), ("vn", "베트남"),
    ]

    static func name(for code: String) -> String {
        common.first { $0.code == code }?.name
            ?? Locale.current.localizedString(forRegionCode: code)
            ?? code.uppercased()
    }
}

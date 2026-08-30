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
                iconURL: (item["artworkUrl100"] as? String).flatMap(URL.init(string:)))
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Mining candidate search terms out of app names.
///
/// Pure string work, kept apart from the network so it can be reasoned about
/// (and argued with) on its own.
enum KeywordCandidates {

    /// Terms worth trying, taken from the names of the apps that stand in the
    /// same part of the store as yours.
    ///
    /// There is no morphological analysis here. Korean app names are compounds
    /// — "복붙키보드", "문자복사 관리자", "자동 붙여넣기 키보드" — so a tokeniser
    /// that split on spaces would never find "키보드" inside the first of them.
    /// What works instead is agreement: every substring of two to six
    /// characters is counted across the neighbours' names, and the ones that
    /// turn up in several *different* apps are the words the category actually
    /// uses. A fragment only one app uses is that app's branding, not a search
    /// term, which is what `minimum` filters out.
    ///
    /// Overlapping segments collapse into the longest one that covers nearly
    /// the same apps: "키보" and "키보드" each appear in eleven names, and only
    /// one of them is a word.
    ///
    /// None of this decides anything by itself. Every candidate is then put to
    /// the store as a real search, and only the ones the app actually ranks for
    /// are kept — see `KeywordStore.discover(for:)`. That is what keeps this
    /// heuristic honest: it only has to be a good net, not a good judge.
    ///
    /// It does land fragments. "붙여넣기" is written with a space by some apps
    /// and without by others, so "붙여" and "넣기" each turn up in three names
    /// while the whole word turns up in one — and the absorption rule below
    /// cannot reach past a form that never appears. Both fragments then rank,
    /// because the store matches on substrings, and both get kept. Several
    /// rules were tried on real neighbours and none separated "붙여" from
    /// "복사", which is a genuine two-character word: the distinction is not in
    /// the names. Rather than tune a Korean tokeniser against one sample, the
    /// odd row is left for the reader to drop (우클릭 → 추적 중단). A term the
    /// store really does rank you for is never nonsense, only sometimes ugly.
    static func mined(from names: [String], appearingIn minimum: Int = 3,
                      excluding taken: Set<String> = [], limit: Int = 12) -> [String] {
        var owners: [String: Set<String>] = [:]

        for name in names {
            for run in hangulRuns(in: name) {
                let characters = Array(run)
                for length in 2...6 where characters.count >= length {
                    for start in 0...(characters.count - length) {
                        owners[String(characters[start..<(start + length)]), default: []].insert(name)
                    }
                }
            }
            for word in latinWords(in: name) {
                owners[word, default: []].insert(name)
            }
        }

        let shared = owners.filter { $0.value.count >= minimum }
        var kept: [(term: String, apps: Int)] = []
        for (term, apps) in shared {
            // Absorbed by a longer segment that covers nearly the same apps.
            let absorbed = shared.contains { longer, longerApps in
                longer.count > term.count && longer.contains(term)
                    && Double(longerApps.count) >= Double(apps.count) * 0.8
            }
            guard !absorbed, !taken.contains(TrackedKeyword.normalize(term)) else { continue }
            kept.append((term, apps.count))
        }

        kept.sort { $0.apps == $1.apps ? $0.term.count > $1.term.count : $0.apps > $1.apps }
        return kept.prefix(limit).map(\.term)
    }

    /// Runs of Hangul syllables, which is where compounds hide.
    private static func hangulRuns(in name: String) -> [String] {
        name.split(whereSeparator: { !("\u{AC00}"..."\u{D7A3}").contains($0) }).map(String.init)
    }

    /// Latin words long enough to be a search rather than an initialism.
    private static func latinWords(in name: String) -> [String] {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter || !$0.isASCII })
            .filter { $0.count >= 4 }
            .map(String.init)
    }
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

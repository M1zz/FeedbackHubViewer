//
//  ChartFeed.swift
//  FeedbackHubViewer
//
//  Apple 의 공개 차트 피드와 앱 정보 조회. 열쇠도 계정도 필요 없다.
//
//   · 차트: `itunes.apple.com/{나라}/rss/{차트}/limit=200[/genre=ID]/json`
//     한 피드 = 한 나라 × 한 차트의 상위 100위. 순서가 곧 순위다.
//   · 앱 정보: `itunes.apple.com/lookup?id=1,2,3` — 여러 앱을 한 번에. 무료인지 · 장르 ·
//     맥 앱인지를 여기서 안다(`StoreApp` 에는 장르 번호와 가격이 없다).
//
//  키워드 검색(`AppStoreDirectory`)과 같은 주소라 한도도 같다. 그래서 같은 줄(`ITunesGate`)에
//  서서 3초씩 벌려 받는다. 한꺼번에 받으면 몇 개 지나 다 403 이 오고, 그 차트의 순위가
//  "100위 밖" 처럼 보인다. 403 을 받으면 줄이 쉬었다가 두 번까지 다시 묻는다.
//

import Foundation

enum ChartFeed {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// 저절로 하는 확인용. 셀룰러 · 핫스팟 · 저데이터 모드에서는 받지 않는다 — 나라를 많이
    /// 고르면 한 번에 수백 MB 라, 사람이 누르지 않은 확인이 요금제를 먹으면 안 된다.
    private static let thriftySession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: configuration)
    }()

    /// 순위대로 늘어선 앱(0번 == 1위). 그 나라에 그 차트가 없으면 빈 배열.
    /// `thrifty` 면 비싼 네트워크에서는 받지 않고 오류로 끝난다.
    static func ranked(for slot: ChartSlot, thrifty: Bool = false) async throws -> [ChartEntry] {
        guard let url = slot.feedURL else { return [] }
        for attempt in 0...maxRetries {
            try await ITunesGate.shared.wait()
            let (data, response) = try await (thrifty ? thriftySession : session).data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return parse(data) }
            // 없는 나라 · 없는 차트는 404/400 으로 온다 — 오류가 아니라 "차트 없음".
            if http.statusCode == 404 || http.statusCode == 400 { return [] }
            // 403 은 "너무 자주" 다. 줄을 쉬게 하고 다시 줄 선다.
            guard http.statusCode == 403, attempt < maxRetries else { break }
            await ITunesGate.shared.backOff()
        }
        throw URLError(.badServerResponse)
    }

    /// 403 을 받은 피드를 다시 물어볼 횟수.
    private static let maxRetries = 2

    /// `{ "feed": { "entry": [ { "id": { "attributes": { "im:id": "123" } }, "im:name": { "label": … },
    /// "im:artist": { "label": … }, "im:image": [ { "label": url }, … ] } ] } }`.
    /// 항목이 하나뿐이면 `entry` 가 배열이 아니라 객체로 온다.
    static func parse(_ data: Data) -> [ChartEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any] else { return [] }
        let entries: [[String: Any]]
        if let list = feed["entry"] as? [[String: Any]] {
            entries = list
        } else if let single = feed["entry"] as? [String: Any] {
            entries = [single]
        } else {
            return []
        }
        return entries.compactMap { entry in
            guard let id = entry["id"] as? [String: Any],
                  let attributes = id["attributes"] as? [String: Any],
                  let value = attributes["im:id"] as? String,
                  let trackId = Int(value) else { return nil }
            func label(_ key: String) -> String? { (entry[key] as? [String: Any])?["label"] as? String }
            // 아이콘은 53 · 75 · 100 순으로 온다 — 목록 한 줄에는 가장 큰 것도 작다.
            let icon = (entry["im:image"] as? [[String: Any]])?.last?["label"] as? String
            return ChartEntry(trackId: trackId,
                              name: label("im:name") ?? "#\(trackId)",
                              developer: label("im:artist"),
                              iconURL: icon.flatMap(URL.init(string:)))
        }
    }

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let trackId: Int?
            let kind: String?
            let price: Double?
            let primaryGenreId: Int?
            let primaryGenreName: String?
            /// 그 나라 말로 된 장르 이름들, 대표 장르가 먼저. `primaryGenreName` 은 늘 영어다.
            let genres: [String]?
        }
        let results: [Result]
    }

    /// 여러 앱의 차트용 사실을 한 번에. 한 나라 가게에만 있는 앱도 있어 나라를 바꿔 가며
    /// 못 찾은 것만 다시 묻는다.
    static func lookup(_ trackIds: [Int], countries: [String] = ["kr", "us", "jp"]) async -> [Int: ChartApp] {
        var found: [Int: ChartApp] = [:]
        for country in countries {
            let missing = trackIds.filter { found[$0] == nil }
            guard !missing.isEmpty else { break }
            var components = URLComponents(string: "https://itunes.apple.com/lookup")!
            components.queryItems = [
                URLQueryItem(name: "id", value: missing.map(String.init).joined(separator: ",")),
                URLQueryItem(name: "country", value: country),
            ]
            guard let url = components.url,
                  (try? await ITunesGate.shared.wait()) != nil,
                  let (data, _) = try? await session.data(from: url),
                  let decoded = try? JSONDecoder().decode(LookupResponse.self, from: data) else { continue }
            for result in decoded.results {
                guard let id = result.trackId else { continue }
                found[id] = ChartApp(trackId: id,
                                     platform: result.kind == "mac-software" ? .mac : .iphone,
                                     isFree: (result.price ?? 0) == 0,
                                     genreId: result.primaryGenreId,
                                     genreName: result.genres?.first ?? result.primaryGenreName)
            }
        }
        return found
    }
}

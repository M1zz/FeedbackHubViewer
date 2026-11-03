//
//  StoreExposure.swift
//  FeedbackHubViewer
//
//  스토어 어디에 보였나. Apple 은 "투데이 탭 ○○ 스토리에 걸렸다" 를 알려 주지 않는다.
//  그래서 알 수 있는 두 가지로 짐작한다.
//
//  1. 둘러보기 노출이 튄 날 · 나라 — 노출 리포트(`StoreFunnel.browse`).
//     차트 · 에디터 모음 · 비슷한 앱 추천 · 업데이트 목록이 모두 '둘러보기' 하나로 묶인다.
//     여러 나라가 함께 튀면 업데이트일 수 있고, **한 나라만 혼자 튀면** 그 나라 어딘가에
//     걸린 것이다(피처드는 나라별로 걸린다).
//  2. 카테고리 차트 순위 — Apple 이 공개한 순위 피드(나라마다 200위까지).
//     앱이 전체 차트 200위 안이면 그 카테고리 차트에도 반드시 있으므로 카테고리 하나만 본다.
//     ⚠️ 이 피드는 한꺼번에 많이 물으면 한동안 403 으로 막는다(40개 나라 × 앱 여럿에서 막혔다).
//        그래서 그 앱이 실제로 보이는 나라만, 한 번에 둘씩 묻는다.
//

import Foundation

enum StoreExposure {

    // MARK: 둘러보기가 튄 날

    struct Spike: Identifiable, Hashable {
        let date: String
        /// nil 이면 여러 나라가 함께 튄 날.
        let territory: String?
        let count: Int
        /// 앞 14일의 가운데 값.
        let usual: Int
        var id: String { date + (territory ?? "*") }
    }

    /// 최근 것부터. 앞 기록이 1주가 안 되는 날은 견줄 것이 없어 보지 않는다.
    static func spikes(_ browse: [String: [String: Int]]) -> [Spike] {
        let days = browse.keys.sorted()
        let total = days.map { browse[$0]?.values.reduce(0, +) ?? 0 }
        let territories = Set(browse.values.flatMap(\.keys))
        var found: [Spike] = []

        for (i, day) in days.enumerated() where i >= 7 {
            let window = max(0, i - 14)..<i
            let usual = median(total[window])
            let ratio = Double(total[i]) / Double(max(usual, 1))
            if total[i] >= max(20, usual * 3) {
                found.append(Spike(date: day, territory: nil, count: total[i], usual: usual))
            }
            for territory in territories {
                let count = browse[day]?[territory] ?? 0
                let base = max(median(days[window].map { browse[$0]?[territory] ?? 0 }), 3)
                // 그 나라만 유난히: 평소의 5배이면서, 전체가 늘어난 것보다 2.5배 넘게.
                if count >= 30, count >= base * 5, Double(count) / Double(base) > ratio * 2.5 {
                    found.append(Spike(date: day, territory: territory, count: count, usual: base))
                }
            }
        }
        return found.sorted { ($0.date, $0.count) > ($1.date, $1.count) }
    }

    private static func median<C: Collection>(_ values: C) -> Int where C.Element == Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    // MARK: 차트 순위

    struct ChartRank: Identifiable, Hashable {
        let country: String
        let rank: Int
        let chart: String
        var id: String { country }
    }

    /// 볼 나라: 한국 · 미국과, 둘러보기 노출이 많은 나라 순으로 모두 10개까지(소문자 코드).
    static func countries(_ browse: [String: [String: Int]]) -> [String] {
        var seen = browse.values.reduce(into: [String: Int]()) { sum, day in
            for (territory, count) in day { sum[territory, default: 0] += count }
        }
        seen["KR", default: 0] += .max / 4
        seen["US", default: 0] += .max / 4
        return seen.sorted { $0.value > $1.value }.prefix(10).map { $0.key.lowercased() }
    }

    /// 나라마다 그 앱 카테고리의 무료(유료면 유료) 차트를 본다. 순위가 높은 것부터.
    /// 스토어에 없는 앱이면 빈 목록. 피드가 막혀 한 나라도 못 읽었으면 nil.
    static func chartRanks(bundleID: String, countries: [String]) async -> [ChartRank]? {
        guard let app = await lookup(bundleID: bundleID) else { return [] }
        let feed = (app.isFree ? "topfree" : "toppaid") + (app.isMac ? "macapps" : "applications")
        var ranks: [ChartRank] = []
        var read = 0
        for pair in stride(from: 0, to: countries.count, by: 2).map({ Array(countries[$0..<min($0 + 2, countries.count)]) }) {
            await withTaskGroup(of: (String, [String]?).self) { group in
                for country in pair {
                    group.addTask {
                        let url = URL(string: "https://itunes.apple.com/\(country)/rss/\(feed)/limit=200/genre=\(app.genreID)/json")!
                        return (country, await feedIDs(url))
                    }
                }
                for await (country, ids) in group {
                    guard let ids else { continue }
                    read += 1
                    if let index = ids.firstIndex(of: app.id) {
                        ranks.append(ChartRank(country: country.uppercased(), rank: index + 1, chart: app.genreName))
                    }
                }
            }
        }
        return read == 0 ? nil : ranks.sorted { $0.rank < $1.rank }
    }

    private struct App {
        let id: String
        let genreID: Int
        let genreName: String
        let isMac: Bool
        let isFree: Bool
    }

    private static func lookup(bundleID: String) async -> App? {
        for country in ["kr", "us"] {
            var parts = URLComponents(string: "https://itunes.apple.com/lookup")!
            parts.queryItems = [.init(name: "bundleId", value: bundleID), .init(name: "country", value: country)]
            guard let (data, _) = try? await URLSession.shared.data(from: parts.url!),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = (json["results"] as? [[String: Any]])?.first,
                  let id = result["trackId"] as? Int,
                  let genre = result["primaryGenreId"] as? Int else { continue }
            return App(id: String(id), genreID: genre,
                       genreName: result["primaryGenreName"] as? String ?? "",
                       isMac: (result["kind"] as? String) == "mac-software",
                       isFree: ((result["price"] as? Double) ?? 0) == 0)
        }
        return nil
    }

    /// 피드의 앱 id 들. 순위 피드는 가끔 403 을 내서 한 번 더 묻는다.
    private static func feedIDs(_ url: URL) async -> [String]? {
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let feed = json["feed"] as? [String: Any] else { continue }
            // 한 개뿐이면 배열이 아니라 객체로 온다.
            let entries = feed["entry"] as? [[String: Any]] ?? (feed["entry"] as? [String: Any]).map { [$0] } ?? []
            return entries.compactMap { (($0["id"] as? [String: Any])?["attributes"] as? [String: Any])?["im:id"] as? String }
        }
        return nil
    }
}

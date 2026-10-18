//
//  ChartRanks.swift
//  FeedbackHubViewer
//
//  App Store 인기 차트에서 내 앱이 나라마다 몇 위인가 — 그 기록.
//
//  키워드 순위(`KeywordHistory`)와 다른 물음이다. 키워드는 "이 말로 찾으면 몇 번째로
//  나오나", 차트는 "그 나라 사람들이 지금 이 앱을 얼마나 받고 있나" 다. 차트에 든다는
//  것은 검색과 상관없이 스토어 첫 화면 쪽에서 보인다는 뜻이기도 하다.
//
//  읽는 곳은 Apple 의 공개 RSS 차트 피드(`ChartFeed`)이고, 한 피드는 한 나라 × 한 차트의
//  **상위 100위**다(피드 주소는 200을 받지만 실제로는 100개만 온다). 그래서 기록에 없는
//  것은 "100위 밖" 이지 "모름" 이 아니다 — 그 나라를 확인했을 때에 한해서.
//
//  기록은 확인할 때마다 한 장(`ChartScan`)이고, 차트에 든 것만 적는다. 100위 밖을 다
//  적으면 앱 × 나라 × 차트만큼 커지는데 거기서 알 수 있는 것은 "없었다" 하나뿐이다.
//  대신 그 확인이 **어느 나라를 봤는지**는 적는다 — 그래야 "빠졌다" 와 "안 봤다" 를
//  가를 수 있다.
//

import Foundation

/// 차트 종류. 무료 앱은 유료 차트에 들 수 없고 그 반대도 같다.
enum ChartKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case free, paid, grossing
    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "무료"
        case .paid: "유료"
        case .grossing: "매출"
        }
    }
}

/// 어느 기기의 차트인가. 아이패드 차트는 아이폰 차트와 거의 겹쳐서 받지 않는다.
enum ChartPlatform: String, Codable, Hashable {
    case iphone, mac

    var label: String {
        switch self {
        case .iphone: "iPhone"
        case .mac: "Mac"
        }
    }
}

/// 차트 한 칸: 기기 × 종류 × 장르(nil 이면 전체) × 나라.
struct ChartSlot: Codable, Hashable {
    let platform: ChartPlatform
    let kind: ChartKind
    /// nil == 전체 차트. 값이 있으면 그 장르(카테고리) 차트.
    let genreId: Int?
    let country: String

    var isOverall: Bool { genreId == nil }

    /// Apple 의 옛 RSS 차트 피드 주소.
    var feedURL: URL? {
        var path = "https://itunes.apple.com/\(country)/rss/\(feedName)/limit=200"
        if let genreId { path += "/genre=\(genreId)" }
        return URL(string: path + "/json")
    }

    private var feedName: String {
        switch (kind, platform) {
        case (.free, .iphone): "topfreeapplications"
        case (.paid, .iphone): "toppaidapplications"
        case (.grossing, .iphone): "topgrossingapplications"
        case (.free, .mac): "topfreemacapps"
        case (.paid, .mac): "toppaidmacapps"
        case (.grossing, .mac): "topgrossingmacapps"
        }
    }
}

/// 차트에 든 것 하나.
struct ChartHit: Codable, Hashable {
    let trackId: Int
    let slot: ChartSlot
    let rank: Int
}

/// 한 번의 확인.
struct ChartScan: Codable {
    let date: Date
    /// 이번에 본 나라. 여기 없는 나라의 "없음" 은 100위 밖이 아니라 안 본 것이다.
    let countries: [String]
    let hits: [ChartHit]
    /// 받지 못한 피드 수. 0이 아니면 이번 확인의 "없음" 중 일부는 모르는 것이다.
    let failedFeeds: Int
    /// 받지 못한 차트 칸. 여기 든 칸의 순위는 이번에 본 것이 아니라 직전 확인에서 이어 쓴
    /// 것이다(`ChartHistory.carryingOver`). 이 칸이 생기기 전 기록은 nil.
    var failedSlots: [ChartSlot]?
}

/// 차트를 고르는 데 필요한 앱의 사실 — 기기, 무료인지, 장르. `iTunes lookup` 이 준다.
struct ChartApp: Codable, Hashable {
    let trackId: Int
    let platform: ChartPlatform
    let isFree: Bool
    let genreId: Int?
    let genreName: String?

    /// 이 앱이 들 수 있는 차트 종류.
    var kinds: [ChartKind] { isFree ? [.free, .grossing] : [.paid, .grossing] }
}

/// 직전 확인과 견준 움직임.
enum ChartMove: Hashable {
    /// 직전에 그 나라를 봤는데 100위 안에 없었다.
    case entered
    case up(Int)
    case down(Int)
    case same
    /// 견줄 확인이 없다(처음이거나, 직전에 그 나라를 안 봤다).
    case unknown
}

struct ChartHistory: Codable {
    var apps: [Int: ChartApp] = [:]
    /// 오래된 것부터.
    var scans: [ChartScan] = []

    /// 남겨 둘 기간. 순위는 며칠 단위로 움직이고, 석 달이면 "가장 좋았던 때" 를 말하기에 충분하다.
    static let keepDays = 90

    var lastScan: ChartScan? { scans.last }

    /// 가장 최근 확인에서 이 앱이 든 차트, 높은 순위부터.
    func current(for trackId: Int) -> [ChartHit] {
        (lastScan?.hits ?? [])
            .filter { $0.trackId == trackId }
            .sorted { ($0.rank, $0.slot.country) < ($1.rank, $1.slot.country) }
    }

    /// 지금 어느 차트든(전체 · 카테고리) 든 나라 수. 카테고리 차트만 든 앱을 "0개국" 이라고
    /// 하면 48위가 옆에 있는데 0이라고 말하게 된다.
    func countriesRanked(for trackId: Int) -> Int {
        Set(current(for: trackId).map(\.slot.country)).count
    }

    /// 지금 나라마다 가장 높은 자리, 높은 나라부터. 앱 목록의 "🇰🇷 48위 · 🇯🇵 72위" 가 이것이다.
    func bestByCountry(for trackId: Int) -> [ChartHit] {
        var best: [String: ChartHit] = [:]
        for hit in current(for: trackId) where (best[hit.slot.country]?.rank ?? .max) > hit.rank {
            best[hit.slot.country] = hit
        }
        return best.values.sorted { ($0.rank, $0.slot.country) < ($1.rank, $1.slot.country) }
    }

    /// 지금 가장 높은 자리.
    func bestCurrent(for trackId: Int) -> ChartHit? {
        current(for: trackId).min { $0.rank < $1.rank }
    }

    /// 직전 확인과 견준 움직임.
    func move(of hit: ChartHit) -> ChartMove {
        guard scans.count >= 2 else { return .unknown }
        let previous = scans[scans.count - 2]
        guard previous.countries.contains(hit.slot.country) else { return .unknown }
        // 못 받은 칸을 적지 않던 때의 기록은, 피드를 놓쳤으면 "없었다" 를 믿을 수 없다.
        guard previous.failedFeeds == 0 || previous.failedSlots != nil else { return .unknown }
        guard let before = previous.hits.first(where: { $0.trackId == hit.trackId && $0.slot == hit.slot }) else {
            return .entered
        }
        if before.rank == hit.rank { return .same }
        return before.rank > hit.rank ? .up(before.rank - hit.rank) : .down(hit.rank - before.rank)
    }

    /// 직전에는 들었는데 이번에 빠진 차트 — 이번에도 그 나라를 봤을 때만, 그리고 그 차트를
    /// 이번에 실제로 받았을 때만. 못 받은 차트는 빠진 게 아니라 모르는 것이다.
    func dropped(for trackId: Int) -> [ChartHit] {
        guard scans.count >= 2, let last = lastScan else { return [] }
        let now = Set(last.hits.filter { $0.trackId == trackId }.map(\.slot))
        let unknown = Set(last.failedSlots ?? [])
        // 직전 확인이 피드를 놓치고도 어느 칸인지 적지 않았다면 견줄 수 없다 — 이번 기록이 옛 것이면 마찬가지.
        guard last.failedFeeds == 0 || last.failedSlots != nil else { return [] }
        return scans[scans.count - 2].hits.filter {
            $0.trackId == trackId && last.countries.contains($0.slot.country)
                && !now.contains($0.slot) && !unknown.contains($0.slot)
        }
    }

    /// 이번 확인에서 받지 못한 칸의 순위를 직전 확인에서 이어 쓴다. 못 받은 차트를 "없음" 으로
    /// 적으면 순위가 다 빠진 것처럼 보이고, 다음 확인에서는 "새로 들어갔다" 가 된다.
    func carryingOver(failed: [ChartSlot], into hits: [ChartHit]) -> [ChartHit] {
        guard !failed.isEmpty, let previous = lastScan else { return hits }
        let failed = Set(failed)
        return hits + previous.hits.filter { failed.contains($0.slot) }
    }

    /// 최근 `days` 일 동안 차트 칸마다 가장 높았던 자리와 그날.
    func best(for trackId: Int, days: Int) -> [(hit: ChartHit, date: Date)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        var best: [ChartSlot: (hit: ChartHit, date: Date)] = [:]
        for scan in scans where scan.date >= cutoff {
            for hit in scan.hits where hit.trackId == trackId {
                if let kept = best[hit.slot], kept.hit.rank <= hit.rank { continue }
                best[hit.slot] = (hit, scan.date)
            }
        }
        return best.values.sorted { ($0.hit.rank, $0.hit.slot.country) < ($1.hit.rank, $1.hit.slot.country) }
    }

    mutating func record(_ scan: ChartScan) {
        scans.append(scan)
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: .now) ?? .distantPast
        scans.removeAll { $0.date < cutoff }
    }
}

/// App Store 나라 코드와 그 이름 · 국기.
enum ChartStorefronts {
    /// 처음 켰을 때 볼 나라. 피드 하나가 압축해도 140KB 남짓이라 나라를 늘릴수록 확인이
    /// 무거워진다 — 필요한 나라는 화면에서 더한다.
    static let defaults = ["kr", "us", "jp", "tw", "gb", "de"]

    /// 고를 수 있는 나라 — App Store 가 있는 나라 전부, 큰 시장부터. Apple 이 차트를 안
    /// 내는 나라는 피드가 비어 오고(`ChartFeed.rankedIDs`), 그건 "100위 밖" 과 같다.
    static let all = [
        "kr", "us", "jp", "cn", "tw", "hk", "sg", "my", "th", "vn", "id", "ph", "in", "au", "nz",
        "gb", "ie", "fr", "de", "at", "ch", "it", "es", "pt", "nl", "be", "lu", "dk", "se", "no", "fi",
        "is", "pl", "cz", "sk", "hu", "ro", "bg", "gr", "hr", "si", "rs", "ua", "tr", "il", "ae", "sa",
        "qa", "kw", "eg", "za", "ng", "ke", "ca", "mx", "br", "ar", "cl", "co", "pe", "ec", "uy", "pa",
        "cr", "do", "gt", "ru", "kz", "pk", "bd", "lk", "np", "mn", "kh", "la", "mo", "bn", "mt", "cy",
        "ee", "lv", "lt", "by", "md", "al", "mk", "ba", "me", "ge", "am", "az", "uz", "kg", "tj", "tm",
        "jo", "lb", "om", "bh", "iq", "ye", "ma", "dz", "tn", "ly", "gh", "ci", "sn", "cm", "tz", "ug",
        "zw", "mz", "zm", "mw", "bw", "na", "mu", "sc", "mg", "ao", "cd", "ga", "ne", "ml", "bf", "td",
        "bj", "tg", "sl", "lr", "gm", "gw", "cv", "st", "gq", "cg", "rw", "bi", "dj", "sz", "ls", "bz",
        "hn", "ni", "sv", "jm", "tt", "bb", "bs", "bm", "ky", "ag", "dm", "gd", "kn", "lc", "vc", "sr",
        "gy", "bo", "py", "ve", "fj", "pg", "sb", "vu", "to", "ws", "fm", "pw", "mv", "bt", "af", "mm",
    ]

    /// 피드 하나의 대략 크기(압축해서 받는 양). 확인이 얼마나 무거운지 미리 말하는 데 쓴다.
    static let approximateFeedBytes = 140_000

    /// "🇰🇷 48위 · 🇯🇵 72위 +2" — 나라마다 가장 높은 자리, 높은 것부터 `limit` 개.
    static func summary(_ hits: [ChartHit], limit: Int = 3) -> String {
        let shown = hits.prefix(limit).map { "\(flag($0.slot.country)) \($0.rank)위" }
        let rest = hits.count - shown.count
        return shown.joined(separator: " · ") + (rest > 0 ? " +\(rest)" : "")
    }

    static func name(_ code: String) -> String {
        Locale(identifier: "ko_KR").localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

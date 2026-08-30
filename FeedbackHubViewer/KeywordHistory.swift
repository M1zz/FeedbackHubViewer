//
//  KeywordHistory.swift
//  FeedbackHubViewer
//
//  What every keyword check saw, kept by day.
//
//  Deliberately *not* built like `UsageRollups`. The event stream needed a day
//  ladder because it grows without bound — thousands of records a day, forever.
//  A keyword grows by one entry a day. A hundred keywords tracked for five
//  years is under two hundred thousand small values, and a week or a month of
//  it is a handful of dictionary reads. Adding a week/month ladder here would
//  be machinery for a cost that does not exist; the days are read directly.
//
//  A rank is also not a sum, which is the other reason the shapes differ. Two
//  days of events add up; two days of "18위" do not. What a period means for a
//  rank is its best, its latest and its direction — computed on read, from the
//  days, because that is cheap and leaves one definition rather than two.
//

import Foundation

/// One keyword in one storefront: the unit a check asks about, and the unit a
/// search request answers.
struct TrackedKeyword: Codable, Hashable, Identifiable {
    var term: String
    /// Storefront code — "kr", "us".
    var country: String
    /// The hub's project keys (bundle ids) this term was added for. A term two
    /// apps both want is still one search; this only decides whose screen it
    /// shows up on.
    var projects: Set<String> = []

    /// Case- and space-insensitive, because "클립 보드" and "클립보드" reach the
    /// same search but "Clipboard" and "clipboard" are the same keyword.
    var id: String { "\(country)/\(TrackedKeyword.normalize(term))" }

    static func normalize(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What one search returned, on one day.
struct KeywordCheck: Codable {
    var checkedAt: Date
    /// trackId (as a string, so the JSON stays readable) → 1-based position in
    /// the results. An app missing from this map was not in the window that was
    /// read — `resultCount` says how deep that window went.
    var ranks: [String: Int] = [:]
    /// The results in order, as far as `KeywordHistory.competitorDepth`. This
    /// is where competitors come from: whoever the store puts above you for a
    /// term you care about is, by definition, who you are up against.
    var top: [Int] = []
    /// How many results the store returned at all, so "안 잡힘" can say out of
    /// how many rather than leaving it open.
    var resultCount: Int = 0

    func rank(of trackId: Int) -> Int? { ranks[String(trackId)] }
}

/// One keyword's numbers for a scope, ready to put in a row.
struct KeywordStanding {
    let keyword: TrackedKeyword
    /// Today's rank, or the most recent one if today has not been checked.
    let rank: Int?
    /// When that rank was seen.
    let seenAt: Date?
    /// Change against the previous *different* day that was checked. Negative
    /// is an improvement — 30위에서 12위로 가면 −18.
    let delta: Int?
    /// The best rank ever recorded for this app on this keyword.
    let best: Int?
    /// The last 30 days, oldest first, `nil` where the day was not checked or
    /// the app was not in the results. What the sparkline draws.
    let recent: [Int?]
    /// How many results the store returned on the latest check.
    let resultCount: Int

    var isRanked: Bool { rank != nil }
}

/// Every check, per keyword, per day. Its own file — it has nothing to do with
/// the CloudKit hub and must not be thrown away when that cache is.
struct KeywordHistory: Codable {

    static let currentVersion = 1

    /// How much of each search result list is kept. Deep enough that a
    /// competitor two pages down still shows up, shallow enough that a year of
    /// daily checks stays a small file.
    static let competitorDepth = 30

    var version = KeywordHistory.currentVersion

    /// The terms being tracked, keyed by `TrackedKeyword.id`.
    var keywords: [String: TrackedKeyword] = [:]
    /// keyword id → day key ("yyyy-MM-dd") → what that day's check saw.
    var checks: [String: [String: KeywordCheck]] = [:]
    /// trackId (as a string) → the app as it was last seen. Kept so a
    /// competitor has a name and an icon without a second lookup, and so a
    /// competitor that later leaves the store still has a label.
    var apps: [String: StoreApp] = [:]
    /// The hub's project key (bundle id) → its App Store trackId, once
    /// resolved. Absent means "not on the store, or not looked up yet".
    var links: [String: Int] = [:]
    /// When a full check last finished.
    var lastCheckedAt: Date?

    var isEmpty: Bool { keywords.isEmpty }

    // MARK: - Editing

    mutating func add(term: String, country: String, for project: String?) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var keyword = TrackedKeyword(term: trimmed, country: country)
        if var existing = keywords[keyword.id] {
            if let project { existing.projects.insert(project) }
            keywords[keyword.id] = existing
            return
        }
        if let project { keyword.projects = [project] }
        keywords[keyword.id] = keyword
    }

    /// Take a term off one app's screen; drop it entirely once no app wants it,
    /// along with the history nothing is left to show.
    mutating func remove(_ keyword: TrackedKeyword, from project: String?) {
        guard var existing = keywords[keyword.id] else { return }
        if let project { existing.projects.remove(project) }
        if project == nil || existing.projects.isEmpty {
            keywords[keyword.id] = nil
            checks[keyword.id] = nil
        } else {
            keywords[keyword.id] = existing
        }
    }

    /// File one search's outcome under today.
    ///
    /// One check per day wins: a term checked twice in a day replaces the
    /// earlier entry rather than growing the file, and every reader can then
    /// assume "a day is at most one number".
    mutating func record(_ keyword: TrackedKeyword, results: [StoreApp],
                         mine: Set<Int>, at now: Date = Date(),
                         calendar: Calendar = .current) {
        var check = KeywordCheck(checkedAt: now, resultCount: results.count)
        for (index, app) in results.enumerated() {
            let position = index + 1
            if mine.contains(app.id) { check.ranks[String(app.id)] = position }
            if position <= Self.competitorDepth {
                check.top.append(app.id)
                apps[String(app.id)] = app
            }
        }
        checks[keyword.id, default: [:]][UsageRollups.dayKey(now, calendar: calendar)] = check
    }

    // MARK: - Reading

    /// The keywords on one app's screen. `nil` scope is every tracked term.
    func keywords(for project: String?) -> [TrackedKeyword] {
        keywords.values
            .filter { project.map($0.projects.contains) ?? true }
            .sorted { ($0.country, $0.term) < ($1.country, $1.term) }
    }

    /// Every storefront any tracked term names, so the picker can show what is
    /// actually in use rather than what was once configured.
    var countriesInUse: [String] {
        Set(keywords.values.map(\.country)).sorted()
    }

    /// One keyword's row for one app, read straight out of the days.
    func standing(_ keyword: TrackedKeyword, trackId: Int?,
                  days: Int = 30, calendar: Calendar = .current,
                  now: Date = Date()) -> KeywordStanding {
        let history = checks[keyword.id] ?? [:]
        guard let trackId else {
            return KeywordStanding(keyword: keyword, rank: nil, seenAt: nil, delta: nil,
                                   best: nil, recent: Array(repeating: nil, count: days),
                                   resultCount: 0)
        }

        // Newest first, so "latest" and "the one before it" are the first two
        // entries that actually hold a rank.
        let ordered = history.sorted { $0.key > $1.key }
        let latest = ordered.first
        let ranked = ordered.compactMap { entry -> (day: String, rank: Int)? in
            guard let rank = entry.value.rank(of: trackId) else { return nil }
            return (entry.key, rank)
        }
        let current = ranked.first
        // Against the previous day that produced a rank, not the previous day
        // outright: a check the network ate should not read as "떨어짐".
        let previous = ranked.dropFirst().first
        let delta = current.flatMap { now in previous.map { now.rank - $0.rank } }

        let axis = UsageRollups.recentDayKeys(days, calendar: calendar, endingAt: now)
        let recent = axis.map { history[$0.key]?.rank(of: trackId) }

        return KeywordStanding(keyword: keyword,
                               rank: current?.rank,
                               seenAt: current.flatMap { history[$0.day]?.checkedAt },
                               delta: delta,
                               best: ranked.map(\.rank).min(),
                               recent: recent,
                               resultCount: latest?.value.resultCount ?? 0)
    }

    /// The latest check for a keyword, whichever day it landed on.
    func latestCheck(_ keyword: TrackedKeyword) -> KeywordCheck? {
        checks[keyword.id]?.max { $0.key < $1.key }?.value
    }

    /// Who you keep running into.
    ///
    /// Counted over the latest check of each of this app's keywords: how many
    /// of them an app appears in, and how often it is *above* you. Ranking
    /// above you on a term you care about is the whole definition of a
    /// competitor here — it is measured, not guessed at from a genre.
    func competitors(for project: String?, trackId: Int?, limit: Int = 20) -> [CompetitorStanding] {
        /// What one rival has accumulated across this app's keywords so far.
        struct Tally {
            var keywords = 0
            var above = 0
            var best = Int.max
            var terms: [String] = []
        }

        var appearances: [Int: Tally] = [:]
        for keyword in keywords(for: project) {
            guard let check = latestCheck(keyword) else { continue }
            let mine: Int? = trackId.flatMap { check.rank(of: $0) }
            for (index, id) in check.top.enumerated() where id != trackId {
                let position = index + 1
                var tally = appearances[id] ?? Tally()
                tally.keywords += 1
                if let mine, position < mine { tally.above += 1 }
                tally.best = min(tally.best, position)
                tally.terms.append(keyword.term)
                appearances[id] = tally
            }
        }

        var standings: [CompetitorStanding] = []
        for (id, tally) in appearances {
            guard let app = apps[String(id)] else { continue }
            standings.append(CompetitorStanding(app: app,
                                                keywords: tally.keywords,
                                                timesAbove: tally.above,
                                                bestRank: tally.best,
                                                terms: tally.terms.sorted()))
        }
        // Above you on the most terms first; then seen on the most terms; then
        // whoever got closest to the top.
        standings.sort { lhs, rhs in
            if lhs.timesAbove != rhs.timesAbove { return lhs.timesAbove > rhs.timesAbove }
            if lhs.keywords != rhs.keywords { return lhs.keywords > rhs.keywords }
            return lhs.bestRank < rhs.bestRank
        }
        return Array(standings.prefix(limit))
    }
}

/// One rival, as the checks actually saw it.
struct CompetitorStanding: Identifiable {
    var id: Int { app.id }
    let app: StoreApp
    /// How many of this app's keywords it turned up in.
    let keywords: Int
    /// How many of those it was ranked above you on.
    let timesAbove: Int
    /// Its best position across those keywords.
    let bestRank: Int
    /// Which terms, so the number is checkable rather than taken on trust.
    let terms: [String]
}

/// Reads and writes `KeywordHistory`.
///
/// Not tied to a CloudKit environment, unlike the hub cache: a Development
/// build and a Production build read the same App Store, and rank history that
/// vanished when you switched schemes would be worse than useless.
actor KeywordCache {

    static let shared = KeywordCache()

    private static let fileName = "keywords"

    private var fileURL: URL? { CacheFile.url(Self.fileName) }

    nonisolated static func saveNow(_ history: KeywordHistory) {
        CacheFile.write(history, to: CacheFile.url(fileName))
    }

    func load() -> KeywordHistory? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let history = try? JSONDecoder().decode(KeywordHistory.self, from: data),
              history.version == KeywordHistory.currentVersion else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return history
    }

    func save(_ history: KeywordHistory) {
        CacheFile.write(history, to: fileURL)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

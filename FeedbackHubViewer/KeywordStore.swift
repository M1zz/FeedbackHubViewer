//
//  KeywordStore.swift
//  FeedbackHubViewer
//
//  Observable state for the 키워드 screen: which terms are tracked, what the
//  last check saw, and the check itself.
//
//  Kept apart from `FeedbackStore` on purpose. That store owns one CloudKit
//  container and everything in it; this one owns a public HTTP API and a file
//  of its own, and the two have nothing to say to each other but a list of
//  bundle ids. Folding them together would mean a keyword check invalidating
//  the hub's derived numbers, and a CloudKit permission error blanking the
//  rank history — neither of which makes any sense.
//
//  A check is one pass:
//
//    1. resolve — bundle ids the hub knows → App Store apps, one request per
//       storefront, and only for ids not already linked.
//    2. search — one request per (키워드, 국가), *deduplicated*: two apps
//       tracking "메모" in kr is one search, and every app's position is read
//       out of the same result list.
//    3. record — the day's entry per keyword, then one write to disk.
//
//  Which is why the cost of a check is the number of terms, not the number of
//  apps times the number of terms.
//

import Foundation
import SwiftUI

@MainActor
final class KeywordStore: ObservableObject {

    /// Everything tracked, and everything ever seen.
    @Published private(set) var history = KeywordHistory()
    @Published private(set) var isChecking = false
    @Published private(set) var progress: CheckProgress?
    @Published var errorMessage: String?

    /// Storefronts offered when adding a term. Seeded from what is already
    /// tracked so the picker matches the data, and persisted as a plain
    /// preference — it is a UI choice, not part of the history.
    @Published var countries: [String] {
        didSet { UserDefaults.standard.set(countries, forKey: Self.countriesKey) }
    }

    private static let countriesKey = "keywordCountries"
    private static let lastCheckDayKey = "keywordLastCheckDay"

    private let directory = AppStoreDirectory.shared
    private var checkTask: Task<Void, Never>?
    private var loaded = false

    /// How far along a check is. Searches are the only slow part and there are
    /// exactly as many as there are distinct terms, so unlike the CloudKit
    /// refresh this one really does have a denominator.
    struct CheckProgress: Equatable {
        var done: Int
        var total: Int
        var term: String

        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
        var text: String { "\(term) 확인 중… (\(done)/\(total))" }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.countriesKey)
        countries = saved?.isEmpty == false ? saved! : ["kr"]
    }

    // MARK: - Lifecycle

    /// Paint what the last check saw, then check today's ranks if today has not
    /// been checked yet.
    ///
    /// Ranks move on a scale of days, and a check costs one HTTP request per
    /// term; running it on every launch would spend that budget for numbers
    /// that cannot have changed. Once a day is the honest cadence.
    func start(bundleIds: [String]) {
        guard !loaded else { return }
        loaded = true
        Task { [weak self] in
            guard let self else { return }
            if let restored = await KeywordCache.shared.load() { self.history = restored }
            var countries = self.countries
            for country in self.history.countriesInUse where !countries.contains(country) {
                countries.append(country)
            }
            self.countries = countries
            guard self.needsDailyCheck else { return }
            self.check(bundleIds: bundleIds)
        }
    }

    /// Whether today's check has run. Stored as a day key rather than a date so
    /// "오늘" means the calendar day, matching how the history is filed.
    private var needsDailyCheck: Bool {
        guard !history.keywords.isEmpty else { return false }
        let today = UsageRollups.dayKey(Date())
        return UserDefaults.standard.string(forKey: Self.lastCheckDayKey) != today
    }

    // MARK: - Checking

    /// Look up every tracked term. `bundleIds` is the hub's project list — the
    /// apps whose positions are read out of each result list.
    func check(bundleIds: [String]) {
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            await self?.runCheck(bundleIds: bundleIds)
            self?.checkTask = nil
        }
    }

    func cancelCheck() {
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        progress = nil
    }

    private func runCheck(bundleIds: [String]) async {
        isChecking = true
        errorMessage = nil
        defer {
            isChecking = false
            progress = nil
        }

        await resolveLinks(bundleIds: bundleIds)
        let mine = Set(history.links.values)
        // Every rank this pass could record would be empty, and it would then
        // mark today as checked and not try again until tomorrow. Better to do
        // nothing and let the next attempt — once the hub has its apps — count.
        guard !mine.isEmpty else {
            errorMessage = "App Store에서 앱을 아직 찾지 못했습니다. 허브가 앱 목록을 읽은 뒤 다시 시도하세요."
            return
        }

        // Deduplicated by `TrackedKeyword.id`, which is (country, normalised
        // term) — the unit a search request actually answers. Two apps tracking
        // the same term in the same storefront cost one request between them.
        let terms = history.keywords.values.sorted { ($0.country, $0.term) < ($1.country, $1.term) }
        guard !terms.isEmpty else { return }

        var failures = 0
        for (index, keyword) in terms.enumerated() {
            guard !Task.isCancelled else { return }
            progress = CheckProgress(done: index, total: terms.count, term: keyword.term)
            do {
                let results = try await directory.search(term: keyword.term, country: keyword.country)
                history.record(keyword, results: results, mine: mine)
            } catch is CancellationError {
                return
            } catch {
                // One term the store would not answer for must not throw away
                // the rest of the pass, or a single throttled request costs a
                // day of history for everything after it.
                failures += 1
                if errorMessage == nil { errorMessage = error.localizedDescription }
            }
            // Written as it goes: a check is minutes long at three seconds a
            // term, and quitting halfway should keep what it already learned.
            if index % 10 == 9 { persist() }
        }

        history.lastCheckedAt = Date()
        if failures < terms.count {
            UserDefaults.standard.set(UsageRollups.dayKey(Date()), forKey: Self.lastCheckDayKey)
        }
        if failures > 0 {
            errorMessage = "키워드 \(failures)개는 확인하지 못했습니다. " + (errorMessage ?? "")
        }
        persist()
    }

    /// Turn bundle ids into App Store apps, for the ids not already linked.
    ///
    /// Looked up in the first tracked storefront: an app is the same `trackId`
    /// in every store it is sold in, so one storefront answers for all of them.
    /// An id that resolves nowhere is simply an app that is not on the App
    /// Store — a Development-only build, or one still in review.
    private func resolveLinks(bundleIds: [String]) async {
        let unlinked = bundleIds.filter { history.links[$0] == nil }
        guard !unlinked.isEmpty else { return }
        let country = countries.first ?? "kr"
        do {
            let apps = try await directory.lookup(bundleIds: unlinked, country: country)
            for app in apps {
                guard let bundleId = app.bundleId else { continue }
                history.links[bundleId] = app.id
                history.apps[String(app.id)] = app
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-read every app's store listing, whether or not it is already linked —
    /// what the 새로고침 button does when a name or rating has moved.
    func refreshLinks(bundleIds: [String]) {
        Task { [weak self] in
            guard let self else { return }
            let country = self.countries.first ?? "kr"
            do {
                let apps = try await self.directory.lookup(bundleIds: bundleIds, country: country)
                for app in apps {
                    guard let bundleId = app.bundleId else { continue }
                    self.history.links[bundleId] = app.id
                    self.history.apps[String(app.id)] = app
                }
                self.persist()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Editing

    func add(term: String, countries terms: [String], for project: String?) {
        for country in terms { history.add(term: term, country: country, for: project) }
        persist()
    }

    func remove(_ keyword: TrackedKeyword, from project: String?) {
        history.remove(keyword, from: project)
        persist()
    }

    /// Check one term on the spot — what the row's own refresh does, and what
    /// a term added just now needs so the screen is not blank until tomorrow.
    func checkNow(_ keyword: TrackedKeyword) {
        Task { [weak self] in
            guard let self else { return }
            let mine = Set(self.history.links.values)
            do {
                let results = try await self.directory.search(term: keyword.term,
                                                              country: keyword.country)
                self.history.record(keyword, results: results, mine: mine)
                self.persist()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Reading

    /// The App Store app behind one of the hub's projects, if it is on the
    /// store at all.
    func storeApp(for project: String) -> StoreApp? {
        guard let trackId = history.links[project] else { return nil }
        return history.apps[String(trackId)]
    }

    func trackId(for project: String?) -> Int? {
        project.flatMap { history.links[$0] }
    }

    /// One app's keyword rows, ranked ones first — the ones with a number are
    /// what you came to look at, and the unranked ones are the work list.
    func standings(for project: String?) -> [KeywordStanding] {
        let trackId = trackId(for: project)
        return history.keywords(for: project)
            .map { history.standing($0, trackId: trackId) }
            .sorted { lhs, rhs in
                switch (lhs.rank, rhs.rank) {
                case let (l?, r?): return l == r ? lhs.keyword.term < rhs.keyword.term : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                default:           return lhs.keyword.term < rhs.keyword.term
                }
            }
    }

    func competitors(for project: String?) -> [CompetitorStanding] {
        history.competitors(for: project, trackId: trackId(for: project))
    }

    /// Terms worth trying, drawn from what the checks already saw.
    ///
    /// Not a model and not a guess: these are words out of the names of apps
    /// that rank above this one on terms it already tracks. If a rival's title
    /// carries a word your listing does not, that is a real, checkable lead —
    /// which is as far as data from this API honestly reaches.
    func suggestions(for project: String?, limit: Int = 12) -> [String] {
        let tracked = Set(history.keywords(for: project).map { TrackedKeyword.normalize($0.term) })
        var counts: [String: Int] = [:]
        for competitor in competitors(for: project) {
            for word in Self.words(in: competitor.app.name) {
                guard !tracked.contains(word), word.count >= 2 else { continue }
                counts[word, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= 2 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    /// Store names are marketing, not prose: "골드위크 - 황금연휴 플래너" has to
    /// come apart at the punctuation as well as the spaces.
    private static func words(in name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = history
        Task { await KeywordCache.shared.save(snapshot) }
    }

    /// Write on the way out, on the spot — the same reason `FeedbackStore`
    /// does: an actor hop scheduled as the process is suspended may never run.
    func flush() {
        KeywordCache.saveNow(history)
    }
}

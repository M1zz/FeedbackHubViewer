//
//  FeedbackCache.swift
//  FeedbackHubViewer
//
//  What the last successful refresh saw, kept on disk so a relaunch paints
//  immediately instead of waiting for CloudKit. The network refresh then runs
//  on its own and only reports what changed (see `FeedbackStore.load(mode:)`).
//
//  The file is a plain JSON snapshot in Application Support, one per CloudKit
//  environment — a Development build must never show Production numbers.
//

import Foundation

/// One on-disk snapshot of the hub.
struct CachedHub: Codable {
    /// Bumped whenever the shape below changes; a mismatch throws the file away
    /// rather than trying to decode something it no longer understands.
    static let currentVersion = 2

    var version = CachedHub.currentVersion
    /// When this snapshot was written — what the UI shows as "업데이트".
    var savedAt: Date
    /// Per record type, the moment its last successful query ran. The next
    /// incremental refresh only asks for records modified after this.
    var watermarks: [String: Date] = [:]
    /// Which feedback record type actually resolved, so the next launch can
    /// query it straight away instead of probing every candidate name.
    var resolvedRecordType: String?
    /// Per record type, which system timestamp this container lets an
    /// incremental read filter on — an empty value means "neither". Remembered
    /// so a launch doesn't re-ask a question already answered.
    var filterFields: [String: String] = [:]
    /// Record types the last read could not sort newest-first, so it had to
    /// walk the whole type. Optional because files written before this existed
    /// must still decode; purely diagnostic — it is re-learned on every read,
    /// never restored.
    var unsortableTypes: [String]?

    var feedback: [Feedback] = []
    var snapshots: [UsageSnapshot] = []
    /// Only the recent window (`FeedbackStore.rawEventRetentionDays`). Older
    /// events are not dropped from the hub — they were summed into
    /// `UsageRollups` when they arrived, and every number on screen reads that.
    /// What is kept here is what the 사용 내역 list needs to show individual
    /// events. The shape is unchanged from earlier versions on purpose: a cache
    /// written before rollups existed still decodes, and its events are folded
    /// into the rollups on the next launch.
    var events: [UsageEvent] = []
    var crashes: [CrashReport] = []

    var isEmpty: Bool {
        feedback.isEmpty && snapshots.isEmpty && events.isEmpty && crashes.isEmpty
    }
}

/// Where the cache files live, and how a value gets into one.
///
/// Free of any actor's state on purpose: two callers need it. The stores below
/// use it for their ordinary reads and writes, and `FeedbackStore.flushCache()`
/// uses it as the app goes away — that one cannot afford to hop onto an actor,
/// because the hop may never be scheduled before the process is suspended.
enum CacheFile {

    /// `~/…/Application Support/FeedbackHubViewer/<name>.json`, with the
    /// directory created if it is not there yet.
    ///
    /// `environment` is present for anything read out of CloudKit — one file
    /// per environment, because a Development build must never show Production
    /// numbers — and absent for what has nothing to do with CloudKit, such as
    /// keyword rank history, which reads the public App Store and must survive
    /// a switch between the two schemes.
    static func url(_ name: String, _ environment: CloudKitEnvironment? = nil) -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true) else { return nil }
        let directory = base.appendingPathComponent("FeedbackHubViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = environment.map { "-\($0.restPathComponent)" } ?? ""
        return directory.appendingPathComponent("\(name)\(suffix).json")
    }

    /// Encode and write where the caller stands. Atomic, so a write cut short
    /// leaves the previous file rather than half of a new one.
    static func write<Value: Encodable>(_ value: Value, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Decode what is there, or nil when the file is absent, unreadable, or
    /// fails `accept`. A stale or corrupt file is worse than none: it is
    /// removed, and the next refresh writes a fresh one.
    static func read<Value: Decodable>(_ type: Value.Type, at url: URL?,
                                       accept: (Value) -> Bool = { _ in true }) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        guard let value = try? JSONDecoder().decode(Value.self, from: data), accept(value) else {
            remove(url)
            return nil
        }
        return value
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Reads and writes `CachedHub`. An actor, so the JSON work stays off the main
/// thread — the whole point is that the first frame doesn't wait for it.
actor FeedbackCache {

    static let shared = FeedbackCache()

    /// A snapshot older than this is refreshed in full rather than
    /// incrementally: an incremental query never notices deleted records, so
    /// the cache is rebuilt from scratch once a day.
    static let fullRefreshInterval: TimeInterval = 24 * 60 * 60

    private static let fileName = "hub"

    private let environment: CloudKitEnvironment

    init(environment: CloudKitEnvironment = .current) {
        self.environment = environment
    }

    private var fileURL: URL? { CacheFile.url(Self.fileName, environment) }

    /// Write without the actor hop. See `CacheFile` and
    /// `FeedbackStore.flushCache()`.
    nonisolated static func saveNow(_ hub: CachedHub,
                                    environment: CloudKitEnvironment = .current) {
        CacheFile.write(hub, to: CacheFile.url(fileName, environment))
    }

    func load() -> CachedHub? {
        // A file written by an older shape of `CachedHub` is thrown away rather
        // than half-decoded into something it no longer describes.
        CacheFile.read(CachedHub.self, at: fileURL) { $0.version == CachedHub.currentVersion }
    }

    func save(_ hub: CachedHub) {
        CacheFile.write(hub, to: fileURL)
    }

    func clear() {
        CacheFile.remove(fileURL)
    }
}

/// Reads and writes `UsageRollups`, in its own file next to the record cache.
///
/// Separate on purpose: the rollups are what every screen actually reads, and
/// they are small and stable, while `hub.json` carries whole records and is
/// rewritten whenever any of them moves. Splitting them means a refresh that
/// only added a few events rewrites the small file, and a launch can decode the
/// numbers without waiting on the records.
actor RollupCache {

    static let shared = RollupCache()

    private static let fileName = "rollups"

    private let environment: CloudKitEnvironment

    init(environment: CloudKitEnvironment = .current) {
        self.environment = environment
    }

    private var fileURL: URL? { CacheFile.url(Self.fileName, environment) }

    /// Write without the actor hop. See `FeedbackStore.flushCache()`.
    nonisolated static func saveNow(_ rollups: UsageRollups,
                                    environment: CloudKitEnvironment = .current) {
        CacheFile.write(rollups, to: CacheFile.url(fileName, environment))
    }

    func load() -> UsageRollups? {
        // A wider range than the hub file accepts: the ladder above the day
        // buckets can be rebuilt, so an older-but-readable file is repaired
        // rather than discarded.
        guard var rollups = CacheFile.read(UsageRollups.self, at: fileURL, accept: {
            (UsageRollups.earliestReadableVersion...UsageRollups.currentVersion).contains($0.version)
        }) else { return nil }

        // An older file, a device that changed region, or a run that folded
        // events and was killed before it re-summed them: all three are made
        // good from the day buckets, which are the only thing here that cannot
        // be recomputed. Written back now so the next launch has nothing to do.
        if rollups.prepareLadder() { CacheFile.write(rollups, to: fileURL) }
        return rollups
    }

    func save(_ rollups: UsageRollups) {
        CacheFile.write(rollups, to: fileURL)
    }

    func clear() {
        CacheFile.remove(fileURL)
    }
}

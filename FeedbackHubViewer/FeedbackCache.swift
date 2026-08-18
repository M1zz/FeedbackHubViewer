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

    var feedback: [Feedback] = []
    var snapshots: [UsageSnapshot] = []
    var events: [UsageEvent] = []
    var crashes: [CrashReport] = []

    var isEmpty: Bool {
        feedback.isEmpty && snapshots.isEmpty && events.isEmpty && crashes.isEmpty
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

    private let environment: CloudKitEnvironment
    private var directoryIsReady = false

    init(environment: CloudKitEnvironment = .current) {
        self.environment = environment
    }

    private var fileURL: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true) else { return nil }
        let directory = base.appendingPathComponent("FeedbackHubViewer", isDirectory: true)
        if !directoryIsReady {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            directoryIsReady = true
        }
        return directory.appendingPathComponent("hub-\(environment.restPathComponent).json")
    }

    func load() -> CachedHub? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedHub.self, from: data),
              cached.version == CachedHub.currentVersion else {
            // A stale or corrupt file is worse than none: drop it and let the
            // next refresh write a fresh one.
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return cached
    }

    func save(_ hub: CachedHub) {
        guard let fileURL, let data = try? JSONEncoder().encode(hub) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

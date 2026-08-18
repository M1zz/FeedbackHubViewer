//
//  Usage.swift
//  FeedbackHubViewer
//
//  The anonymous usage statistics the apps themselves report into the same
//  hub container, read back exactly as they were written.
//
//  Written by LeeoKit's `LeeoUsageReporter` (see the app-side policy in
//  ClipKeyboard's `UsageReportingService` and docs/USAGE_STATS_HUB.md):
//
//    UsageSnapshot — one record per install, upserted (recordName
//      "usage-<installID>"): appId, appName, appVersion, platform, osVersion,
//      locale, launchCount, eventCount, daysSinceInstall, installDate,
//      lastActiveAt, metrics (JSON `[String: Double]`).
//
//    UsageEvent — one record per significant action (throttled per name):
//      appId, appName, event, appVersion, platform, installID, occurredAt.
//
//  The viewer stays app-agnostic: `metrics` keys and event names are whatever
//  an app decided to send, and are shown under their own names.
//

import Foundation
import CloudKit

/// One install's snapshot, as reported by the app.
struct UsageSnapshot: Identifiable, Hashable {
    /// CloudKit record name — "usage-<installID>" for records LeeoKit wrote.
    let id: String
    let appId: String?
    let appName: String?
    let appVersion: String
    let platform: String
    let osVersion: String
    let locale: String
    let launchCount: Int
    /// Significant actions counted locally by the app (LeeoEngagement).
    let eventCount: Int
    let daysSinceInstall: Int
    let installDate: Date?
    let lastActiveAt: Date?
    /// Per-install approximate metrics the app chose to send. Keys are the
    /// app's own (`shortcuts`, `flag.isPro`, `persona.<name>`, …).
    let metrics: [String: Double]
    /// Every field on the record, stringified, for the raw view.
    let allFields: [(key: String, value: String)]

    static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The anonymous install identifier this snapshot belongs to. LeeoKit puts
    /// it in the record name rather than a field.
    var installID: String {
        id.hasPrefix("usage-") ? String(id.dropFirst("usage-".count)) : id
    }

    /// Same grouping rule as `Feedback.projectKey`, so usage and feedback line
    /// up under one project.
    var projectKey: String {
        if let id = appId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        if let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return Feedback.unclassifiedProject
    }

    init(record: CKRecord) {
        id = record.recordID.recordName
        appId = record["appId"] as? String
        appName = record["appName"] as? String
        appVersion = (record["appVersion"] as? String) ?? "—"
        platform = (record["platform"] as? String) ?? "—"
        osVersion = (record["osVersion"] as? String) ?? "—"
        locale = (record["locale"] as? String) ?? "—"
        launchCount = (record["launchCount"] as? Int) ?? 0
        eventCount = (record["eventCount"] as? Int) ?? 0
        daysSinceInstall = (record["daysSinceInstall"] as? Int) ?? 0
        installDate = record["installDate"] as? Date
        lastActiveAt = record["lastActiveAt"] as? Date
        metrics = UsageSnapshot.decodeMetrics(record["metrics"] as? String)
        allFields = record.allKeys().sorted().map { ($0, Feedback.stringify(record[$0])) }
    }

    /// `metrics` travels as a JSON object of doubles.
    private static func decodeMetrics(_ json: String?) -> [String: Double] {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return decoded
    }
}

/// One reported action. `occurredAt` is when it actually happened — a record
/// can be written days later (backfilled keyboard activity), so the creation
/// date would bunch those up on the day they were uploaded.
struct UsageEvent: Identifiable, Hashable {
    let id: String
    let appId: String?
    let appName: String?
    /// Event name, possibly with a slice: "paywall_view:memo".
    let name: String
    let appVersion: String
    let platform: String
    /// Anonymous install identifier, for counting distinct users.
    let installID: String?
    let occurredAt: Date

    static func == (lhs: UsageEvent, rhs: UsageEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var projectKey: String {
        if let id = appId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        if let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return Feedback.unclassifiedProject
    }

    /// The part before the slice separator, e.g. "paywall_view" of
    /// "paywall_view:memo".
    var baseName: String {
        String(name.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    init(record: CKRecord) {
        id = record.recordID.recordName
        appId = record["appId"] as? String
        appName = record["appName"] as? String
        name = (record["event"] as? String) ?? "—"
        appVersion = (record["appVersion"] as? String) ?? "—"
        platform = (record["platform"] as? String) ?? "—"
        installID = record["installID"] as? String
        // Old records predate `occurredAt`; they fall back to the server's
        // creation date, which is what the apps' own screens do too.
        occurredAt = (record["occurredAt"] as? Date) ?? record.creationDate ?? Date()
    }
}

// MARK: - Codable (disk cache)

/// Usage records are written to disk verbatim so a relaunch can paint before
/// CloudKit answers (see `FeedbackCache`). `allFields` is a tuple array, which
/// Codable cannot synthesize for, so it travels as an array of key/value pairs.
extension UsageSnapshot: Codable {
    private struct CachedField: Codable {
        let key: String
        let value: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, appId, appName, appVersion, platform, osVersion, locale
        case launchCount, eventCount, daysSinceInstall, installDate
        case lastActiveAt, metrics, allFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        appId = try c.decodeIfPresent(String.self, forKey: .appId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        platform = try c.decode(String.self, forKey: .platform)
        osVersion = try c.decode(String.self, forKey: .osVersion)
        locale = try c.decode(String.self, forKey: .locale)
        launchCount = try c.decode(Int.self, forKey: .launchCount)
        eventCount = try c.decode(Int.self, forKey: .eventCount)
        daysSinceInstall = try c.decode(Int.self, forKey: .daysSinceInstall)
        installDate = try c.decodeIfPresent(Date.self, forKey: .installDate)
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        metrics = try c.decode([String: Double].self, forKey: .metrics)
        allFields = try c.decode([CachedField].self, forKey: .allFields)
            .map { (key: $0.key, value: $0.value) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(appId, forKey: .appId)
        try c.encodeIfPresent(appName, forKey: .appName)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(platform, forKey: .platform)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(locale, forKey: .locale)
        try c.encode(launchCount, forKey: .launchCount)
        try c.encode(eventCount, forKey: .eventCount)
        try c.encode(daysSinceInstall, forKey: .daysSinceInstall)
        try c.encodeIfPresent(installDate, forKey: .installDate)
        try c.encodeIfPresent(lastActiveAt, forKey: .lastActiveAt)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(allFields.map { CachedField(key: $0.key, value: $0.value) }, forKey: .allFields)
    }
}

/// Every property is a plain value, so the cache representation is synthesized.
extension UsageEvent: Codable {}

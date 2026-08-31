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
//  Unlike feedback, these schemas are the hub's own — the field names are fixed
//  and read straight, with no `RecordReader` name-guessing.
//

import Foundation
import CloudKit

/// One install's snapshot, as reported by the app.
struct UsageSnapshot: HubRecord, Codable {
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
    let allFields: [RecordField]

    /// The anonymous install identifier this snapshot belongs to. LeeoKit puts
    /// it in the record name rather than a field.
    var installID: String {
        id.hasPrefix("usage-") ? String(id.dropFirst("usage-".count)) : id
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
        allFields = RecordReader(record).allFields
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
struct UsageEvent: HubRecord, Codable {
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

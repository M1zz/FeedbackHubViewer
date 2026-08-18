//
//  Feedback.swift
//  FeedbackHubViewer
//
//  A CloudKit-record-agnostic model. Because the exact schema of the
//  FeedbackHub container is not known ahead of time, this type maps a
//  handful of *common* field names to strongly-typed properties and also
//  keeps every raw field around so the detail view can show anything.
//

import Foundation
import CloudKit

struct Feedback: Identifiable, Hashable {
    /// Shown for records that carry no project identifier (e.g. legacy
    /// feedback submitted before LeeoKit started tagging the source app).
    static let unclassifiedProject = "미분류"

    let id: String              // CKRecord.ID.recordName
    let recordType: String
    /// Machine identifier of the source app (`appId` field — e.g. "kora").
    /// Present on hub records; the stable key used to group by project.
    let appId: String?
    /// Human-readable app name (`appName` field — e.g. "KORA"). Only newer
    /// LeeoKit records carry it; older records have only `appId`.
    let appName: String?
    let text: String
    let rating: Int?
    let appVersion: String?
    let deviceModel: String?
    let systemVersion: String?
    let contactEmail: String?
    /// Feedback category as submitted by LeeoKit (`type` field — e.g. bug /
    /// feature request). `nil` when the record has no such field.
    let feedbackType: String?
    /// Submitting platform (`platform` field — e.g. iOS / macCatalyst).
    let platform: String?
    let createdAt: Date?
    let modifiedAt: Date?

    /// Every field on the record, stringified, for the detail view.
    let allFields: [(key: String, value: String)]

    // Identity is the CloudKit record name, which is globally unique. Declared
    // explicitly because the tuple-array `allFields` blocks synthesized
    // Hashable/Equatable conformance.
    static func == (lhs: Feedback, rhs: Feedback) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Construction from CKRecord

    init(record: CKRecord) {
        id = record.recordID.recordName
        recordType = record.recordType
        createdAt = record.creationDate
        modifiedAt = record.modificationDate

        var fields: [(key: String, value: String)] = []
        for key in record.allKeys().sorted() {
            fields.append((key, Feedback.stringify(record[key])))
        }
        allFields = fields

        appId = Feedback.firstString(
            in: record,
            keys: ["appId", "appID", "app_id", "bundleID", "bundleIdentifier",
                   "appBundleID"]
        )

        appName = Feedback.firstString(
            in: record,
            keys: ["appName", "projectName", "project", "appTitle",
                   "source", "sourceApp"]
        )

        text = Feedback.firstString(
            in: record,
            keys: ["text", "message", "content", "body", "feedback",
                   "feedbackText", "comment", "comments", "description", "note"]
        ) ?? ""

        rating = Feedback.firstInt(
            in: record,
            keys: ["rating", "stars", "star", "score", "rate"]
        )

        appVersion = Feedback.firstString(
            in: record,
            keys: ["appVersion", "version", "appVer", "buildVersion",
                   "app_version", "build"]
        )

        deviceModel = Feedback.firstString(
            in: record,
            keys: ["deviceModel", "device", "model", "deviceName",
                   "device_model", "hardware"]
        )

        systemVersion = Feedback.firstString(
            in: record,
            keys: ["systemVersion", "osVersion", "os", "iosVersion",
                   "macosVersion", "system_version"]
        )

        contactEmail = Feedback.firstString(
            in: record,
            keys: ["email", "contactEmail", "contact", "userEmail", "mail"]
        )

        feedbackType = Feedback.firstString(
            in: record,
            keys: ["type", "category", "kind", "feedbackType", "topic"]
        )

        platform = Feedback.firstString(
            in: record,
            keys: ["platform", "os", "osName", "deviceOS"]
        )
    }

    /// Convenience initializer used only by SwiftUI previews / sample data.
    init(id: String, text: String, rating: Int?, appVersion: String?,
         deviceModel: String?, systemVersion: String?, contactEmail: String?,
         createdAt: Date?, appId: String? = nil, appName: String? = nil) {
        self.id = id
        self.recordType = "Feedback"
        self.appId = appId
        self.appName = appName
        self.text = text
        self.rating = rating
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.contactEmail = contactEmail
        self.feedbackType = nil
        self.platform = nil
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        var fields: [(key: String, value: String)] = [("text", text)]
        if let rating { fields.append(("rating", String(rating))) }
        if let appVersion { fields.append(("appVersion", appVersion)) }
        if let deviceModel { fields.append(("deviceModel", deviceModel)) }
        self.allFields = fields
    }

    // MARK: - Field extraction helpers

    private static func firstString(in record: CKRecord, keys: [String]) -> String? {
        let lowered = Dictionary(record.allKeys().map { ($0.lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })
        for key in keys {
            if let actual = lowered[key.lowercased()], let value = record[actual] {
                let s = stringify(value)
                if !s.isEmpty { return s }
            }
        }
        return nil
    }

    private static func firstInt(in record: CKRecord, keys: [String]) -> Int? {
        let lowered = Dictionary(record.allKeys().map { ($0.lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })
        for key in keys {
            guard let actual = lowered[key.lowercased()], let value = record[actual] else { continue }
            if let n = value as? NSNumber { return n.intValue }
            if let s = value as? String, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
            if let d = value as? Double { return Int(d) }
        }
        return nil
    }

    /// Turn any CKRecordValue into something printable.
    static func stringify(_ value: CKRecordValue?) -> String {
        guard let value else { return "" }
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            return n.stringValue
        case let d as Date:
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        case let data as Data:
            return "\(data.count) bytes"
        case let asset as CKAsset:
            return asset.fileURL?.lastPathComponent ?? "asset"
        case let ref as CKRecord.Reference:
            return ref.recordID.recordName
        case let array as [CKRecordValue]:
            return array.map { stringify($0) }.joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    // MARK: - Presentation helpers

    /// Stable grouping key for the project: prefer the machine `appId`, fall
    /// back to `appName`, then to the unclassified bucket. Never empty. Display
    /// names are resolved from this key by `FeedbackStore.displayName(for:)`.
    var projectKey: String {
        if let id = appId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        if let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return Feedback.unclassifiedProject
    }

    /// The app name carried by this record alone (no cross-record learning).
    var recordAppName: String? {
        let trimmed = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var createdAtDisplay: String {
        guard let createdAt else { return "—" }
        return AppFormat.dateTime(createdAt)
    }

    /// "3주 전" — for narrow rows where the full timestamp doesn't fit.
    var createdAtRelative: String {
        guard let createdAt else { return "—" }
        return AppFormat.relative(createdAt)
    }

    var snippet: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Fall back to the first non-empty field so the row is never blank.
            return allFields.first(where: { !$0.value.isEmpty })?.value ?? "(no text)"
        }
        return trimmed
    }
}

// MARK: - Codable (disk cache)

/// Feedback is written to disk verbatim so a relaunch can paint before CloudKit
/// answers (see `FeedbackCache`). `allFields` is a tuple array, which Codable
/// cannot synthesize for, so it travels as an array of key/value pairs.
extension Feedback: Codable {
    private struct CachedField: Codable {
        let key: String
        let value: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, recordType, appId, appName, text, rating, appVersion
        case deviceModel, systemVersion, contactEmail, feedbackType, platform
        case createdAt, modifiedAt, allFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        recordType = try c.decode(String.self, forKey: .recordType)
        appId = try c.decodeIfPresent(String.self, forKey: .appId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        text = try c.decode(String.self, forKey: .text)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
        systemVersion = try c.decodeIfPresent(String.self, forKey: .systemVersion)
        contactEmail = try c.decodeIfPresent(String.self, forKey: .contactEmail)
        feedbackType = try c.decodeIfPresent(String.self, forKey: .feedbackType)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
        allFields = try c.decode([CachedField].self, forKey: .allFields)
            .map { (key: $0.key, value: $0.value) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(recordType, forKey: .recordType)
        try c.encodeIfPresent(appId, forKey: .appId)
        try c.encodeIfPresent(appName, forKey: .appName)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(rating, forKey: .rating)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
        try c.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try c.encodeIfPresent(systemVersion, forKey: .systemVersion)
        try c.encodeIfPresent(contactEmail, forKey: .contactEmail)
        try c.encodeIfPresent(feedbackType, forKey: .feedbackType)
        try c.encodeIfPresent(platform, forKey: .platform)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try c.encode(allFields.map { CachedField(key: $0.key, value: $0.value) }, forKey: .allFields)
    }
}

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
    let id: String              // CKRecord.ID.recordName
    let recordType: String
    let text: String
    let rating: Int?
    let appVersion: String?
    let deviceModel: String?
    let systemVersion: String?
    let contactEmail: String?
    let createdAt: Date?
    let modifiedAt: Date?

    /// Every field on the record, stringified, for the detail view.
    let allFields: [(key: String, value: String)]

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
    }

    /// Convenience initializer used only by SwiftUI previews / sample data.
    init(id: String, text: String, rating: Int?, appVersion: String?,
         deviceModel: String?, systemVersion: String?, contactEmail: String?,
         createdAt: Date?) {
        self.id = id
        self.recordType = "Feedback"
        self.text = text
        self.rating = rating
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.contactEmail = contactEmail
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

    var createdAtDisplay: String {
        guard let createdAt else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: createdAt)
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

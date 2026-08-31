//
//  Feedback.swift
//  FeedbackHubViewer
//
//  A CloudKit-record-agnostic model. Because the exact schema of the
//  FeedbackHub container is not known ahead of time, this type maps a
//  handful of *common* field names to strongly-typed properties and also
//  keeps every raw field around so the detail view can show anything.
//
//  The name-matching itself lives in `RecordReader`.
//

import Foundation
import CloudKit

struct Feedback: HubRecord, Codable {
    /// Shown for records that carry no project identifier (e.g. legacy
    /// feedback submitted before LeeoKit started tagging the source app).
    static let unclassifiedProject = "미분류"

    let id: String              // CKRecord.ID.recordName
    let recordType: String
    let appId: String?
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

    /// Every field on the record, stringified, for the detail view. Carried to
    /// disk verbatim so a relaunch can paint before CloudKit answers.
    let allFields: [RecordField]

    // MARK: - Construction from CKRecord

    init(record: CKRecord) {
        let fields = RecordReader(record)

        id = record.recordID.recordName
        recordType = record.recordType
        createdAt = record.creationDate
        modifiedAt = record.modificationDate
        allFields = fields.allFields

        appId = fields.string("appId", "appID", "app_id", "bundleID",
                              "bundleIdentifier", "appBundleID")
        appName = fields.string("appName", "projectName", "project", "appTitle",
                                "source", "sourceApp")
        text = fields.string("text", "message", "content", "body", "feedback",
                             "feedbackText", "comment", "comments", "description", "note") ?? ""
        rating = fields.int("rating", "stars", "star", "score", "rate")
        appVersion = fields.string("appVersion", "version", "appVer", "buildVersion",
                                   "app_version", "build")
        deviceModel = fields.string("deviceModel", "device", "model", "deviceName",
                                    "device_model", "hardware")
        systemVersion = fields.string("systemVersion", "osVersion", "os", "iosVersion",
                                      "macosVersion", "system_version")
        contactEmail = fields.string("email", "contactEmail", "contact", "userEmail", "mail")
        feedbackType = fields.string("type", "category", "kind", "feedbackType", "topic")
        platform = fields.string("platform", "os", "osName", "deviceOS")
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

        var fields = [RecordField(key: "text", value: text)]
        if let rating { fields.append(RecordField(key: "rating", value: String(rating))) }
        if let appVersion { fields.append(RecordField(key: "appVersion", value: appVersion)) }
        if let deviceModel { fields.append(RecordField(key: "deviceModel", value: deviceModel)) }
        self.allFields = fields
    }

    // MARK: - Presentation helpers

    /// The app name carried by this record alone (no cross-record learning).
    var recordAppName: String? {
        let trimmed = appName?.trimmed ?? ""
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
        let trimmed = text.trimmed
        if trimmed.isEmpty {
            // Fall back to the first non-empty field so the row is never blank.
            return allFields.first(where: { !$0.value.isEmpty })?.value ?? "(no text)"
        }
        return trimmed
    }
}

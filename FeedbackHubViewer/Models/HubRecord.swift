//
//  HubRecord.swift
//  FeedbackHubViewer
//
//  What everything in the hub has in common: it is one CloudKit record, it is
//  identified by that record's name, and it belongs to one project.
//
//  The four record types each carried their own copy of `projectKey` and their
//  own `==`/`hash(into:)`. They agreed, which is the only reason nothing broke
//  — but "usage and feedback line up under one project" is a rule of the hub,
//  not a coincidence four structs happened to share, so it is written once.
//

import Foundation

protocol HubRecord: Identifiable, Hashable {
    /// `CKRecord.ID.recordName` — globally unique, which is what makes it the
    /// identity below.
    var id: String { get }
    /// Machine identifier of the source app (`appId` — e.g. "kora"), when the
    /// record carries one.
    var appId: String? { get }
    /// Human-readable app name (`appName` — e.g. "KORA"). Only newer LeeoKit
    /// records carry it; diagnostics never do.
    var appName: String? { get }
}

extension HubRecord {
    /// Diagnostics have no `appName` field at all — their project name is
    /// resolved from the `appId` like an older feedback record's is.
    var appName: String? { nil }

    /// Stable grouping key for the project: prefer the machine `appId`, fall
    /// back to `appName`, then to the unclassified bucket. Never empty. Display
    /// names are resolved from this key by `FeedbackStore.displayName(for:)`.
    var projectKey: String {
        if let id = appId?.trimmed, !id.isEmpty { return id }
        if let name = appName?.trimmed, !name.isEmpty { return name }
        return Feedback.unclassifiedProject
    }

    // Identity is the CloudKit record name. Declared rather than synthesized
    // because two of these types hold an array of stringified fields, which
    // blocks synthesis — and because equality *should* be the record name
    // regardless: the same record read twice is the same record.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

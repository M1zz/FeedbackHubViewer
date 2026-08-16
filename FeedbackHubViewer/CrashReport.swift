//
//  CrashReport.swift
//  FeedbackHubViewer
//
//  MetricKit diagnostics the apps upload into the same hub container, read back
//  as they were written (see ClipKeyboard's `DiagnosticsService` and
//  docs/CRASH_REPORT_SCHEMA.md):
//
//    CrashReport — every field a String: appId, kind ("crash" / "hang" /
//      "disk_write"), detail, appVersion, osVersion, deviceType, stack (call
//      stack JSON, truncated at 4000 characters).
//
//  There is no timestamp field and no appName: the record's creation date is
//  when it arrived, and the project name is resolved from the appId the same
//  way feedback and usage records are.
//

import Foundation
import CloudKit

struct CrashReport: Identifiable, Hashable {
    let id: String
    let appId: String?
    /// "crash" / "hang" / "disk_write" — anything else is shown as sent.
    let kind: String
    /// One line about the termination reason, hang duration, and so on.
    let detail: String
    let appVersion: String
    let osVersion: String
    let deviceType: String
    /// Call stack JSON. Long, so the UI keeps it collapsed.
    let stack: String
    /// When the record reached the hub. MetricKit hands diagnostics over about
    /// once a day, so this trails the actual crash.
    let receivedAt: Date?

    static func == (lhs: CrashReport, rhs: CrashReport) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var projectKey: String {
        if let id = appId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        return Feedback.unclassifiedProject
    }

    var kindLabel: String { Self.label(for: kind) }

    /// Same wording the apps use on their own 안정성 screen. An unknown kind is
    /// shown as sent rather than hidden.
    static func label(for kind: String) -> String {
        switch kind {
        case "crash": return "크래시"
        case "hang": return "멈춤"
        case "disk_write": return "과도한 디스크 쓰기"
        default: return kind
        }
    }

    /// Short form for tight places (a segmented filter), where the full label
    /// would be truncated instead of shortened.
    static func shortLabel(for kind: String) -> String {
        kind == "disk_write" ? "디스크 쓰기" : label(for: kind)
    }

    var hasDetail: Bool {
        !detail.isEmpty && detail != "-"
    }

    /// Plain text for copying into a bug report, like the apps' own screen.
    var copyText: String {
        var lines = ["[\(kindLabel)] \(appVersion)"]
        if let receivedAt { lines.append(AppFormat.dateTime(receivedAt)) }
        lines.append("\(deviceType) · OS \(osVersion)")
        if hasDetail { lines.append(detail) }
        lines.append("")
        lines.append(stack)
        return lines.joined(separator: "\n")
    }

    init(record: CKRecord) {
        id = record.recordID.recordName
        appId = record["appId"] as? String
        kind = (record["kind"] as? String) ?? "-"
        detail = (record["detail"] as? String) ?? "-"
        appVersion = (record["appVersion"] as? String) ?? "—"
        osVersion = (record["osVersion"] as? String) ?? "—"
        deviceType = (record["deviceType"] as? String) ?? "—"
        stack = (record["stack"] as? String) ?? ""
        receivedAt = record.creationDate
    }
}

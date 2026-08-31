//
//  RecordReader.swift
//  FeedbackHubViewer
//
//  Reading a `CKRecord` whose schema is not known ahead of time.
//
//  The hub's own record types (usage, diagnostics) have fixed field names and
//  are read straight. Feedback does not: it predates LeeoKit and arrives from
//  several generations of app, so a field may be `appId`, `appID` or
//  `bundleIdentifier`. `RecordReader` takes the list of names a value might
//  have gone by and returns the first one present.
//
//  Built once per record. The lowercased index used to be rebuilt inside every
//  lookup, which meant walking the record's key list ten times to construct one
//  `Feedback`.
//

import Foundation
import CloudKit

/// One field of a record, stringified for display and for the disk cache.
/// A struct rather than a `(key:value:)` tuple so both `Codable` and `Hashable`
/// can be synthesized for the records that hold an array of these.
struct RecordField: Codable, Hashable {
    let key: String
    let value: String
}

struct RecordReader {
    private let record: CKRecord
    /// Lowercased field name → the name as the record actually spells it.
    private let index: [String: String]

    init(_ record: CKRecord) {
        self.record = record
        self.index = Dictionary(record.allKeys().map { ($0.lowercased(), $0) },
                                uniquingKeysWith: { first, _ in first })
    }

    /// The first of `keys` the record carries a non-empty value for.
    func string(_ keys: String...) -> String? {
        for key in keys {
            guard let actual = index[key.lowercased()], let value = record[actual] else { continue }
            let text = RecordReader.stringify(value)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// The same, for a number that may have been written as one or as a string.
    func int(_ keys: String...) -> Int? {
        for key in keys {
            guard let actual = index[key.lowercased()], let value = record[actual] else { continue }
            if let n = value as? NSNumber { return n.intValue }
            if let s = value as? String, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
            if let d = value as? Double { return Int(d) }
        }
        return nil
    }

    /// Every field, stringified and sorted by name — what a detail view shows
    /// when it has no idea what the record contains.
    var allFields: [RecordField] {
        record.allKeys().sorted().map { RecordField(key: $0, value: RecordReader.stringify(record[$0])) }
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
}

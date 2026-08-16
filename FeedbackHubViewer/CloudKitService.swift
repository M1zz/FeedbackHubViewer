//
//  CloudKitService.swift
//  FeedbackHubViewer
//
//  Reads feedback records from the PUBLIC CloudKit database of the
//  "iCloud.com.Ysoup.FeedbackHub" container.
//
//  Because the record type name is not known in advance, the service tries a
//  list of likely names and uses the first one that returns rows. If your
//  record type has a different name, add it to `candidateRecordTypes` (or set
//  it as the first entry) and rebuild.
//

import Foundation
import CloudKit

/// Which half of the CloudKit container a build reads.
///
/// CloudKit picks this from the `com.apple.developer.icloud-container-environment`
/// entitlement baked into the binary, so it is fixed for a given build — the
/// framework has no runtime switch. The `CLOUDKIT_PRODUCTION` compilation
/// condition is set by the "Production" build configuration, which ships the
/// Production entitlement; everything else follows the usual Debug/Release rule.
enum CloudKitEnvironment: String {
    case development = "Development"
    case production = "Production"

    var displayName: String {
        switch self {
        case .development: return "Development"
        case .production: return "Production"
        }
    }

    var shortLabel: String {
        switch self {
        case .development: return "DEV"
        case .production: return "PROD"
        }
    }

    /// The environment path component in a CloudKit Web Services URL.
    var restPathComponent: String {
        switch self {
        case .development: return "development"
        case .production: return "production"
        }
    }

    static var current: CloudKitEnvironment {
        #if CLOUDKIT_PRODUCTION
        return .production
        #elseif DEBUG
        return .development
        #else
        // Release builds (TestFlight / App Store) always read Production.
        return .production
        #endif
    }
}

@MainActor
final class CloudKitService {

    /// The CloudKit container that backs the feedback data.
    static let containerIdentifier = "iCloud.com.Ysoup.FeedbackHub"

    /// The environment this build reads. See `CloudKitEnvironment`.
    static var environment: CloudKitEnvironment { .current }

    /// Likely names for the feedback record type. The first one that returns
    /// data wins. Reorder or add your real type name here if needed.
    var candidateRecordTypes = [
        "Feedback", "Feedbacks", "FeedbackItem", "FeedbackEntry",
        "UserFeedback", "Review", "Report", "CD_Feedback"
    ]

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    init() {
        container = CKContainer(identifier: Self.containerIdentifier)
    }

    struct FetchOutcome {
        var feedback: [Feedback]
        /// The record type that actually produced rows, for display.
        var resolvedRecordType: String?
    }

    /// Fetch all feedback from the public database.
    func fetchFeedback() async throws -> FetchOutcome {
        var lastError: Error?

        for type in candidateRecordTypes {
            do {
                let records = try await queryAll(recordType: type)
                if !records.isEmpty {
                    let items = records.map(Feedback.init(record:))
                    return FetchOutcome(feedback: items, resolvedRecordType: type)
                }
            } catch {
                // "Unknown record type" and similar are expected while probing;
                // remember the error and keep trying other candidates.
                lastError = error
                continue
            }
        }

        // No candidate returned rows. If every attempt errored, surface the
        // last error so the UI can explain what went wrong; otherwise the
        // database is simply empty.
        if let lastError, !isBenignProbeError(lastError) {
            throw lastError
        }
        return FetchOutcome(feedback: [], resolvedRecordType: nil)
    }

    // MARK: - Querying

    private func queryAll(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        // Prefer newest-first, but many public schemas don't mark the creation
        // timestamp as sortable — fall back to an unsorted query if so.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            return try await runQuery(query)
        } catch {
            if isSortError(error) {
                query.sortDescriptors = []
                return try await runQuery(query)
            }
            throw error
        }
    }

    private func runQuery(_ query: CKQuery) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor,
                                                  desiredKeys: nil,
                                                  resultsLimit: CKQueryOperation.maximumResults)
            } else {
                page = try await database.records(matching: query,
                                                  inZoneWith: nil,
                                                  desiredKeys: nil,
                                                  resultsLimit: CKQueryOperation.maximumResults)
            }
            for (_, result) in page.matchResults {
                if case .success(let record) = result {
                    collected.append(record)
                }
            }
            cursor = page.queryCursor
        } while cursor != nil

        return collected
    }

    // MARK: - Error classification

    private func isSortError(_ error: Error) -> Bool {
        let ck = error as NSError
        // "Field 'creationDate' is not marked sortable" -> invalidArguments.
        return ck.domain == CKErrorDomain
            && ck.code == CKError.invalidArguments.rawValue
            && ck.localizedDescription.lowercased().contains("sort")
    }

    /// Errors that just mean "this record type doesn't exist here" — safe to
    /// ignore while probing candidate types.
    private func isBenignProbeError(_ error: Error) -> Bool {
        let ck = error as NSError
        guard ck.domain == CKErrorDomain else { return false }
        if ck.code == CKError.unknownItem.rawValue { return true }
        let msg = ck.localizedDescription.lowercased()
        return msg.contains("did not find record type")
            || msg.contains("unknown record type")
            || msg.contains("not marked queryable")
    }

    /// The current iCloud account's CloudKit user record name. This is the
    /// value you register in an admin Security Role (with read permission) on
    /// the CloudKit Dashboard so this account can read feedback that World is
    /// not allowed to read.
    func currentUserRecordName() async -> String? {
        do {
            return try await container.userRecordID().recordName
        } catch {
            return nil
        }
    }

    // MARK: - Account status (for a friendlier message)

    func accountStatusMessage() async -> String? {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return nil
            case .noAccount:
                return "이 Mac에 로그인된 iCloud 계정이 없습니다. 공개 데이터는 조회될 수 있지만, 계정 로그인이 권장됩니다."
            case .restricted:
                return "iCloud 접근이 제한되어 있습니다(기기 관리 정책 등)."
            case .couldNotDetermine:
                return "iCloud 계정 상태를 확인할 수 없습니다."
            case .temporarilyUnavailable:
                return "iCloud 계정을 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도하세요."
            @unknown default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

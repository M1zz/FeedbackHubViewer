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

    var displayName: String { rawValue }

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
    nonisolated static let containerIdentifier = "iCloud.com.Ysoup.FeedbackHub"

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

    /// Called on every page a read walks, with the record type being paged and
    /// how many records of it have been seen so far.
    ///
    /// This is deliberately a count and not a fraction: a CloudKit query never
    /// says how many records it will return — paging just runs until the cursor
    /// comes back `nil` — so there is no denominator to build a percentage out
    /// of. What a refresh *can* say honestly is which record type it is on and
    /// how far it has walked, which is what `FeedbackStore.refreshProgress`
    /// turns into the status line.
    var onProgress: ((String, Int) -> Void)?

    init() {
        container = CKContainer(identifier: Self.containerIdentifier)
    }

    /// Usage statistics record types, written by LeeoKit's `LeeoUsageReporter`
    /// into this same container. Fixed names — unlike feedback, there is no
    /// guessing to do (see `Usage.swift`).
    static let snapshotRecordType = "UsageSnapshot"
    static let eventRecordType = "UsageEvent"
    /// MetricKit diagnostics, uploaded by the apps' `DiagnosticsService`.
    static let crashRecordType = "CrashReport"

    struct FetchOutcome {
        var feedback: [Feedback]
        /// The record type that actually produced rows, for display.
        var resolvedRecordType: String?
    }

    struct UsageOutcome {
        /// `nil` means "this type was not read this time" — the query failed,
        /// so whatever the caller already had is still the best it has. An
        /// empty array means the type was read and holds nothing.
        var snapshots: [UsageSnapshot]?
        var events: [UsageEvent]?
        var crashes: [CrashReport]?
        /// Why usage data is missing or incomplete, if it is. Usage is a
        /// separate schema with its own read permission, so it can fail while
        /// feedback loads fine — that is worth saying rather than showing an
        /// empty dashboard.
        var notice: String?
        /// Record types whose query succeeded, with the moment it ran. The
        /// caller stores these as the watermark for the next incremental read.
        var syncedTypes: [String: Date] = [:]
        /// Record types this container would not let the read narrow — neither
        /// a `creationDate` filter nor a newest-first sort. Such a read is a
        /// full unordered scan every time, so it is correct but expensive, and
        /// it can never stop early. Reported so the hub can say what to fix in
        /// the CloudKit Console instead of quietly getting slower.
        var unindexedTypes: Set<String> = []
    }

    /// Read the usage statistics the apps report. Each record type is fetched
    /// independently: a missing or unreadable one leaves the other intact,
    /// which is how the apps' own statistics screens behave.
    ///
    /// - Parameters:
    ///   - modifiedSince: per record type, only read records changed after this
    ///     moment. Absent (the launch-with-no-cache case) reads everything.
    ///   - known: per record type, the record names this device already holds,
    ///     so the read can stop as soon as it reaches them. Absent reads
    ///     everything, which is what a full refresh wants.
    ///
    /// No record type is capped here. A cap on a read that cannot be resumed
    /// does not return "the newest N" — it returns *some* N, and the type is
    /// then marked as read to the end, so the rest is never asked for again.
    /// What the hub keeps is bounded on the way in instead: events are summed
    /// into `UsageRollups` and only a recent window is retained as records
    /// (`FeedbackStore.withinRetention`), and diagnostics are trimmed after the
    /// merge. Reads themselves stop early only where that is sound — at a run
    /// of records this device already holds, which needs the newest-first sort.
    ///   - onPartial: handed a slice of one record type while it is still being
    ///     read, and once more with the whole of it when that type is done —
    ///     that last call is the one carrying `syncedTypes`, which is what
    ///     tells the caller the type was read to the end. Everything before it
    ///     is the newest records and nothing older, so it may only be merged,
    ///     never treated as the whole type. See `partialBatch`.
    func fetchUsage(modifiedSince: [String: Date] = [:],
                    known: [String: Set<String>] = [:],
                    onPartial: ((UsageOutcome) -> Void)? = nil) async -> UsageOutcome {
        var outcome = UsageOutcome()
        var problems: [String] = []
        let startedAt = Date()
        unsortableTypes = []

        /// Read one type into the slot it belongs in. Each is independent: a
        /// missing or unreadable one leaves the others intact, which is how the
        /// apps\' own statistics screens behave.
        func read<Record>(_ recordType: String,
                          shape: ChangeShape = .appendOnly,
                          _ make: @escaping (CKRecord) -> Record,
                          into slot: WritableKeyPath<UsageOutcome, [Record]?>) async {
            do {
                // `known` only narrows an append-only type — see `queryAll`.
                let records = try await queryAll(recordType: recordType,
                                                 modifiedSince: modifiedSince[recordType],
                                                 shape: shape,
                                                 known: known[recordType],
                                                 onPartial: { page in
                    var partial = UsageOutcome()
                    partial[keyPath: slot] = page.map(make)
                    onPartial?(partial)
                })
                outcome[keyPath: slot] = records.map(make)
                outcome.syncedTypes[recordType] = startedAt

                // The last hand-over is the one carrying `syncedTypes`: that is
                // what tells the caller this type was read to the end.
                var finished = UsageOutcome()
                finished[keyPath: slot] = outcome[keyPath: slot]
                finished.syncedTypes = [recordType: startedAt]
                onPartial?(finished)
            } catch {
                problems.append(usageProblem(recordType, error))
            }
        }

        // The one upserted type: a snapshot is rewritten in place every time an
        // install reports again, so its creation date says nothing.
        await read(Self.snapshotRecordType, shape: .upserted,
                   UsageSnapshot.init(record:), into: \.snapshots)
        await read(Self.eventRecordType, UsageEvent.init(record:), into: \.events)
        await read(Self.crashRecordType, CrashReport.init(record:), into: \.crashes)

        // A type that can be neither filtered nor sorted has no way to read
        // less than all of it, and no way to stop early either — so it is read
        // whole on every refresh, for as long as it keeps growing. Nothing on
        // screen would ever say so, which is why it is said here.
        outcome.unindexedTypes = unsortableTypes.filter { learnedFilterField[$0] == FilterField.none }
        if !outcome.unindexedTypes.isEmpty {
            problems.append("\(outcome.unindexedTypes.sorted().joined(separator: ", "))은(는) 새로고침마다 전체를 읽고 있습니다"
                + " — CloudKit Console → 이 레코드 타입의 Indexes에서 Created(___createTime)와"
                + " Modified(___modTime)를 Queryable·Sortable로 추가하면 바뀐 부분만 읽습니다.")
        }
        if !problems.isEmpty {
            outcome.notice = problems.joined(separator: "\n")
                + "\n\nCloudKit Console에서 해당 스키마가 이 환경에 배포되어 있고, admin 역할에 read 권한이 있는지 확인하세요."
        }
        return outcome
    }

    private func usageProblem(_ type: String, _ error: Error) -> String {
        isBenignProbeError(error)
            ? "\(type) 레코드 타입이 이 환경에 아직 없습니다."
            : "\(type)을(를) 읽지 못했습니다: \(Self.friendlyDescription(for: error))"
    }

    private static func friendlyDescription(for error: Error) -> String {
        let ck = error as NSError
        if ck.domain == CKErrorDomain, ck.code == CKError.permissionFailure.rawValue {
            return "읽기 권한이 없습니다 (Security Roles의 admin 역할 확인)"
        }
        return ck.localizedDescription
    }

    /// Fetch feedback from the public database.
    ///
    /// - Parameters:
    ///   - modifiedSince: only read records changed after this moment — what an
    ///     incremental refresh asks for. `nil` reads everything.
    ///   - knownRecordType: the type a previous run resolved. Trying it first
    ///     skips probing the whole candidate list on every launch; if it yields
    ///     nothing on a full read, the probe still runs.
    ///   - known: record names this device already holds, so the read can stop
    ///     as soon as it reaches them.
    func fetchFeedback(modifiedSince: Date? = nil,
                       knownRecordType: String? = nil,
                       known: Set<String>? = nil) async throws -> FetchOutcome {
        var lastError: Error?

        if let knownRecordType {
            do {
                let records = try await queryAll(recordType: knownRecordType,
                                                 modifiedSince: modifiedSince, known: known)
                // On an incremental read "nothing came back" is the normal
                // answer and says nothing about the type being wrong.
                if !records.isEmpty || modifiedSince != nil || known != nil {
                    return FetchOutcome(feedback: records.map(Feedback.init(record:)),
                                        resolvedRecordType: knownRecordType)
                }
            } catch {
                lastError = error
            }
        }

        for type in candidateRecordTypes where type != knownRecordType {
            do {
                let records = try await queryAll(recordType: type, modifiedSince: modifiedSince, known: known)
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
        return FetchOutcome(feedback: [], resolvedRecordType: knownRecordType)
    }

    // MARK: - Querying

    /// How a record type changes, which decides what an incremental read is
    /// allowed to filter on.
    enum ChangeShape {
        /// Records are only ever appended — feedback, events, diagnostics. The
        /// creation date is then just as good a filter as the modification
        /// date, and public schemas index it far more often.
        case appendOnly
        /// Records are rewritten in place (one usage snapshot per install), so
        /// only a modification-date filter notices an update.
        case upserted
    }

    /// The timestamp an incremental read filters on. The raw values are what
    /// gets written to the cache file, so they must stay stable.
    enum FilterField: String {
        case creation = "creationDate"
        case modification = "modificationDate"
        /// Recorded when neither is queryable in this container.
        case none = ""

        var key: String? { self == .none ? nil : rawValue }
    }

    /// Which timestamp this container actually lets us filter each record type
    /// on. CloudKit only indexes the system timestamps when the schema says so
    /// (`___createTime` / `___modTime` marked Queryable in the console), and
    /// there is no way to ask other than trying. Learned once per launch so the
    /// refresh that runs every minute doesn't re-probe.
    private var learnedFilterField: [String: FilterField] = [:]

    /// Record types this container refused to sort newest-first, learned the
    /// same way — by asking. Reset at the start of each usage read, because it
    /// describes that read rather than the container forever.
    private var unsortableTypes: Set<String> = []

    /// What has been learned so far, in a form the cache file can hold, so the
    /// next launch doesn't repeat probes that already came back refused.
    var incrementalFilterFields: [String: String] {
        learnedFilterField.mapValues(\.rawValue)
    }

    func restoreIncrementalFilterFields(_ fields: [String: String]) {
        learnedFilterField = fields.compactMapValues(FilterField.init(rawValue:))
    }

    /// Which record types the last usage read could not sort newest-first. A
    /// read that cannot be sorted cannot stop at a record this device already
    /// holds, so it walks the whole type every time — worth recording, because
    /// nothing else on screen would ever say so.
    var unsortableRecordTypes: Set<String> { unsortableTypes }

    /// Ask the container again. A schema can gain a queryable index long after
    /// this app first asked, so a full refresh re-probes rather than trusting
    /// an answer from an earlier day.
    func forgetIncrementalFilterFields() {
        learnedFilterField = [:]
    }

    /// Run one record type's query, reading as little as the container allows.
    ///
    /// Two independent narrowings are attempted, because either can be
    /// unavailable:
    ///
    ///  - a server-side `creationDate`/`modificationDate` filter, which only
    ///    works when the schema marks that system timestamp Queryable;
    ///  - stopping at the first record `known` already holds, which needs
    ///    nothing from the schema beyond the newest-first sort.
    ///
    /// Two things public schemas commonly refuse are absorbed rather than
    /// reported: that sort, and that filter. Either one falls back to the
    /// broader query — a full result is always a valid answer, since the caller
    /// merges by record name.
    ///
    /// - Parameter known: record names already stored on this device. Only
    ///   meaningful for `.appendOnly` types: an upserted record keeps its name
    ///   while its contents change, so stopping at it would skip the update.
    private func queryAll(recordType: String,
                          modifiedSince: Date? = nil,
                          shape: ChangeShape = .appendOnly,
                          known: Set<String>? = nil,
                          onPartial: (([CKRecord]) -> Void)? = nil) async throws -> [CKRecord] {
        let boundary = shape == .appendOnly ? known : nil

        guard let modifiedSince else {
            return try await runFiltered(recordType: recordType,
                                         field: .none, since: nil, known: boundary,
                                         onPartial: onPartial)
        }

        for field in filterCandidates(for: recordType, shape: shape) {
            do {
                let records = try await runFiltered(recordType: recordType,
                                                    field: field, since: modifiedSince, known: boundary,
                                                    onPartial: onPartial)
                learnedFilterField[recordType] = field
                return records
            } catch {
                guard isFilterError(error) else { throw error }
                continue
            }
        }

        learnedFilterField[recordType] = FilterField.none
        return try await runFiltered(recordType: recordType,
                                     field: .none, since: nil, known: boundary,
                                     onPartial: onPartial)
    }

    /// What is worth trying for this record type, narrowed to one entry (or
    /// none) as soon as the container has answered once.
    private func filterCandidates(for recordType: String, shape: ChangeShape) -> [FilterField] {
        if let learned = learnedFilterField[recordType] {
            return learned.key == nil ? [] : [learned]
        }
        switch shape {
        case .appendOnly: return [.creation, .modification]
        case .upserted: return [.modification]
        }
    }

    private func runFiltered(recordType: String,
                             field: FilterField,
                             since: Date?,
                             known: Set<String>?,
                             onPartial: (([CKRecord]) -> Void)? = nil) async throws -> [CKRecord] {
        let predicate: NSPredicate
        if let key = field.key, let since {
            predicate = NSPredicate(format: "%K > %@", key, since as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: recordType, predicate: predicate)
        // Prefer newest-first, but many public schemas don't mark the creation
        // timestamp as sortable — fall back to an unsorted query if so.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            return try await runQuery(query, stoppingAtKnown: known, onPartial: onPartial)
        } catch {
            if isSortError(error) {
                query.sortDescriptors = []
                unsortableTypes.insert(recordType)
                // Unordered, there is no boundary to stop at: a known record can
                // sit anywhere in the results, so the whole type is read.
                //
                // And no cap either. Without the sort there is no "newest" to
                // keep — a cap would hand back whichever records the container
                // happened to page first and call it the answer, while the
                // caller went on to record the type as read to the end. That
                // turns a slow read into a wrong one, which is far worse.
                return try await runQuery(query, onPartial: onPartial)
            }
            throw error
        }
    }

    /// How many already-stored records in a row end the read. Records written
    /// in one batch can share a creation timestamp, and the order between those
    /// is not guaranteed to repeat, so a short run — rather than the very first
    /// one — is what marks the boundary.
    private static let knownRunToStop = 5

    /// How many records a read collects before handing what it has back to the
    /// caller mid-flight. A first launch reads thousands of records over a
    /// minute or more, and on a phone that read is very likely to be cut short
    /// — so the caller gets a chance to write what has arrived rather than
    /// losing all of it. Batched rather than per page, because each hand-over
    /// costs the caller a merge and a disk write.
    private static let partialBatch = 500

    /// - Parameter known: record names this device already holds. The query is
    ///   ordered newest-first and these record types are only ever appended to,
    ///   so a run of already-stored records is the boundary: everything past it
    ///   is older and already stored. Paging stops there, which is what keeps a
    ///   launch from re-reading the whole hub. Records the caller already has
    ///   are not collected, so an empty result means "nothing new".
    private func runQuery(_ query: CKQuery,
                          stoppingAtKnown known: Set<String>? = nil,
                          onPartial: (([CKRecord]) -> Void)? = nil) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var knownRun = 0
        // How much of `collected` the caller has already been shown.
        var handedOver = 0
        // Everything the read walked, including records skipped because this
        // device already holds them — that, not the collected count, is what
        // "how far along" means to someone watching the status line.
        var scanned = 0

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
                guard case .success(let record) = result else { continue }
                scanned += 1
                if let known, known.contains(record.recordID.recordName) {
                    knownRun += 1
                    if knownRun >= Self.knownRunToStop {
                        onProgress?(query.recordType, scanned)
                        return collected
                    }
                    continue
                }
                knownRun = 0
                collected.append(record)
            }
            onProgress?(query.recordType, scanned)
            if let onPartial, collected.count - handedOver >= Self.partialBatch {
                onPartial(Array(collected[handedOver...]))
                handedOver = collected.count
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

    /// The schema won't let us filter on `modificationDate` (not marked
    /// queryable in this container). The incremental read then degrades to a
    /// full one instead of reporting a failure.
    private func isFilterError(_ error: Error) -> Bool {
        let ck = error as NSError
        guard ck.domain == CKErrorDomain,
              ck.code == CKError.invalidArguments.rawValue else { return false }
        // "Field '___modTime' is not marked queryable" is what the server says.
        let msg = ck.localizedDescription.lowercased()
        return msg.contains("queryable") || msg.contains("modtime") || msg.contains("createtime")
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

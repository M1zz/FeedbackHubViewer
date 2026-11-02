//
//  SyncedBlob.swift
//  FeedbackHubViewer
//
//  키·값 저장소(1MB)에 담기에는 큰, 이 기기가 쌓은 기록을 기기 사이에서 하나로 —
//  키워드 순위 기록(추적 키워드 포함), 차트 기록, 스토어 리뷰 확인.
//
//  요약본(`HubSummarySync`)과 같은 자리, 같은 방법이다: 이 iCloud 계정의 **비공개** DB 에
//  레코드 하나 + 첨부 파일(CKAsset). 레코드 타입도 요약본의 `HubSummary` 를 그대로 쓰고
//  이름만 다르게 둔다 — 새 타입을 만들면 Production 스키마를 또 배포해야 하는데, 필드
//  (payload · generatedAt · generatedBy · schemaVersion)가 똑같아 그럴 까닭이 없다.
//
//  ## 합치는 규칙
//
//  갈아끼우지 않고 합친다(요약본과 같은 까닭). 무엇을 어떻게 합칠지는 값마다 다르므로
//  `merge` 를 받는다. 받아올 때 합친 것이 이 기기 것과 다르면 화면에 들이고, iCloud 것과
//  다르면 올린다. 이 기기에서 고치면 잠깐 기다렸다(연달아 고치는 것을 한 번에) 올린다.
//  남이 먼저 올렸으면 서버가 거절하고, 그때 받아 합쳐 한 번 더 올린다.
//
//  iCloud 가 없거나 실패하면 조용히 넘어간다 — 기록은 지금까지처럼 이 기기에 남는다.
//

import Foundation
import CloudKit

/// 비공개 DB 의 레코드 하나 — 압축한 바이트 덩어리를 읽고 쓴다.
actor CloudBlob {

    private let recordID: CKRecord.ID
    private let container = CKContainer(identifier: CloudKitService.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }
    /// 마지막으로 본 서버 레코드 — 변경 태그를 실어 보내려고.
    private var known: CKRecord?

    init(name: String) {
        recordID = CKRecord.ID(recordName: "viewer-\(name)")
    }

    /// iCloud 에 있는 것. 아직 아무도 안 올렸으면 nil.
    func fetch() async throws -> Data? {
        do {
            let record = try await database.record(for: recordID)
            known = record
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            return (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// 올린다. 남이 먼저 올렸으면 `resolve` 에 서버 것을 넘겨 합친 것으로 한 번 더.
    /// 실제로 올라간 바이트를 돌려준다.
    func publish(_ data: Data, resolve: @Sendable (Data) -> Data) async throws -> Data {
        do {
            try await save(data)
            return data
        } catch let error as CKError where Self.unwrap(error).code == .serverRecordChanged {
            known = Self.unwrap(error).serverRecord
            let theirs = try await fetch()
            let merged = theirs.map(resolve) ?? data
            try await save(merged)
            return merged
        }
    }

    private func save(_ data: Data) async throws {
        let packed = try (data as NSData).compressed(using: .zlib) as Data
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(recordID.recordName)-\(UUID().uuidString).z")
        try packed.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let record = known ?? CKRecord(recordType: HubSummarySync.recordType, recordID: recordID)
        record["payload"] = CKAsset(fileURL: url)
        record["generatedAt"] = Date() as NSDate
        record["generatedBy"] = HubSummary.deviceName as NSString
        record["schemaVersion"] = 1 as NSNumber

        let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                     savePolicy: .ifServerRecordUnchanged,
                                                     atomically: true)
        for (_, result) in saved.saveResults {
            switch result {
            case .success(let record): known = record
            case .failure(let error): throw error
            }
        }
    }

    private static func unwrap(_ error: CKError) -> CKError {
        guard error.code == .partialFailure,
              let inner = error.partialErrorsByItemID?.values.first as? CKError else { return error }
        return inner
    }
}

/// 가게 하나의 기록을 `CloudBlob` 과 잇는다.
///
/// 가게가 넘겨주는 것은 셋: 지금 값(`current`), 합친 값을 들이는 법(`adopt` — 다시 올리지
/// 않게 디스크에만 쓴다), 두 값을 합치는 법(`merge(local, remote)`).
@MainActor
final class SyncedBlob<Value: Codable & Equatable & Sendable> {

    private let blob: CloudBlob
    private let current: () -> Value?
    private let adopt: (Value) -> Void
    private let merge: @Sendable (Value, Value) -> Value
    private var pushTask: Task<Void, Never>?
    private var isPulling = false
    private var lastPull: Date?

    /// 마지막 실패. 설정 화면이 보여 줄 수 있다.
    private(set) var lastError: String?

    init(name: String,
         current: @escaping () -> Value?,
         adopt: @escaping (Value) -> Void,
         merge: @escaping @Sendable (Value, Value) -> Value) {
        blob = CloudBlob(name: name)
        self.current = current
        self.adopt = adopt
        self.merge = merge
    }

    /// iCloud 것을 받아 합친다. `minimumInterval` 안에 이미 받았으면 건너뛴다(앞으로 올 때마다).
    func pull(minimumInterval: TimeInterval = 0) async {
        guard !isPulling else { return }
        if let lastPull, Date().timeIntervalSince(lastPull) < minimumInterval { return }
        isPulling = true
        defer { isPulling = false }
        do {
            let data = try await blob.fetch()
            lastPull = Date()
            lastError = nil
            let local = current()
            guard let data, let remote = try? JSONDecoder().decode(Value.self, from: data) else {
                // 아직 아무도 안 올렸다 — 이 기기 것이 첫 판이다.
                if local != nil { schedulePush(after: 1) }
                return
            }
            guard let local else {
                adopt(remote)
                return
            }
            let merged = merge(local, remote)
            if merged != local { adopt(merged) }
            if merged != remote { schedulePush(after: 1) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 이 기기에서 고쳤다 — 잠깐 기다렸다 올린다. 그 사이 또 고치면 다시 기다린다.
    func schedulePush(after delay: TimeInterval = 8) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func push() async {
        guard let local = current(), let data = try? JSONEncoder().encode(local) else { return }
        let merge = self.merge
        do {
            let sent = try await blob.publish(data) { theirs in
                guard let remote = try? JSONDecoder().decode(Value.self, from: theirs),
                      let merged = try? JSONEncoder().encode(merge(local, remote)) else { return data }
                return merged
            }
            lastError = nil
            if sent != data, let merged = try? JSONDecoder().decode(Value.self, from: sent),
               let now = current() {
                // 올리는 사이 이 기기에서 또 고쳤을 수 있다 — 그것까지 합쳐 들인다.
                let combined = self.merge(now, merged)
                if combined != now { adopt(combined) }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}

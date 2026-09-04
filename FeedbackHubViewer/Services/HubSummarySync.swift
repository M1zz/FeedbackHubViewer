//
//  HubSummarySync.swift
//  FeedbackHubViewer
//
//  요약본 한 벌이 오가는 자리 — 이 iCloud 계정의 **비공개** 데이터베이스.
//
//  ## 왜 여기인가
//
//  허브의 공개 DB는 앱들이 쓰는 곳이고 이 뷰어에는 읽기 권한밖에 없다. 그래서
//  "내가 마지막으로 새로고침한 결과"를 둘 자리로는 처음부터 후보가 아니었다.
//  남은 것은 둘:
//
//   · `NSUbiquitousKeyValueStore` — 읽음·처리를 나누는 자리
//     (`ReviewStateSync`)다. 여기에는 못 쓴다. 한도가 앱 전체 1MB인데 요약본은
//     압축하고도 2MB 남짓이고, 앱이 늘고 날이 쌓이면 더 커진다.
//   · **비공개 DB의 레코드 + 첨부 파일(CKAsset)** — 크기 제한이 사실상 없고,
//     "지금 받아와라"가 분명한 한 번의 요청이다. 실행하자마자 받아와야 하는
//     것이므로 이쪽이 맞다. iCloud Drive 문서로 두면 언제 내려올지를 시스템이
//     정한다.
//
//  비공개 DB는 이 계정의 것이라 Security Role과 무관하다 — 공개 DB 읽기 권한이
//  없는 계정에서도 요약본은 오간다.
//
//  ## 스키마를 한 번 배포해야 한다
//
//  CloudKit의 레코드 타입은 컨테이너 단위라, 비공개 DB에 쓰는 것이라도
//  Production 스키마에 있어야 한다. Development에서는 처음 저장할 때 자동으로
//  만들어지지만 Production은 그렇지 않다. 한 번만 해 두면 되는 일이고, 안 해
//  두면 이 파일이 오류를 사람이 읽을 수 있는 문장으로 바꿔 화면에 올린다
//  (`Failure.message`). 순서는 README §2-2에.
//
//  ## 부딪혔을 때
//
//  두 기기가 동시에 새로고침을 끝낼 수 있다. 저장은 받아올 때 쥔 변경 태그를
//  걸고 하므로, 그 사이 남이 올렸으면 서버가 거절한다. 거절당하면 그때 받아서
//  합치고 한 번 더 올린다 — 평소에는 내려받기 없이 올리기 한 번이고, 부딪힌
//  때에만 값을 치른다.
//

import Foundation
import CloudKit

/// 비공개 DB에 놓인 요약본 하나를 읽고 쓴다.
///
/// `actor`인 이유는 압축이다. 요약본은 JSON 10MB를 zlib에 통과시키는 일이라
/// 메인 스레드에서 하면 그 사이 화면이 멈춘다. 여기 담아 두면 인코딩도
/// 디코딩도 저절로 메인 밖에서 돈다 — 캐시 파일이 액터에 담긴 것과 같은 이유다.
actor HubSummarySync {

    /// 레코드 타입 하나, 레코드 하나. 이름을 고정해 두면 조회가 필요 없다 —
    /// 인덱스도, Queryable 설정도 걸리지 않는 `fetch(withRecordID:)` 한 번이다.
    static let recordType = "HubSummary"

    /// 환경마다 다른 레코드. Development 빌드가 Production 숫자를 보면 안 되는
    /// 것은 캐시 파일이 나뉜 이유와 같다.
    private static func recordID(_ environment: CloudKitEnvironment) -> CKRecord.ID {
        CKRecord.ID(recordName: "hub-summary-\(environment.restPathComponent)")
    }

    private enum Field {
        static let payload = "payload"
        static let generatedAt = "generatedAt"
        static let generatedBy = "generatedBy"
        static let schemaVersion = "schemaVersion"
    }

    /// 요약본을 못 쓰게 만든 이유. 오류를 그대로 보여 주는 대신 무엇을 하면
    /// 되는지까지 적는다 — 대부분은 로그인 아니면 스키마 배포다.
    enum Failure: Error {
        /// iCloud 로그인이 없거나 꺼져 있다.
        case noAccount
        /// Production 스키마에 `HubSummary` 타입이 아직 없다.
        case schemaMissing
        /// 그 밖의 CloudKit 오류.
        case other(String)

        var message: String {
            switch self {
            case .noAccount:
                return "iCloud에 로그인하면 기기 사이에서 같은 숫자를 봅니다."
            case .schemaMissing:
                return "iCloud에 요약본을 둘 자리가 아직 없습니다. CloudKit Console → 컨테이너 → Schema에서 Development의 HubSummary 레코드 타입을 Production으로 배포하세요."
            case .other(let text):
                return text
            }
        }
    }

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    private let environment: CloudKitEnvironment

    /// 마지막으로 서버에서 본 레코드. 저장할 때 이것을 고쳐서 보내야 변경
    /// 태그가 실려 나가고, 그래야 남이 먼저 올린 것을 덮어쓰지 않는다.
    private var known: CKRecord?

    init(environment: CloudKitEnvironment = .current) {
        self.environment = environment
        container = CKContainer(identifier: CloudKitService.containerIdentifier)
    }

    // MARK: - 받아오기

    /// iCloud에 있는 요약본. 아직 아무도 올린 적이 없으면 `nil`을 돌려준다 —
    /// 그건 오류가 아니라 첫 기기라는 뜻이다.
    func fetch() async throws -> HubSummary? {
        do {
            let record = try await database.record(for: Self.recordID(environment))
            known = record
            guard let asset = record[Field.payload] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            let summary = try HubSummaryPayload.decode(data)
            // 이 빌드가 못 읽는 새 모양이면 못 본 것으로 한다. 지우지도,
            // 덮어쓰지도 않는다 — 그 요약본을 읽는 기기가 따로 있다.
            guard summary.version <= HubSummary.currentVersion else { return nil }
            return summary
        } catch let error as CKError where error.code == .unknownItem {
            // 레코드가 없거나(첫 기기) 타입 자체가 아직 없다. 둘 다 "받아올
            // 것이 없다"이고, 구별은 올릴 때 난다.
            return nil
        } catch {
            throw Self.failure(for: error)
        }
    }

    // MARK: - 올리기

    /// 이 기기가 방금 만든 요약본을 올린다.
    ///
    /// 남이 먼저 올렸으면 서버가 거절한다. 그때는 `resolve`에 서버의 것을
    /// 넘겨 합친 결과를 받아 한 번 더 시도한다. 한 번만 — 두 번 연달아
    /// 부딪히는 일은 1분마다 도는 자동 갱신에서도 사실상 없고, 놓쳐도 다음
    /// 새로고침이 다시 올린다.
    func publish(_ summary: HubSummary,
                 resolve: (HubSummary) -> HubSummary) async throws {
        do {
            try await save(summary)
        } catch let error as CKError where Self.unwrap(error).code == .serverRecordChanged {
            // 거절당한 응답에 서버의 레코드가 실려 온다. 그것을 쥐고 다시
            // 만들어야 변경 태그가 맞는다.
            known = Self.unwrap(error).serverRecord
            do {
                let theirs = try await fetch()
                try await save(theirs.map(resolve) ?? summary)
            } catch {
                throw Self.failure(for: error)
            }
        } catch {
            throw Self.failure(for: error)
        }
    }

    private func save(_ summary: HubSummary) async throws {
        let data = try HubSummaryPayload.encode(summary)
        // CKAsset은 파일에서만 만들 수 있다. 임시 파일은 저장이 끝나면 지운다 —
        // 요약본은 메가바이트 단위라 남겨 둘 것이 아니다.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-summary-\(UUID().uuidString).z")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let record = known ?? CKRecord(recordType: Self.recordType,
                                       recordID: Self.recordID(environment))
        record[Field.payload] = CKAsset(fileURL: url)
        record[Field.generatedAt] = summary.generatedAt as NSDate
        record[Field.generatedBy] = summary.generatedBy as NSString
        record[Field.schemaVersion] = summary.version as NSNumber

        // 새 레코드에는 변경 태그가 없어서 정책이 통하지 않는다. 서버에 이미
        // 있으면 unknownItem이 아니라 serverRecordChanged로 거절되고, 위에서
        // 받아 합친다.
        let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                     savePolicy: .ifServerRecordUnchanged,
                                                     atomically: true)
        for (_, result) in saved.saveResults {
            if case .success(let record) = result { known = record }
            if case .failure(let error) = result { throw error }
        }
    }

    // MARK: - 오류 번역

    /// 배치 하나짜리 쓰기가 거절되면 CloudKit은 그것을 `partialFailure`로 한 겹
    /// 싸서 돌려주기도 하고, 그대로 돌려주기도 한다. 어느 쪽이든 알고 싶은 것은
    /// 안쪽의 레코드 오류 하나뿐이다.
    private static func unwrap(_ error: CKError) -> CKError {
        guard error.code == .partialFailure,
              let inner = error.partialErrorsByItemID?.values.first as? CKError else { return error }
        return inner
    }

    private static func failure(for error: Error) -> Failure {
        guard let ck = (error as? CKError).map(unwrap) else { return .other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .noAccount
        case .invalidArguments, .serverRejectedRequest, .unknownItem:
            // Production 스키마에 타입이 없을 때 CloudKit이 돌려주는 것들이다.
            // 문구는 버전마다 다르지만 결론은 하나 — 배포가 안 됐다.
            return .schemaMissing
        case .networkUnavailable, .networkFailure:
            return .other("네트워크에 연결할 수 없어 요약본을 주고받지 못했습니다.")
        case .quotaExceeded:
            return .other("iCloud 저장 공간이 부족해 요약본을 올리지 못했습니다.")
        default:
            return .other("iCloud 요약본 오류: \(ck.localizedDescription)")
        }
    }
}

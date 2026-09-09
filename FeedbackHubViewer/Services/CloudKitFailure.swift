//
//  CloudKitFailure.swift
//  FeedbackHubViewer
//
//  What a CloudKit error means to the person reading the screen.
//

import Foundation
import CloudKit

/// A failed CloudKit read, translated once.
///
/// The failure is shown in two places — beside each record type that could not
/// be read, and once as the advice under the list — so what happened is kept
/// apart from what to do about it. Repeating "인터넷 연결을 확인하세요" beside
/// every failed type reads as several separate problems instead of one.
///
/// Translating in one place is also what keeps the advice honest: a network
/// timeout used to arrive on screen as a raw `CKErrorDomain error 4` under a
/// line telling the reader to go check Security Roles in the CloudKit Console,
/// which is the wrong screen for a dropped connection.
enum CloudKitFailure {
    /// The request never left, or died on the way.
    case network
    /// iCloud answered, but asked us to come back later.
    case serverBusy
    case notAuthenticated
    case permission
    /// The query does not fit the schema deployed in this environment — an
    /// unknown record type, or a field that is not queryable/sortable.
    case schema(String)
    /// Anything we have nothing better to say about; the payload is already a
    /// finished sentence.
    case other(String)

    init(_ error: Error) {
        let ck = error as NSError
        guard ck.domain == CKErrorDomain else {
            self = .other(ck.localizedDescription)
            return
        }
        switch ck.code {
        case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
            self = .network
        case CKError.serviceUnavailable.rawValue, CKError.requestRateLimited.rawValue:
            self = .serverBusy
        case CKError.notAuthenticated.rawValue:
            self = .notAuthenticated
        case CKError.permissionFailure.rawValue:
            self = .permission
        case CKError.invalidArguments.rawValue, CKError.unknownItem.rawValue:
            self = .schema(ck.localizedDescription)
        default:
            self = .other("CloudKit 오류: \(ck.localizedDescription)")
        }
    }

    /// What happened, with no instruction in it.
    var summary: String {
        switch self {
        case .network: return "네트워크에 연결할 수 없습니다."
        case .serverBusy: return "iCloud 서버가 일시적으로 응답하지 않습니다."
        case .notAuthenticated: return "iCloud 인증이 필요합니다."
        case .permission: return "읽기 권한이 없습니다."
        case .schema(let detail): return "이 환경의 스키마로는 실행할 수 없는 쿼리입니다. (\(detail))"
        case .other(let detail): return detail
        }
    }

    /// What to do about it — `nil` when there is nothing useful to say.
    var advice: String? {
        switch self {
        case .network: return "인터넷 연결을 확인한 뒤 다시 새로고침하세요."
        case .serverBusy: return "잠시 후 다시 새로고침하세요."
        case .notAuthenticated: return "시스템 설정에서 iCloud에 로그인하세요."
        case .permission: return "CloudKit Console → Security Roles에서 admin 역할에 read 권한이 있는지 확인하세요."
        case .schema: return "CloudKit Console에서 해당 스키마가 이 환경에 배포되어 있고, 조회에 쓰는 필드가 Queryable·Sortable인지 확인하세요."
        case .other: return nil
        }
    }

    /// The two halves as one sentence, for a place that shows a single line.
    var message: String {
        [summary, advice].compactMap { $0 }.joined(separator: " ")
    }
}

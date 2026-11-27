//
//  FeedbackScreenshots.swift
//  FeedbackHubViewer
//
//  사용자가 피드백에 붙인 사진(LeeoKit 의 `screenshot1`~`screenshot3`, CKAsset).
//
//  CloudKit 이 내려 준 CKAsset 파일은 CloudKit 의 임시 캐시에 있어 언제든 지워진다.
//  피드백 목록은 글자로만 디스크에 남기므로(`Feedback.allFields`), 사진은 받는 순간
//  이 앱의 캐시 폴더로 옮겨 둔다. 캐시가 비었으면(다른 기기에서 처음 열었거나 시스템이
//  비웠을 때) 상세를 열 때 그 레코드의 사진 필드만 다시 받는다.
//

import Foundation
import CloudKit

enum FeedbackScreenshots {
    /// LeeoKit 이 사진을 싣는 필드. 순서대로 보여 준다.
    static let fieldKeys = ["screenshot1", "screenshot2", "screenshot3"]

    /// 레코드 하나의 사진이 놓이는 곳: Caches/FeedbackScreenshots/<recordName>/
    static func directory(forFeedback id: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FeedbackScreenshots", isDirectory: true)
            .appendingPathComponent(safeName(id), isDirectory: true)
    }

    static func fileURL(forFeedback id: String, key: String) -> URL {
        directory(forFeedback: id).appendingPathComponent("\(key).jpg")
    }

    /// 이미 옮겨 둔 사진. `keys` 순서를 지킨다.
    static func cached(forFeedback id: String, keys: [String]) -> [URL] {
        keys.map { fileURL(forFeedback: id, key: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 레코드에 실린 사진을 캐시로 옮긴다. 이미 있으면 그대로 둔다.
    static func keep(_ record: CKRecord) {
        let id = record.recordID.recordName
        for key in fieldKeys {
            guard let source = (record[key] as? CKAsset)?.fileURL,
                  FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = fileURL(forFeedback: id, key: key)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: target)
        }
    }

    /// 레코드 이름은 CloudKit 이 만든 UUID 지만, 예전 레코드가 무엇을 썼을지 몰라
    /// 경로에 쓸 수 없는 글자는 바꾼다.
    private static func safeName(_ id: String) -> String {
        String(id.map { $0 == "/" || $0 == ":" ? "_" : $0 })
    }
}

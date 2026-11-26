//
//  CacheFileSync.swift
//  FeedbackHubViewer
//
//  디스크 캐시 파일 몇 개를 기기 사이에서 하나로 — App Store Connect 에서 받은 것
//  (판매 · 상품 · 스토어 문구 · 리뷰 · 버전 · 분석 결과 · 받은 때).
//
//  맥이 여러 대면 지금까지는 기기마다 같은 리포트를 처음부터 다시 받았다. 받은 것은
//  기기마다 똑같으므로, 한 기기가 받으면 나머지는 그 파일을 iCloud 에서 받아 그대로
//  쓴다. 받은 때(`connect-fetched-at`)도 함께 가서, 다른 기기가 방금 받은 것은 이 기기도
//  다시 묻지 않는다(`AppStoreConnectStore.shouldFetch`).
//
//  자리는 `SyncedBlob` — 키워드 · 차트 기록과 같은 비공개 DB 레코드 + 첨부 파일이다.
//  여기 것은 사람이 만든 기록이 아니라 다시 받을 수 있는 캐시라, 파일마다 **늦게 쓴 쪽**이
//  이긴다. 받은 때 기록만은 열쇠마다 늦은 쪽을 남긴다 — 두 기기가 서로 다른 것을 받았을 수 있다.
//

import Foundation

/// 파일 이름 → 그 파일의 내용과 쓴 때.
struct CacheFileBundle: Codable, Equatable, Sendable {

    struct File: Codable, Equatable, Sendable {
        /// 초 단위로 자른다 — 파일 수정 시각으로 오가며 끝자리가 달라지지 않게.
        var savedAt: Date
        var data: Data
    }

    var files: [String: File] = [:]

    /// 다른 기기에서 받은 묶음을 디스크에 들였다 — `AppStoreConnectStore` 밖에서 그 파일을 읽는 곳이 듣는다.
    static let didAdopt = Notification.Name("CacheFileBundle.didAdopt")

    /// 열쇠 → 날짜 꼴이라 열쇠마다 합치는 파일.
    static let keyedDates: Set<String> = ["connect-fetched-at"]

    /// 디스크에 지금 있는 것.
    static func read(_ names: [String]) -> CacheFileBundle {
        var bundle = CacheFileBundle()
        for name in names {
            guard let url = CacheFile.url(name), let data = try? Data(contentsOf: url),
                  let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate else { continue }
            bundle.files[name] = File(savedAt: modified.wholeSeconds, data: data)
        }
        return bundle
    }

    /// 파일마다 늦게 쓴 쪽. 같으면 이 기기 것.
    static func merge(_ local: CacheFileBundle, _ remote: CacheFileBundle) -> CacheFileBundle {
        var merged = local
        for (name, theirs) in remote.files {
            guard let ours = local.files[name] else {
                merged.files[name] = theirs
                continue
            }
            if keyedDates.contains(name), let combined = mergeDates(ours, theirs) {
                merged.files[name] = combined
            } else if theirs.savedAt > ours.savedAt {
                merged.files[name] = theirs
            }
        }
        return merged
    }

    private static func mergeDates(_ a: File, _ b: File) -> File? {
        let decoder = JSONDecoder()
        guard let left = try? decoder.decode([String: Date].self, from: a.data),
              let right = try? decoder.decode([String: Date].self, from: b.data) else { return nil }
        let combined = left.merging(right) { max($0, $1) }
        if combined == left { return a }
        if combined == right { return b }
        guard let data = try? CacheFile.encoder.encode(combined) else { return nil }
        return File(savedAt: max(a.savedAt, b.savedAt), data: data)
    }

    /// 이 기기 것과 다른 파일만 디스크에 쓴다. 수정 시각을 받은 쪽의 때로 맞춰, 다음에
    /// 읽어도 같은 묶음이 되게(그래야 다시 올리지 않는다). 쓴 것이 있으면 true.
    @discardableResult
    func write(over local: CacheFileBundle) -> Bool {
        var wrote = false
        for (name, file) in files where local.files[name] != file {
            guard let url = CacheFile.url(name), (try? file.data.write(to: url, options: .atomic)) != nil else { continue }
            try? FileManager.default.setAttributes([.modificationDate: file.savedAt], ofItemAtPath: url.path)
            wrote = true
        }
        return wrote
    }
}

private extension Date {
    var wholeSeconds: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down)) }
}

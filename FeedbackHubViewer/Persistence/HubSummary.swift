//
//  HubSummary.swift
//  FeedbackHubViewer
//
//  기기마다 다른 숫자를 하나로 — 마지막으로 새로고침한 결과를 iCloud에 두고,
//  실행할 때 그것부터 받아온다.
//
//  ## 왜 달랐나
//
//  지금까지 각 기기는 자기가 읽어 낸 것만 가지고 자기 화면을 만들었다. 허브는
//  같은데 읽어 낸 것이 달랐다:
//
//   · `UsageEvent`는 최신부터 읽다가 이미 가진 레코드를 만나면 멈춘다. 한때
//     5,000건에서 끊고도 "끝까지 읽었다"고 표시하던 시절이 있었고, 그때 생긴
//     구멍은 그 기기에 영영 남는다 — 다음 읽기가 그 앞에서 멈추므로.
//   · 날짜 버킷(`UsageRollups`)은 그 기기가 읽은 이벤트만큼만 쌓인다. 지난달에
//     산 아이폰은 지난달부터의 추이만 가지고 있다.
//   · 원본 이벤트는 90일, 진단은 1,000건까지만 남긴다. 언제부터 켜 뒀느냐에
//     따라 남은 것이 다르다.
//
//  그래서 맥에서 "7일 활성 120명"이 아이폰에서는 80명이었다. 둘 다 거짓말은
//  아니지만, 둘 다 믿을 수 없게 된다.
//
//  ## 무엇을 나누나
//
//  화면에 나오는 숫자만 따로 추려서 나누는 방법도 있었다. 그렇게 하지 않았다 —
//  통계 화면은 스펙(`ProjectStatsSpec`)에 적힌 대로 원본 스냅샷을 그 자리에서
//  집계하므로, "숫자만" 이라는 경계선을 그을 수가 없다. 대신 **새로고침이 만들어
//  낸 결과 전체**를 나눈다. 레코드 캐시와 날짜 버킷, 즉 이 앱이 디스크에 쓰는
//  바로 그것이다.
//
//  그래도 되는 이유는 크기다. 같은 내용이 반복되는 JSON이라 zlib이 잘 듣는다 —
//  이 계정 기준 스냅샷 6,300건이 8MB에서 600KB로, 전체가 2MB 남짓이다. 그 값에
//  모든 화면이 기기 사이에서 정확히 같아진다.
//
//  ## 합치는 규칙
//
//  받은 것으로 **갈아끼우지 않고 합친다**. 갈아끼우면 마지막에 새로고침한
//  기기가 이긴다 — 구멍이 있는 쪽이 마지막이면 멀쩡하던 쪽까지 구멍이 난다.
//  합집합은 그런 순서 의존이 없다: 어느 기기가 언제 올리든 모두가 둘을 합한
//  것으로 수렴한다.
//
//   · 레코드는 이름(`recordName`)으로 합친다 — `RecordMerge.byID`.
//   · 날짜 버킷은 칸마다 더 완전한 쪽을 취한다 — `UsageRollups.merge`.
//   · 워터마크는 늦은 쪽이다. 상대의 레코드를 방금 받았으니 상대가 읽은
//     지점까지는 이쪽도 읽은 셈이다.
//
//  예외는 "캐시 비우고 전체 다시 불러오기" 하나다. 그것은 이 기기 기준으로
//  처음부터 다시 만들겠다는 뜻이므로, 끝나고 올리는 요약본이 iCloud의 것을
//  덮어쓴다 — 합치면 방금 버린 것이 그대로 돌아온다.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// iCloud에 놓인 "마지막 요약본" 한 벌.
struct HubSummary: Codable {

    /// 모양이 바뀌면 올린다. 못 읽는 버전은 무시하고 이 기기 것을 쓴다 —
    /// 지우지는 않는다. 새 버전을 쓰는 다른 기기가 여전히 그것을 읽고 있다.
    static let currentVersion = 1

    var version = HubSummary.currentVersion
    /// 이 요약본을 만든 새로고침이 끝난 시각. 화면의 "업데이트"와 같은 값이고,
    /// 받아올지 말지를 정하는 기준이다.
    var generatedAt: Date
    /// 만든 기기 이름. 숫자가 어디서 온 것인지 사람이 알아볼 수 있게 —
    /// 병합 규칙에는 쓰이지 않는다.
    var generatedBy: String
    /// 레코드 캐시. 디스크에 쓰는 것과 같은 값이다.
    var hub: CachedHub
    /// 날짜 버킷. 화면의 모든 사용 통계가 여기서 나온다.
    var rollups: UsageRollups

    init(generatedAt: Date, generatedBy: String, hub: CachedHub, rollups: UsageRollups) {
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.hub = hub
        self.rollups = rollups
    }

    /// 이 기기 이름. 맥은 컴퓨터 이름, 아이폰·아이패드는 기기 이름.
    static var deviceName: String {
        #if os(macOS)
        let name = Host.current().localizedName ?? ""
        return name.isEmpty ? "이 Mac" : name
        #else
        return UIDevice.current.name
        #endif
    }
}

// MARK: - 합치기

extension CachedHub {

    /// 다른 기기가 올린 캐시를 이쪽에 합친다. 레코드는 이름으로, 워터마크는
    /// 늦은 쪽으로. 필드 학습 결과(`filterFields`)와 레코드 타입 이름은 이미
    /// 알아낸 쪽이 이긴다 — 둘 다 "한 번 물어보면 답이 정해지는" 것들이다.
    ///
    /// - Returns: 이쪽이 실제로 달라졌는지.
    @discardableResult
    mutating func merge(_ other: CachedHub) -> Bool {
        let before = (feedback.count, snapshots.count, events.count, crashes.count)

        feedback = RecordMerge.byID(other.feedback, into: feedback) {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
        snapshots = RecordMerge.byID(other.snapshots, into: snapshots) {
            ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast)
        }
        events = RecordMerge.byID(other.events, into: events) { $0.occurredAt > $1.occurredAt }
        crashes = RecordMerge.byID(other.crashes, into: crashes) {
            ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast)
        }

        for (type, date) in other.watermarks where (watermarks[type] ?? .distantPast) < date {
            watermarks[type] = date
        }
        if resolvedRecordType == nil { resolvedRecordType = other.resolvedRecordType }
        for (type, field) in other.filterFields where filterFields[type] == nil {
            filterFields[type] = field
        }
        if savedAt < other.savedAt { savedAt = other.savedAt }

        return before != (feedback.count, snapshots.count, events.count, crashes.count)
    }
}

// MARK: - 짐 싸기

/// 요약본을 CloudKit에 실을 수 있는 크기로 만드는 한 겹.
///
/// 압축하는 이유는 요금이 아니라 시간이다. 스냅샷은 레코드마다 같은 필드
/// 이름이 되풀이되는 JSON이라 8MB가 600KB로 줄어든다 — 실행할 때 받아오는
/// 것이므로, 그 차이가 곧 첫 숫자가 뜨기까지의 시간이다.
enum HubSummaryPayload {

    /// JSON으로 만들고 zlib으로 줄인다.
    static func encode(_ summary: HubSummary) throws -> Data {
        let json = try JSONEncoder().encode(summary)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    /// 풀고 되돌린다. 압축을 못 풀면 압축 안 된 JSON으로도 한 번 시도한다 —
    /// 지금은 늘 압축해서 쓰지만, 읽는 쪽이 더 너그러워서 손해 볼 것은 없다.
    static func decode(_ data: Data) throws -> HubSummary {
        if let json = try? (data as NSData).decompressed(using: .zlib) as Data {
            return try JSONDecoder().decode(HubSummary.self, from: json)
        }
        return try JSONDecoder().decode(HubSummary.self, from: data)
    }
}

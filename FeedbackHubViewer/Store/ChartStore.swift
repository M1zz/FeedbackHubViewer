//
//  ChartStore.swift
//  FeedbackHubViewer
//
//  차트 화면의 상태: 어느 나라를 볼지, 지금까지 본 것, 그리고 확인 자체.
//
//  `KeywordStore` 처럼 따로 둔다. 읽는 곳(공개 차트 피드)도 파일도 제 것이고, 허브와
//  나누는 것은 "내 앱이 누구냐" — App Store 앱 번호 목록 하나뿐이다. 그 목록은 키워드
//  가게가 허브의 번들 id 를 스토어 앱에 이어 둔 것(`KeywordStore.trackId(for:)`)을 그대로
//  받는다. 그래서 앱을 따로 등록하는 화면이 없다 — 허브에 있는 앱이면 저절로 따라온다.
//
//  확인 한 번:
//
//    1. 앱 정보 — `lookup` 한 번에 모든 앱을 묶어 묻는다(무료인지 · 장르 · 맥인지).
//    2. 피드 — (기기, 차트, 장르, 나라) 마다 **한 번만** 받고, 모든 앱을 그 목록에서 찾는다.
//       앱이 늘어도 같은 장르 · 같은 나라면 요청 수는 그대로다.
//    3. 기록 — 차트에 든 것만 한 장으로 적고, 파일에 한 번 쓴다.
//
//  차트는 몇 시간 단위로 움직이고 피드는 무겁다. 그래서 저절로는 12시간에 한 번(나라가
//  30개를 넘으면 하루 한 번), 그것도 와이파이 같은 싼 네트워크에서만 보고, 더 자주 보고
//  싶으면 화면의 "지금 확인" 을 누른다(그건 어디서든 받는다).
//

import Foundation
import SwiftUI

@MainActor
final class ChartStore: ObservableObject {

    @Published private(set) var history = ChartHistory()
    @Published private(set) var isScanning = false
    @Published private(set) var progress: (done: Int, total: Int)?
    @Published var errorMessage: String?

    /// 볼 나라. 기기마다 따로 — 화면 고르기이지 기록의 일부가 아니다.
    @Published var countries: [String] {
        didSet { UserDefaults.standard.set(countries, forKey: Self.countriesKey) }
    }

    private static let countriesKey = "chartCountries"
    private static let fileName = "chart-ranks"
    /// 저절로 다시 볼 때까지의 간격. 순위도 숫자라 하루에 한 번이면 된다("지금 확인"은 언제든).
    var autoInterval: TimeInterval { 24 * 60 * 60 }
    static let manyCountries = 30
    private static let maxConcurrency = 6

    private var restored = false

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.countriesKey)
        countries = saved?.isEmpty == false ? saved! : ChartStorefronts.defaults
    }

    // MARK: - Lifecycle

    /// 지난번에 본 것을 디스크에서 바로 그린다. 공개 데이터라 CloudKit 환경과 상관없이
    /// 파일 하나다(`CacheFile.url` 의 환경 없는 쪽).
    func restore() {
        guard !restored else { return }
        restored = true
        if let saved = CacheFile.read(ChartHistory.self, at: CacheFile.url(Self.fileName)) {
            history = saved
        }
    }

    /// 볼 때가 됐으면 본다 — 마지막 확인이 12시간 넘었거나, 처음 보는 앱이 생겼을 때.
    /// 허브의 앱 목록이 바뀔 때마다 불려도 되도록 싸게 끝난다.
    func startIfDue(trackIds: Set<Int>) {
        guard !trackIds.isEmpty, !isScanning else { return }
        let isStale = history.lastScan.map { Date().timeIntervalSince($0.date) > autoInterval } ?? true
        let hasNewApp = !trackIds.isSubset(of: Set(history.apps.keys))
        guard isStale || hasNewApp else { return }
        Task { await scan(trackIds: trackIds, automatic: true) }
    }

    // MARK: - Scan

    /// `automatic` 은 사람이 누르지 않은 확인 — 셀룰러 · 저데이터 모드에서는 피드를 받지 않는다.
    func scan(trackIds: Set<Int>, automatic: Bool = false) async {
        guard !isScanning, !trackIds.isEmpty else { return }
        isScanning = true
        errorMessage = nil
        defer {
            isScanning = false
            progress = nil
        }

        // 1. 앱 정보 — 전부 한 요청에 묶어 매번 다시 묻는다. 무료였던 앱이 유료가 되면
        //    볼 차트가 바뀌고, 그걸 모르면 엉뚱한 차트만 보고 "100위 밖" 이라고 말한다.
        let found = await ChartFeed.lookup(Array(trackIds))
        for (id, app) in found { history.apps[id] = app }
        let apps = trackIds.compactMap { history.apps[$0] }
        guard !apps.isEmpty else {
            errorMessage = "App Store 에서 앱 정보를 받지 못했습니다."
            return
        }

        // 2. 필요한 피드를 한 번씩만.
        let countries = self.countries
        var slots = Set<ChartSlot>()
        for app in apps {
            for country in countries {
                for kind in app.kinds {
                    slots.insert(ChartSlot(platform: app.platform, kind: kind, genreId: nil, country: country))
                    if let genre = app.genreId {
                        slots.insert(ChartSlot(platform: app.platform, kind: kind, genreId: genre, country: country))
                    }
                }
            }
        }
        let wanted = Set(apps.map(\.trackId))
        let list = Array(slots)
        progress = (0, list.count)

        var hits: [ChartHit] = []
        var failed = 0
        var done = 0
        await withTaskGroup(of: (ChartSlot, [Int]?).self) { group in
            var iterator = list.makeIterator()
            func enqueue() {
                guard let slot = iterator.next() else { return }
                group.addTask { (slot, try? await ChartFeed.rankedIDs(for: slot, thrifty: automatic)) }
            }
            for _ in 0..<Self.maxConcurrency { enqueue() }
            for await (slot, ids) in group {
                done += 1
                progress = (done, list.count)
                if let ids {
                    for (index, id) in ids.enumerated() where wanted.contains(id) {
                        hits.append(ChartHit(trackId: id, slot: slot, rank: index + 1))
                    }
                } else {
                    failed += 1
                }
                enqueue()
            }
        }

        // 다 실패했으면 기록하지 않는다 — "아무 데도 없음" 으로 적히면 순위가 다 빠진 것처럼 보인다.
        guard failed < list.count else {
            // 저절로 하는 확인이 셀룰러에서 막힌 것은 오류가 아니다 — 다음 와이파이 때 본다.
            if !automatic { errorMessage = "차트를 받지 못했습니다. 네트워크를 확인해 주세요." }
            return
        }
        if failed > 0 {
            errorMessage = "차트 \(list.count)개 중 \(failed)개는 받지 못했습니다. 그 칸의 순위는 이번에 빠져 있을 수 있습니다."
        }

        // 3. 한 장 적고, 한 번 쓴다.
        history.record(ChartScan(date: Date(), countries: countries, hits: hits, failedFeeds: failed))
        CacheFile.write(history, to: CacheFile.url(Self.fileName))
    }

    // MARK: - Reading

    /// 나라 하나를 볼 때 받는 피드 수 — 이 앱들이 드는 (기기, 차트, 장르) 조합 수.
    /// 아직 앱 정보를 모르면(처음) 앱 수 × 4 로 어림한다.
    var feedsPerCountry: Int {
        guard !history.apps.isEmpty else { return 4 }
        var combos = Set<String>()
        for app in history.apps.values {
            for kind in app.kinds {
                combos.insert("\(app.platform)-\(kind)-all")
                if let genre = app.genreId { combos.insert("\(app.platform)-\(kind)-\(genre)") }
            }
        }
        return combos.count
    }

    func app(_ trackId: Int?) -> ChartApp? { trackId.flatMap { history.apps[$0] } }
}

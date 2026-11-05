//
//  MarketingStore.swift
//  FeedbackHubViewer
//
//  마케팅 자료를 들고, 기기 사이에서 하나로 맞춘다.
//
//  맥에서 기획하고 아이폰에서 올리는 일이 흔하다. 그래서 활동은 iCloud 키·값 저장소에 둔다
//  (`ReviewStateSync` 와 같은 길, 같은 까닭). 활동마다 `updatedAt` 이 늦은 쪽이 이기고, 지운
//  것은 `isDeleted` 로 남겨 지웠다는 사실도 전한다. iCloud 를 못 쓰면 이 기기 파일만으로 돈다.
//

import Foundation
import UserNotifications

@MainActor
final class MarketingStore: ObservableObject {
    static let shared = MarketingStore()

    /// 지운 것까지 전부. 화면은 `items` 를 읽는다.
    @Published private var all: [UUID: MarketingItem] = [:]

    private let cloud = NSUbiquitousKeyValueStore.default
    private static let cloudKey = "marketing-items-v1"
    private static let fileName = "marketing-items"
    private var observer: NSObjectProtocol?

    private init() {
        let saved = CacheFile.read([MarketingItem].self, at: CacheFile.url(Self.fileName)) ?? []
        all = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: Self.newer)
        startSync()
        importSeedIfNeeded()
        clearReminders()
    }

    // MARK: - 읽기

    /// 지우지 않은 활동, 올릴 때가 이른 것부터(날짜 없는 것은 뒤).
    var items: [MarketingItem] {
        all.values.filter { !$0.isDeleted }.sorted(by: Self.order)
    }

    func items(for project: String?) -> [MarketingItem] {
        items.filter { project == nil || $0.project == project }
    }

    func item(_ id: UUID) -> MarketingItem? { all[id].flatMap { $0.isDeleted ? nil : $0 } }

    private static func order(_ a: MarketingItem, _ b: MarketingItem) -> Bool {
        switch (a.plannedAt, b.plannedAt) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.createdAt < b.createdAt
        }
    }

    // MARK: - 쓰기

    func save(_ item: MarketingItem) {
        var item = item
        item.updatedAt = Date()
        all[item.id] = item
        commit()
    }

    func add(_ items: [MarketingItem]) {
        for item in items { all[item.id] = item }
        commit()
    }

    func delete(_ id: UUID) {
        guard var item = all[id] else { return }
        item.isDeleted = true
        item.updatedAt = Date()
        all[id] = item
        commit()
    }

    // MARK: - 시드

    private static let seedKey = "marketing-seed-imported"

    /// 번들에 채워 둔 활동을 시드 판마다 한 번 들인다.
    ///
    /// 없는 것은 더하고, 있는 것은 **한 번도 손대지 않은 것만**(고친 시각 = 만든 시각 = 첫 시드)
    /// 새 판의 글로 바꾼다. 고쳤거나 올렸거나 미뤘거나 지운 것은 그대로 둔다.
    private func importSeedIfNeeded() {
        guard UserDefaults.standard.string(forKey: Self.seedKey) != MarketingSeed.version else { return }
        UserDefaults.standard.set(MarketingSeed.version, forKey: Self.seedKey)
        var changed = false
        for seed in MarketingSeed.load() {
            guard let existing = all[seed.id] else {
                all[seed.id] = seed
                changed = true
                continue
            }
            // 시드가 넣었거나 시드가 바꾼 그대로인 것 — 사람이 고친 것은 무엇이든 이보다 늦다.
            let untouched = existing.createdAt <= MarketingSeed.firstStamp
                && existing.updatedAt <= MarketingSeed.refreshStamp && !existing.isDeleted
            guard untouched else { continue }
            var next = existing
            next.channel = seed.channel
            next.title = seed.title
            next.angle = seed.angle
            next.plannedAt = seed.plannedAt
            next.stage = seed.stage
            next.slides = seed.slides
            next.script = seed.script
            next.scriptEn = seed.scriptEn
            next.body = seed.body
            next.bodyEn = seed.bodyEn
            next.updatedAt = MarketingSeed.refreshStamp
            all[seed.id] = next
            changed = true
        }
        if changed { commit() }
    }

    // MARK: - 맞추기

    private func commit() {
        CacheFile.write(Array(all.values), to: CacheFile.url(Self.fileName))
        pushToCloud()
    }

    private static func newer(_ a: MarketingItem, _ b: MarketingItem) -> MarketingItem {
        a.updatedAt >= b.updatedAt ? a : b
    }

    private func startSync() {
        guard cloud.synchronize() else { return }
        pullFromCloud()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { _ in
            Task { @MainActor in MarketingStore.shared.pullFromCloud() }
        }
    }

    /// 다른 기기가 바꾼 것을 들인다. 새로고침 단추도 이것을 부른다.
    func pullFromCloud() {
        cloud.synchronize()
        guard let data = cloud.data(forKey: Self.cloudKey),
              let remote = try? JSONDecoder().decode([MarketingItem].self, from: data) else { return }
        var merged = all
        for item in remote { merged[item.id] = merged[item.id].map { Self.newer($0, item) } ?? item }
        guard merged != all else { return }
        all = merged
        CacheFile.write(Array(all.values), to: CacheFile.url(Self.fileName))
    }

    private func pushToCloud() {
        // 쓰기 전에 저쪽 것과 합친다 — 통째로 덮으면 다른 기기의 하루가 사라진다.
        if let data = cloud.data(forKey: Self.cloudKey),
           let remote = try? JSONDecoder().decode([MarketingItem].self, from: data) {
            for item in remote { all[item.id] = all[item.id].map { Self.newer($0, item) } ?? item }
        }
        // 지운 지 30일이 지난 것은 더 전할 까닭이 없다.
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let kept = all.values.filter { !$0.isDeleted || $0.updatedAt > cutoff }
        guard let data = try? JSONEncoder().encode(Array(kept)) else { return }
        cloud.set(data, forKey: Self.cloudKey)
        cloud.synchronize()
    }

    // MARK: - 옛 알림

    /// 예전 판이 걸어 둔 "올렸나요?" 알림을 걷는다.
    private func clearReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(
                withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("marketing-") })
        }
    }
}

//
//  MarketingStore.swift
//  FeedbackHubViewer
//
//  마케팅 활동을 들고, 기기 사이에서 하나로 맞추고, 올리기로 한 때가 되면 묻는다.
//
//  맥에서 기획하고 아이폰에서 올리는 일이 흔하다. 그래서 활동은 iCloud 키·값 저장소에 둔다
//  (`ReviewStateSync` 와 같은 길, 같은 까닭). 활동마다 `updatedAt` 이 늦은 쪽이 이기고, 지운
//  것은 `isDeleted` 로 남겨 지웠다는 사실도 전한다. iCloud 를 못 쓰면 이 기기 파일만으로 돈다.
//
//  "올렸나요?" 는 두 곳에서 묻는다. 올리기로 한 때에 알림을 미리 걸어 두고(앱이 꺼져 있어도),
//  앱 안에서는 그때가 지난 활동을 마케팅 칸 맨 위와 사이드바 뱃지로 묻는다 — 답할 때까지.
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
        // "올렸나요?" 는 시각이 지나는 것만으로 생긴다 — 바뀐 데이터가 없어도 뱃지가 서게
        // 1분마다 한 번 화면에 알린다.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - 읽기

    /// 지우지 않은 활동, 올릴 때가 이른 것부터(날짜 없는 것은 뒤).
    var items: [MarketingItem] {
        all.values.filter { !$0.isDeleted }.sorted(by: Self.order)
    }

    func items(for project: String?) -> [MarketingItem] {
        items.filter { project == nil || $0.project == project }
    }

    /// 올렸는지 답해야 하는 것.
    func awaitingConfirmation(for project: String?, now: Date = Date()) -> [MarketingItem] {
        items(for: project).filter { $0.needsConfirmation(now: now) }
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

    /// "올렸어요".
    func markPosted(_ id: UUID, url: String = "") {
        guard var item = all[id] else { return }
        item.stage = .posted
        item.postedAt = Date()
        if !url.isEmpty { item.postURL = url }
        save(item)
    }

    /// "아직이에요" — 내일 같은 시각에 다시 묻는다.
    func snooze(_ id: UUID, days: Int = 1) {
        guard var item = all[id] else { return }
        item.snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: Date())
        save(item)
    }

    /// "안 올릴래요".
    func skip(_ id: UUID) {
        guard var item = all[id] else { return }
        item.stage = .skipped
        save(item)
    }

    // MARK: - 시드

    private static let seedKey = "marketing-seed-imported"

    /// 번들에 채워 둔 활동을 한 번 들인다. 이미 있는 것(지운 것 포함)은 건드리지 않는다.
    private func importSeedIfNeeded() {
        guard UserDefaults.standard.string(forKey: Self.seedKey) != MarketingSeed.version else { return }
        let fresh = MarketingSeed.load().filter { all[$0.id] == nil }
        UserDefaults.standard.set(MarketingSeed.version, forKey: Self.seedKey)
        guard !fresh.isEmpty else { return }
        for item in fresh { all[item.id] = item }
        commit()
    }

    // MARK: - 맞추기

    private func commit() {
        CacheFile.write(Array(all.values), to: CacheFile.url(Self.fileName))
        pushToCloud()
        scheduleReminders()
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
        scheduleReminders()
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

    // MARK: - 묻기

    private static let reminderPrefix = "marketing-"

    /// 올리기로 한 때에 "올렸나요?" 알림. 걸어 둔 것을 다 지우고 다시 건다.
    func scheduleReminders(now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        let upcoming = items.filter { $0.stage.isOpen }
            .compactMap { item -> (MarketingItem, Date)? in
                let at = [item.plannedAt, item.snoozedUntil].compactMap { $0 }.max()
                return at.flatMap { $0 > now ? (item, $0) : nil }
            }
            .prefix(40) // iOS 는 앱마다 예약 알림 64개까지
        // 묻겠다고 한 것이라 허락을 한 번 청한다(이미 정했으면 시스템이 다시 묻지 않는다).
        if !upcoming.isEmpty { Task { await NotificationService.requestAuthorization() } }
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for (item, at) in upcoming {
                let content = UNMutableNotificationContent()
                content.title = "올렸나요? · \(item.channel) \(item.kind.label)"
                content.body = item.hasMaterial
                    ? "\(item.title) — 올렸으면 마케팅 칸에서 \"올렸어요\" 를 눌러 주세요."
                    : "\(item.title) — 아직 자료가 비어 있어요. 마케팅 칸에서 준비하거나 미뤄 주세요."
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: Self.reminderPrefix + item.id.uuidString,
                                                 content: content, trigger: trigger))
            }
        }
    }
}

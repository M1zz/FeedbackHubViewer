//
//  SyncedDefaults.swift
//  FeedbackHubViewer
//
//  기기에 남던 작은 설정 · 확인 상태를 iCloud 키·값 저장소로 기기 사이에서 맞춘다.
//
//  읽음 · 처리(`ReviewStateSync`)와 같은 저장소, 다른 키다. 여기 오는 것은 사람이 고친
//  것 중 작은 것 — 숨긴 앱, 활동 정의, 뱃지 · 알림 종류, 키워드 · 차트 나라, 칸마다 확인한
//  뱃지, 소식을 읽은 시각. 큰 기록(키워드 순위 · 차트 · 리뷰 확인)은 비공개 DB 로
//  (`ViewerStateSync`).
//
//  `UserDefaults` 는 그대로 로컬 미러다. 가게들은 지금처럼 `UserDefaults` 에서 읽고, 쓸
//  때만 `SyncedDefaults.set` 을 부른다. 다른 기기가 바꾸면 미러를 고치고
//  `SyncedDefaults.changed` 를 울린다 — 가게는 그것을 듣고 다시 읽는다.
//
//  합치는 규칙은 키마다 다르다. 설정은 마지막 쓰기가 이긴다(저장소가 이미 그렇다).
//  늘어나기만 하는 것(빨강 읽음)은 합집합, 시각은 늦은 쪽, 칸별 확인은 칸마다 늦은 쪽.
//  iCloud 가 없으면 아무 일도 하지 않고 지금까지처럼 기기 안에서만 기억한다.
//

import Foundation

@MainActor
enum SyncedDefaults {

    /// 다른 기기가 바꾼 키가 미러에 들어왔다. `userInfo["keys"]` 는 바뀐 `UserDefaults` 키.
    static let changed = Notification.Name("SyncedDefaults.changed")

    /// 저장소 안의 이름은 앞에 붙여 다른 키(`reviewState-…`, 리드 · 마케팅)와 섞이지 않게.
    private static let prefix = "pref."

    /// 기기 사이에서 맞추는 `UserDefaults` 키와 합치는 법. nil 이면 저장소 것이 이긴다.
    private static let keys: [String: ((Any?, Any?) -> Any?)?] = [
        "hiddenProjects": nil,
        "activityDefinitions": nil,
        "badgeKinds": nil,
        "alertKinds": nil,
        "keywordCountries": nil,
        "chartCountries": nil,
        SectionChanges.marksKey: { SectionChanges.mergeSyncedMarks($0, $1) },
        SectionChanges.releaseAckKey: { union($0, $1) },
        SectionChanges.keywordDueAckKey: { union($0, $1) },
        "newsLastReadAt": { later($0, $1) },
        // 고마운 분들 — 지운 것이 되살아나지 않게 합치지 않고 마지막 쓰기가 이긴다.
        SupportersStore.defaultsKey: nil,
    ]

    private static var store: NSUbiquitousKeyValueStore { .default }
    private static var observer: NSObjectProtocol?
    private static var defaults: UserDefaults { .standard }

    /// 저장소를 쓸 수 있는지. 설정 화면이 한 줄로 알린다.
    private(set) static var isAvailable = false

    /// 앱이 뜰 때 한 번 — 가게들이 `UserDefaults` 를 읽기 전에. 저장소에 이미 있는 것을
    /// 미러로 내리고, 이 기기에만 있던 것은 올린다.
    static func start() {
        guard observer == nil else { return }
        isAvailable = store.synchronize()
        reconcile(Array(keys.keys), notify: false)
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let accountChanged = reason == NSUbiquitousKeyValueStoreAccountChange
            Task { @MainActor in
                let ours = accountChanged
                    ? Array(keys.keys)
                    : (changed ?? []).filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
                        .filter { keys[$0] != nil }
                guard !ours.isEmpty else { return }
                reconcile(ours, notify: true)
            }
        }
    }

    /// 로컬 미러와 저장소에 함께 쓴다. nil 이면 둘 다에서 지운다.
    static func set(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        guard keys[key] != nil else { return }
        if let value {
            store.set(value, forKey: prefix + key)
        } else {
            store.removeObject(forKey: prefix + key)
        }
    }

    // MARK: - 합치기

    private static func reconcile(_ names: [String], notify: Bool) {
        var touched: [String] = []
        for name in names {
            guard let merge = keys[name] else { continue }
            let local = defaults.object(forKey: name)
            let remote = store.object(forKey: prefix + name)
            let result: Any?
            if let merge {
                result = merge(local, remote)
            } else {
                result = remote ?? local
            }
            if !same(result, local) {
                if let result { defaults.set(result, forKey: name) } else { defaults.removeObject(forKey: name) }
                touched.append(name)
            }
            if isAvailable, let result, !same(result, remote) {
                store.set(result, forKey: prefix + name)
            }
        }
        if notify, !touched.isEmpty {
            NotificationCenter.default.post(name: changed, object: nil, userInfo: ["keys": touched])
        }
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }

    private static func union(_ a: Any?, _ b: Any?) -> Any? {
        let left = a as? [String] ?? []
        let right = b as? [String] ?? []
        if a == nil && b == nil { return nil }
        return Array(Set(left).union(right)).sorted()
    }

    private static func later(_ a: Any?, _ b: Any?) -> Any? {
        switch (a as? Date, b as? Date) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}

extension Notification {
    /// `SyncedDefaults.changed` 에 실린 키 가운데 하나라도 있는가.
    func touches(_ keys: String...) -> Bool {
        let changed = userInfo?["keys"] as? [String] ?? []
        return keys.contains { changed.contains($0) }
    }
}

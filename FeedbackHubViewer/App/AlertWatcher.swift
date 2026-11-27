//
//  AlertWatcher.swift
//  FeedbackHubViewer
//
//  새 피드백 · 리뷰를 알려 주는 쪽. 알림이 켜져 있는 동안만 돈다.
//
//  - 피드백 · 진단: CloudKit 푸시(`PushSubscriptions`)가 앱이 꺼져 있어도 알린다. 푸시가
//    오면 `HubAppDelegate` 가 깨워서 목록을 바로 새로 읽는다. 여기 감시는 푸시를 놓쳤을
//    때의 그물이다.
//  - 리뷰: Apple 이 푸시를 주지 않는다. 맥은 앱이 떠 있는 동안(창을 닫아도) 5분마다 보고
//    리뷰는 30분 지난 앱만 다시 받는다(`reviewFreshness`). 아이폰은 iOS 가 허락할 때
//    백그라운드 새로고침으로 본다 - 언제일지는 iOS 가 정해서 몇 시간 늦을 수 있다.
//
//  숫자(사용 현황 · 이벤트)는 이 감시가 읽지 않는다. 하루에 한 번이다(`numbersInterval`).
//

import Foundation
import SwiftUI
import UserNotifications
import CloudKit
#if os(iOS)
import BackgroundTasks
import UIKit
#else
import AppKit
#endif

@MainActor
final class AlertWatcher: ObservableObject {

    /// 맥 · 앱이 앞에 있는 동안 몇 초마다 보나.
    static let interval: TimeInterval = 5 * 60
    /// 아이폰 백그라운드 새로고침 id. Info.plist 의 BGTaskSchedulerPermittedIdentifiers 와 같아야 한다.
    nonisolated static let refreshTaskID = "com.Ysoup.FeedbackHubViewer.alerts"

    private var loop: Task<Void, Never>?
    private weak var store: FeedbackStore?
    private weak var purchases: AppStoreConnectStore?

    /// 스토어를 잇고 감시를 건다. 여러 번 불러도 한 번만 건다.
    func start(store: FeedbackStore, purchases: AppStoreConnectStore) {
        attach(store: store, purchases: purchases)
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.interval))
                if Task.isCancelled { break }
                await self?.check()
            }
        }
    }

    private func attach(store: FeedbackStore, purchases: AppStoreConnectStore) {
        self.store = store
        self.purchases = purchases
        purchases.onNewReviews = { [weak store] bundleID, reviews in
            store?.announceNewReviews(bundleID: bundleID, reviews: reviews)
        }
        HubAppDelegate.onPush = { [weak store] in
            await store?.load(mode: .incremental)
        }
    }

    /// 한 번 보기. 알림이 꺼져 있으면 아무것도 안 한다.
    func check() async {
        guard let store, let purchases, store.notificationsEnabled else { return }
        await store.load(mode: .incremental)
        guard store.alertKinds.contains(.review), purchases.isConfigured else { return }
        let apps = store.allProjectKeys.filter { !store.isExcluded($0) }
        await purchases.loadReviews(bundleIDs: apps)
    }

    #if os(iOS)
    /// iOS 가 백그라운드에서 깨웠을 때. 다음 차례를 먼저 걸어 둔다.
    func backgroundCheck(store: FeedbackStore, purchases: AppStoreConnectStore) async {
        Self.scheduleAppRefresh()
        attach(store: store, purchases: purchases)
        store.start()
        await store.awaitRestore()
        await check()
    }

    /// 다음 백그라운드 새로고침을 부탁한다. 30분보다 일찍은 안 부른다 - 리뷰를 그보다 자주
    /// 받지 않는다.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ [AlertWatcher.scheduleAppRefresh] \(error)")
        }
    }
    #endif
}

/// 원격 알림(CloudKit 푸시)을 받으려고 등록하고, 앱이 떠 있을 때 푸시가 오면 목록을 새로 읽는다.
#if os(iOS)
final class HubAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var onPush: (() async -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = ForegroundPurchaseAlerts.shared
        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [HubAppDelegate] 원격 알림 등록 실패: \(error)")
    }

    @MainActor
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await Self.onPush?()
        return .newData
    }
}
#else
final class HubAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var onPush: (() async -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
        UNUserNotificationCenter.current().delegate = ForegroundPurchaseAlerts.shared
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [HubAppDelegate] 원격 알림 등록 실패: \(error)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor in await Self.onPush?() }
    }
}
#endif

/// 앱이 떠 있을 때 온 알림은 시스템이 숨긴다. 결제 알림만은 떠 있어도 배너로 보인다 —
/// 허브를 보던 중이라도 결제는 바로 알아야 하고, 설정의 "시험 결제 알림 보내기" 도 앱 안에서 누른다.
/// 피드백 · 진단 푸시는 그대로 숨긴다(앱이 떠 있으면 목록이 새로 읽혀 거기 보인다).
final class ForegroundPurchaseAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundPurchaseAlerts()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let push = CKNotification(fromRemoteNotificationDictionary: info)
        return push?.subscriptionID == PushSubscriptions.purchaseSubscriptionID ? [.banner, .sound, .list] : []
    }
}

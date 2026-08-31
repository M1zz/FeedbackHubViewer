//
//  NotificationService.swift
//  FeedbackHubViewer
//
//  App icon badge and local notifications for what arrives in the hub.
//
//  These are *local* notifications posted after a refresh finds records the
//  viewer hasn't seen before, so they land while the app is running (the 자동
//  갱신 toggle keeps it polling every minute). Push that wakes a closed app
//  would need the Push Notifications capability and a CKQuerySubscription —
//  see README §3.
//

import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#endif

enum NotificationService {

    // MARK: - Permission

    /// Ask once; returns whether alerts/badges are allowed now.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Badge

    /// The app icon badge. 0 clears it.
    static func setBadge(_ count: Int) {
        #if os(macOS)
        // The Dock tile needs no permission, unlike the notification badge.
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        #else
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        #endif
    }

    // MARK: - Notifications

    /// "새 피드백 3건" — one notification per refresh, not per record, so a
    /// batch that arrives together doesn't bury the screen.
    static func notifyNewFeedback(count: Int, projects: [String]) {
        guard count > 0 else { return }
        let scope = projects.isEmpty ? "" : " · " + projects.prefix(3).joined(separator: ", ")
            + (projects.count > 3 ? " 외 \(projects.count - 3)개" : "")
        post(id: "new-feedback",
             title: "새 피드백 \(count)건",
             body: "허브에 새 피드백이 도착했습니다\(scope)")
    }

    /// Diagnostics are the other thing worth interrupting for.
    static func notifyNewCrashes(count: Int, projects: [String]) {
        guard count > 0 else { return }
        let scope = projects.isEmpty ? "" : " · " + projects.prefix(3).joined(separator: ", ")
        post(id: "new-crash",
             title: "새 진단 \(count)건",
             body: "크래시·멈춤 리포트가 올라왔습니다\(scope)")
    }

    private static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // A unique id per post: reusing one id replaces the previous alert,
        // which would hide a second batch that arrives a minute later.
        let request = UNNotificationRequest(identifier: "\(id)-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

//
//  NotificationService.swift
//  FeedbackHubViewer
//
//  App icon badge and local notifications for what arrives in the hub.
//
//  These are *local* notifications posted after a refresh finds records the
//  viewer hasn't seen before, so they land while the app is running. 피드백 ·
//  진단은 그 위에 CloudKit 푸시(`PushSubscriptions`)가 따로 있어서 앱이 꺼져 있어도
//  오고, 푸시가 걸린 종류는 여기서 다시 알리지 않는다. 리뷰는 Apple 이 푸시를 주지
//  않아 이 로컬 알림뿐이다(`AlertWatcher`).
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

    /// 한 앱에 새 리뷰. 한 건이면 별점과 제목까지, 여럿이면 수와 가장 낮은 별점.
    static func notifyNewReviews(app: String, reviews: [CustomerReview]) {
        guard let first = reviews.first else { return }
        let stars = { (rating: Int) in String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating)) }
        if reviews.count == 1 {
            let text = [first.title, first.body].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            post(id: "new-review",
                 title: "\(app) 새 리뷰 \(stars(first.rating))",
                 body: text.isEmpty ? "App Store 에 새 리뷰가 달렸습니다" : text)
        } else {
            let lowest = reviews.map(\.rating).min() ?? first.rating
            post(id: "new-review",
                 title: "\(app) 새 리뷰 \(reviews.count)건",
                 body: "가장 낮은 별점 \(stars(lowest))")
        }
    }

    // MARK: - 앱 소식

    /// 큰 소식 하나(`NewsKind.isBig`). 제목이 이미 앱 이름을 말한다.
    static func notifyNews(title: String, body: String, app: String) {
        post(id: "news", title: title, body: body)
    }

    /// 한 번에 큰 소식이 넷 이상이면 한 장으로 — 화면을 덮지 않게.
    static func notifyNewsSummary(_ items: [(app: String, title: String)]) {
        guard !items.isEmpty else { return }
        let lines = items.prefix(3).map(\.title)
        let more = items.count > 3 ? "\n외 \(items.count - 3)건" : ""
        post(id: "news", title: "내 앱 소식 \(items.count)건", body: lines.joined(separator: "\n") + more)
    }

    /// 아침 묶음. 미리 예약해 두어 앱이 꺼져 있어도 울린다. 같은 id 로 다시 걸면 앞의 예약을
    /// 바꾸고, 줄이 없으면 예약을 지운다.
    static func scheduleNewsDigest(id: String, at date: Date, lines: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard !lines.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "어제부터 내 앱 소식 \(lines.count)건"
        content.body = lines.prefix(4).joined(separator: "\n") + (lines.count > 4 ? "\n외 \(lines.count - 4)건" : "")
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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

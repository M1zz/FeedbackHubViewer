//
//  AppStoreConnectStore+Funnels.swift
//  FeedbackHubViewer
//
//  구독 이벤트 리포트를 모으는 곳. 판매 리포트처럼 계정 전체가 하루 한 파일이라,
//  날짜별로 한 번 받으면 모든 앱이 그 안에 있고, 지난 날은 디스크에 두고 다시 받지 않는다.
//
//  판매 리포트와 따로 받는다. 구독을 파는 앱이 없는 계정이면 30번의 요청이 헛걸음이라,
//  구독 상품이 있는 앱을 열었을 때만 부른다.
//

import Foundation

extension AppStoreConnectStore {

    func loadSubscriptionEvents(force: Bool = false) async {
        guard let client, let vendor = credentials?.vendorNumber?.trimmingCharacters(in: .whitespaces),
              !vendor.isEmpty else { return }
        guard force || (subscriptionEvents == nil && !isLoadingSubscriptionEvents) else { return }
        isLoadingSubscriptionEvents = true
        subscriptionEventsError = nil
        defer { isLoadingSubscriptionEvents = false }

        let calendar = Calendar(identifier: .gregorian)
        let window = (1...Self.salesDays).compactMap { offset -> (key: String, date: Date)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (AppStoreConnect.day.string(from: date), date)
        }
        // 디스크에 있던 날들로 먼저 그린다.
        if subscriptionEvents == nil {
            let stored = window.compactMap { subscriptionReportCache[$0.key] }
            if !stored.isEmpty {
                subscriptionEvents = SubscriptionEventWindow(lines: stored.flatMap { $0 }, days: Self.salesDays, missingDays: 0)
            }
        }
        defer {
            CacheFile.write(subscriptionReportCache.filter { Self.keepsDay($0.key, $0.value) },
                            to: Self.subscriptionEventsFile)
        }

        var lines: [SubscriptionEventLine] = []
        var missingDays = 0
        for (key, date) in window {
            if let cached = subscriptionReportCache[key] { lines += cached; continue }
            do {
                let day = try await client.subscriptionEvents(on: date, vendorNumber: vendor)
                if Self.keepsDay(key, day) { subscriptionReportCache[key] = day }
                lines += day
            } catch {
                // 키 · 권한 문제면 서른 번 되풀이할 이유가 없다.
                if let failure = error as? AppStoreConnect.Failure {
                    switch failure {
                    case .unauthorized, .forbidden, .missing:
                        subscriptionEventsError = failure.localizedDescription
                        return
                    default: break
                    }
                }
                missingDays += 1
            }
        }
        subscriptionEvents = SubscriptionEventWindow(lines: lines, days: Self.salesDays, missingDays: missingDays)
    }

    func forgetSubscriptionEvents() {
        subscriptionEvents = nil
        subscriptionEventsError = nil
        subscriptionReportCache = [:]
        CacheFile.remove(Self.subscriptionEventsFile)
    }
}

//
//  AppStoreConnect+Subscriptions.swift
//  FeedbackHubViewer
//
//  구독 이벤트 리포트(SUBSCRIPTION_EVENT) — 판매 요약이 가르지 못하는 것을 가른다.
//
//  판매 요약(SALES)의 구독 줄은 "이날 돈이 들어온 구독"이다. 처음 산 사람과 석 달째
//  갱신한 사람이 한 줄에 섞여 있어서, 그걸로는 "체험을 시작한 사람 중 몇이 돈을
//  냈나"를 물을 수 없다. 구독 이벤트 리포트는 일어난 일을 이름으로 적는다 — 체험 시작,
//  체험 뒤 유료 전환, 갱신, 해지, 환불. 깔때기는 이것으로만 그릴 수 있다.
//
//  이벤트 이름은 Apple 이 정한 영어 원문이다("Start Introductory Price", "Paid
//  Subscription from Introductory Price", "Renew", "Cancel" …). 모르는 이름이 와도
//  버리지 않고 원문 그대로 센다 — Apple 이 이름을 늘리면 화면에 그대로 드러난다.
//

import Foundation

/// 구독 이벤트 리포트의 한 줄에서 필요한 것만.
struct SubscriptionEventLine: Hashable, Codable {
    /// 앱의 Apple ID — 판매 요약의 앱 줄 Apple Identifier 와 같은 값.
    let appAppleID: String
    let event: String
    let quantity: Int
}

extension AppStoreConnect {

    /// 이 리포트의 버전은 해마다 오른다. 요청이 버전 때문에 거절되면 다음 것으로.
    static let subscriptionEventVersions = ["1_4", "1_3"]

    /// 하루치 구독 이벤트. 그날 이벤트가 없거나 아직 안 나왔으면 빈 배열(404).
    func subscriptionEvents(on date: Date, vendorNumber: String) async throws -> [SubscriptionEventLine] {
        var lastFailure: Error?
        for version in Self.subscriptionEventVersions {
            let (data, status) = try await send(url("v1/salesReports", [
                "filter[frequency]": "DAILY",
                "filter[reportType]": "SUBSCRIPTION_EVENT",
                "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": vendorNumber,
                "filter[reportDate]": Self.day.string(from: date),
                "filter[version]": version
            ]), accept: "application/a-gzip")
            if status == 404 { return [] }
            do {
                try check(data, status)
            } catch Failure.http(400, let detail) {
                // 버전이 틀린 400 이면 다음 버전을 시도한다. 다른 400 도 같은 모양이라
                // 마지막 버전까지 틀리면 그때 알린다.
                lastFailure = Failure.http(400, detail)
                continue
            }
            guard let text = Self.gunzip(data).flatMap({ String(data: $0, encoding: .utf8) }) else { throw Failure.decoding }
            return Self.parseSubscriptionEvents(text)
        }
        throw lastFailure ?? Failure.decoding
    }

    static func parseSubscriptionEvents(_ text: String) -> [SubscriptionEventLine] {
        var rows = text.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !rows.isEmpty else { return [] }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        guard let app = header.firstIndex(of: "App Apple ID"),
              let event = header.firstIndex(of: "Event"),
              let quantity = header.firstIndex(of: "Quantity") else { return [] }
        return rows.compactMap { row in
            guard row.count > max(app, event, quantity) else { return nil }
            let name = row[event].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return SubscriptionEventLine(appAppleID: row[app].trimmingCharacters(in: .whitespaces),
                                         event: name,
                                         quantity: Int(Double(row[quantity]) ?? 0))
        }
    }
}

/// 최근 N일 구독 이벤트를 앱별로 접은 것.
struct SubscriptionEventWindow {
    let days: Int
    let missingDays: Int
    /// 앱 Apple ID → 이벤트 원문 → 수.
    let byApp: [String: [String: Int]]

    init(lines: [SubscriptionEventLine], days: Int, missingDays: Int) {
        self.days = days
        self.missingDays = missingDays
        var byApp: [String: [String: Int]] = [:]
        for line in lines {
            byApp[line.appAppleID, default: [:]][line.event, default: 0] += line.quantity
        }
        self.byApp = byApp
    }

    func summary(appleID: String) -> SubscriptionSummary {
        SubscriptionSummary(events: byApp[appleID] ?? [:])
    }
}

/// 한 앱의 구독 이벤트를 깔때기가 읽을 말로 묶은 것.
struct SubscriptionSummary {
    /// 이벤트 원문 → 수. 많은 것부터 보여 줄 때 쓴다.
    let events: [String: Int]

    private func sum(_ matches: (String) -> Bool) -> Int {
        events.filter { matches($0.key) }.reduce(0) { $0 + $1.value }
    }

    /// 체험 · 할인 오퍼로 시작("Start Introductory Price", "Start Promotional Offer" …).
    var offerStarts: Int { sum { $0.hasPrefix("Start ") } }
    /// 체험 · 할인이 끝나고 돈을 내기 시작("Paid Subscription from …").
    var paidFromOffer: Int { sum { $0.hasPrefix("Paid Subscription from") } }
    /// 오퍼 없이 바로 유료 구독.
    var directSubscribes: Int { sum { $0 == "Subscribe" } }
    var renewals: Int { sum { $0.hasPrefix("Renew") && !$0.contains("Billing Retry") } }
    var cancels: Int { sum { $0.hasPrefix("Cancel") } }
    var refunds: Int { sum { $0.hasPrefix("Refund") } }
    /// 새로 돈을 내기 시작한 구독 — 바로 구독 + 오퍼 뒤 유료. 갱신은 뺀다.
    var newPaid: Int { directSubscribes + paidFromOffer }

    var isEmpty: Bool { events.isEmpty }
}

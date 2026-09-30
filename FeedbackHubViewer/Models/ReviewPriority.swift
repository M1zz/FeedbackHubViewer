//
//  ReviewPriority.swift
//  FeedbackHubViewer
//
//  "어느 앱을 먼저 볼까" — ReviewManager 의 우선순위 대시보드(AppWatch Scorer)를 옮긴 것.
//
//  앱마다 두 축으로 점수를 낸다.
//
//    위험 — 돈을 버는 앱인데 다운로드가 꺾이거나 평점이 흔들린다. 불을 꺼야 할 앱.
//    기회 — 이미 벌고 있고 오르는 중이라, 손대면 더 커질 앱.
//
//    우선순위 = max(위험, 기회) + 0.15 × min(위험, 기회)
//
//  한쪽만 강해도 위로 올라오고, 둘 다 강하면 그보다 조금 더 위로 간다.
//
//  **원본과 다른 점 하나.** 원본은 "매출"을 달러 하나로 더했지만, 판매 리포트의 수익금은
//  나라마다 통화가 달라 환율 없이는 더할 수 없다. 틀린 합을 점수에 넣느니 통화가 없는
//  숫자 — **돈을 낸 인앱 결제 건수** — 를 "버는 앱" 신호로 쓴다. 수익금은 통화별로 따로
//  적어 옆에 보여 준다.
//
//  **없는 신호는 0이 아니다.** 판매자 번호가 없으면 결제·다운로드 신호가 통째로 없고,
//  리뷰가 없는 앱은 평점 신호가 없다. 그런 신호는 0으로 더하지 않고 가중치의 분모에서
//  뺀다 — 그래야 남은 신호만으로도 0~100 을 고르게 쓴다.
//

import Foundation

struct PriorityAnalysis: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let rows: [PriorityRow]
    /// 판매 리포트를 쓸 수 있었나. 아니면 리뷰만으로 낸 점수다.
    let usedSales: Bool
}

struct PriorityRow: Identifiable, Codable, Hashable {
    /// 번들 ID(= 프로젝트 키).
    let id: String
    let name: String
    /// 최근 30일 돈을 낸 인앱 결제.
    let paidPurchases: Int
    /// 통화별 수익금 "₩12,000 · $4.20".
    let proceedsLabel: String
    let firstDownloads: Int
    /// 30일을 반으로 갈라 뒤 절반이 앞 절반보다 몇 % 많은가. nil 이면 가를 수 없었다.
    let trendPct: Double?
    let recentRating: Double?
    let ratingDelta: Double?
    let reviewCount: Int
    let unanswered: Int

    let risk: Double
    let opportunity: Double
    let priority: Double
    let flags: [PriorityFlag]
}

struct PriorityFlag: Codable, Hashable {
    enum Kind: String, Codable { case money, surge, drop, lowRating, ratingDrop, opportunity, unanswered }
    let kind: Kind
    let text: String

    var systemImage: String {
        switch kind {
        case .money: return "wonsign.circle"
        case .surge: return "chart.line.uptrend.xyaxis"
        case .drop: return "chart.line.downtrend.xyaxis"
        case .lowRating: return "star.slash"
        case .ratingDrop: return "star.leadinghalf.filled"
        case .opportunity: return "arrow.up.right.circle"
        case .unanswered: return "bubble.left.and.exclamationmark.bubble.right"
        }
    }

    var isBad: Bool { [.drop, .lowRating, .ratingDrop, .unanswered].contains(kind) }
}

enum PrioritySort: String, CaseIterable, Identifiable {
    case priority = "우선순위"
    case risk = "위험"
    case opportunity = "기회"
    case purchases = "결제"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .priority: return "flag"
        case .risk: return "exclamationmark.triangle"
        case .opportunity: return "arrow.up.right.circle"
        case .purchases: return "creditcard"
        }
    }

    func sorted(_ rows: [PriorityRow]) -> [PriorityRow] {
        switch self {
        case .priority: return rows.sorted { $0.priority > $1.priority }
        case .risk: return rows.sorted { $0.risk > $1.risk }
        case .opportunity: return rows.sorted { $0.opportunity > $1.opportunity }
        case .purchases: return rows.sorted { $0.paidPurchases > $1.paidPurchases }
        }
    }
}

/// 점수 한 줄을 만들 재료.
struct PriorityInput {
    let key: String
    let name: String
    let paidPurchases: Int?
    let proceedsLabel: String
    let firstDownloads: Int?
    /// 날짜순 하루 첫 다운로드. 4일이 안 되면 추세를 가르지 않는다.
    let dailyDownloads: [Int]
    let reviews: [CustomerReview]
}

enum PriorityScorer {

    // 위험 축 안의 가중치(합 1).
    static let riskMoney = 0.40, riskDrop = 0.30, riskReviews = 0.30
    // 기회 축 안의 가중치(합 1).
    static let oppMoney = 0.45, oppSurge = 0.40, oppRating = 0.15

    static func score(_ inputs: [PriorityInput]) -> [PriorityRow] {
        let realMax = inputs.compactMap(\.paidPurchases).max() ?? 0
        let maxMoney = Double(max(realMax, 1))
        let portfolioHasMoney = realMax > 0

        return inputs.map { input in
            let reviews = input.reviews.sorted { $0.createdDate > $1.createdDate }
            let money = Double(input.paidPurchases ?? 0)
            let moneySignal = norm(money, 0, maxMoney)

            let trend = trendPct(input.dailyDownloads)
            let dropSignal = norm(max(0, -(trend ?? 0)), 0, 100)
            let surgeSignal = norm(max(0, trend ?? 0), 0, 100)

            let recent = average(reviews.prefix(20))
            let older = average(reviews.dropFirst(20).prefix(20))
            let delta = recent.flatMap { r in older.map { r - $0 } }

            var reviewRisk = 0.0
            var ratingHealth = 0.0
            if let recent {
                let low = norm(5 - recent, 0, 4)
                let drop = (delta ?? 0) < 0 ? norm(-(delta ?? 0), 0, 2) : 0
                reviewRisk = max(low, drop)
                ratingHealth = norm(recent - 3, 0, 2) * ((delta ?? 0) < 0 ? 0.5 : 1)
            }

            let risk = weighted([
                (riskMoney, moneySignal, portfolioHasMoney),
                (riskDrop, dropSignal, trend != nil),
                (riskReviews, reviewRisk, recent != nil)
            ])
            let opportunity = weighted([
                (oppMoney, moneySignal, portfolioHasMoney),
                (oppSurge, surgeSignal, trend != nil),
                (oppRating, ratingHealth, recent != nil)
            ])
            let priority = max(risk, opportunity) + 0.15 * min(risk, opportunity)
            let unanswered = reviews.filter { $0.response == nil }.count

            return PriorityRow(
                id: input.key,
                name: input.name,
                paidPurchases: input.paidPurchases ?? 0,
                proceedsLabel: input.proceedsLabel,
                firstDownloads: input.firstDownloads ?? 0,
                trendPct: trend.map { ($0 * 10).rounded() / 10 },
                recentRating: recent,
                ratingDelta: delta,
                reviewCount: reviews.count,
                unanswered: unanswered,
                risk: (risk * 10).rounded() / 10,
                opportunity: (opportunity * 10).rounded() / 10,
                priority: (priority * 10).rounded() / 10,
                flags: flags(money: money, maxMoney: portfolioHasMoney ? maxMoney : 0, trend: trend,
                             recent: recent, delta: delta, opportunity: opportunity,
                             unansweredLow: reviews.prefix(50).filter { $0.response == nil && $0.rating <= 2 }.count))
        }
        .sorted { $0.priority > $1.priority }
    }

    /// 쓸 수 있는 신호의 가중치만으로 0~100 을 낸다.
    static func weighted(_ pairs: [(weight: Double, value: Double, enabled: Bool)]) -> Double {
        let denominator = pairs.filter(\.enabled).reduce(0) { $0 + $1.weight }
        guard denominator > 0 else { return 0 }
        return pairs.filter(\.enabled).reduce(0) { $0 + $1.weight * $1.value } / denominator
    }

    /// 하루 다운로드를 앞뒤 절반으로 갈라 증감률(%). 4일이 안 되면 nil.
    static func trendPct(_ daily: [Int]) -> Double? {
        guard daily.count >= 4 else { return nil }
        let mid = daily.count / 2
        let first = daily[..<mid].reduce(0, +)
        let second = daily[mid...].reduce(0, +)
        if first == 0 { return second > 0 ? 100 : 0 }
        return Double(second - first) / Double(first) * 100
    }

    static func average<S: Sequence>(_ reviews: S) -> Double? where S.Element == CustomerReview {
        let ratings = reviews.map(\.rating).filter { $0 > 0 }
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    static func norm(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard high != low else { return 0 }
        return min(100, max(0, (value - low) / (high - low) * 100))
    }

    static func flags(money: Double, maxMoney: Double, trend: Double?, recent: Double?,
                      delta: Double?, opportunity: Double, unansweredLow: Int) -> [PriorityFlag] {
        var flags: [PriorityFlag] = []
        if maxMoney > 0, money > 0, money >= 0.25 * maxMoney {
            flags.append(PriorityFlag(kind: .money, text: "결제 핵심"))
        }
        if let trend, trend >= 40 {
            flags.append(PriorityFlag(kind: .surge, text: "다운로드 급등 +\(Int(trend))%"))
        } else if let trend, trend <= -25 {
            flags.append(PriorityFlag(kind: .drop, text: "다운로드 급락 \(Int(trend))%"))
        }
        if let recent, recent < 3.5 {
            flags.append(PriorityFlag(kind: .lowRating, text: String(format: "최근 평점 %.1f", recent)))
        }
        if let delta, delta <= -0.5 {
            flags.append(PriorityFlag(kind: .ratingDrop, text: String(format: "평점 하락 %+.1f", delta)))
        }
        if unansweredLow > 0 {
            flags.append(PriorityFlag(kind: .unanswered, text: "답 안 한 저평점 \(unansweredLow)건"))
        }
        if opportunity >= 55, (trend ?? 0) > 0 {
            flags.append(PriorityFlag(kind: .opportunity, text: "키울 기회"))
        }
        return flags
    }
}

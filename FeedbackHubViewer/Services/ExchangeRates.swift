//
//  ExchangeRates.swift
//  FeedbackHubViewer
//
//  판매 리포트의 수익금은 **나라마다 그 나라 통화**로 온다 — 원, 달러, 엔, 유로 …
//  통화별로 늘어놓으면 "그래서 얼마 벌었나" 가 안 읽혀서, 하루 한 번 받은 환율로
//  원화 · 달러 합계를 낸다.
//
//  읽는 곳은 ExchangeRate-API 의 공개 끝점(`open.er-api.com`)이다. 키가 필요 없고
//  160개 넘는 통화를 하루 단위로 준다. 이용 조건이 출처 표기를 요구해서 화면에
//  "환율: ExchangeRate-API" 를 단다(`attribution`).
//
//  환산은 **어림값**이다. Apple 이 실제로 보내 주는 돈은 지급 시점의 환율로 바뀌고,
//  여기 환율은 오늘 것이다. 화면은 그래서 언제나 "≈" 를 붙인다.
//

import Foundation

struct ExchangeRates: Codable, Equatable {
    /// 환율이 매겨진 날(공급자가 말한 갱신 시각).
    let date: Date
    /// 통화 코드 → 1달러에 그 통화 몇 단위.
    let perUSD: [String: Double]

    static let attribution = "환율: ExchangeRate-API (exchangerate-api.com)"
    static let attributionURL = URL(string: "https://www.exchangerate-api.com")!

    /// 받은 지 이만큼 지나면 다시 받는다. 공급자는 하루 한 번 바꾼다.
    static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// 이 통화 금액을 달러로. 모르는 통화면 nil.
    func usd(_ amount: Double, currency: String) -> Double? {
        guard let rate = perUSD[currency.uppercased()], rate > 0 else { return nil }
        return amount / rate
    }

    func krw(fromUSD usd: Double) -> Double? {
        perUSD["KRW"].map { usd * $0 }
    }

    /// 이 통화 금액을 원으로. 모르는 통화면 nil.
    func krw(_ amount: Double, currency: String) -> Double? {
        if currency.uppercased() == "KRW" { return amount }
        return usd(amount, currency: currency).flatMap { krw(fromUSD: $0) }
    }

    /// 통화별 금액 묶음을 달러 하나로. 환산하지 못한 통화는 따로 돌려준다 — 조용히 빼면
    /// 합계가 거짓이 된다.
    func usd(_ amounts: [String: Double]) -> (total: Double, unconverted: [String]) {
        var total = 0.0
        var unconverted: [String] = []
        for (currency, amount) in amounts where amount != 0 {
            if let value = usd(amount, currency: currency) {
                total += value
            } else {
                unconverted.append(currency)
            }
        }
        return (total, unconverted.sorted())
    }

    private struct Response: Decodable {
        let result: String
        let time_last_update_unix: TimeInterval?
        let rates: [String: Double]
    }

    /// 오늘 환율. 실패하면 오류.
    static func fetch() async throws -> ExchangeRates {
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result == "success", !response.rates.isEmpty else { throw URLError(.badServerResponse) }
        return ExchangeRates(date: response.time_last_update_unix.map(Date.init(timeIntervalSince1970:)) ?? Date(),
                             perUSD: response.rates)
    }
}

/// "₩1,234,567" / "$920.15" — 합계는 원 단위 · 센트 단위까지만.
enum MoneyFormat {
    static func krw(_ amount: Double) -> String {
        format(amount, code: "KRW", digits: 0)
    }

    static func usd(_ amount: Double) -> String {
        format(amount, code: "USD", digits: abs(amount) >= 1000 ? 0 : 2)
    }

    /// "₩1,234,567 ($920.15)" — 앱 내 구입 화면의 금액은 늘 달러를 같이 적는다.
    static func krwWithUSD(krw: Double, usd: Double) -> String {
        "\(self.krw(krw)) (\(self.usd(usd)))"
    }

    /// 지도 위에 얹을 만큼 짧게: "₩1.2만", "₩35만", "₩1,240만".
    static func shortKRW(_ amount: Double) -> String {
        let value = abs(amount)
        let sign = amount < 0 ? "-" : ""
        if value >= 10_000 {
            let man = value / 10_000
            return sign + "₩" + (man >= 100 ? String(format: "%.0f만", man) : String(format: "%.1f만", man))
        }
        return sign + "₩" + String(format: "%.0f", value)
    }

    private static func format(_ amount: Double, code: String, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.currencyCode = code
        formatter.currencySymbol = code == "KRW" ? "₩" : "$"
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = digits
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }
}

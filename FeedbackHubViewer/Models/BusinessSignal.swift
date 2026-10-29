//
//  BusinessSignal.swift
//  FeedbackHubViewer
//
//  앱마다 비즈니스 모델 신호등 — 돈을 받는 길이 있고, 그 길이 열려 있고, 실제로 돈이 들어오나.
//
//  재료는 셋이다.
//   · app-portfolio 의 앱 JSON — 수익 모델(price.pricingModel) · 인앱 상품 · 수익화 장치(숙성도 money)
//   · app-portfolio 의 paywalls.json — 앱 안 결제 화면(페이월)이 있고 켜져 있나(`hidden`)
//   · 허브가 받는 App Store 판매 리포트 — 최근 30일 결제 · 수익. 없으면 app-portfolio 의 매출 관문
//
//  판정은 순수 함수(`make`)라 화면은 결과만 그린다.
//

import SwiftUI

/// paywalls.json 의 앱 하나. 앱 소스에서 사람이 읽어 정리한 페이월.
struct PaywallInfo: Decodable {
    let slug: String?
    /// one-time-unlock · subscription · tip-jar · consumable-pack · mixed · none
    let kind: String?
    let headline: String?
    let subheadline: String?
    let benefits: [String]?
    let free: [String]?
    let locked: [String]?
    let tiers: [Tier]?
    let triggers: [String]?
    let cta: String?
    let trial: String?
    let restore: Bool?
    let notes: String?
    /// 출시 빌드에서 결제 화면을 꺼 두었다.
    let hidden: Bool?
    let paywallFiles: [String]?

    struct Tier: Decodable, Hashable {
        let productId: String?
        let label: String?
        let price: String?
        let period: String?
        /// 스토어에서 팔고 있다. false 면 스토어 준비 중.
        let live: Bool?
    }

    var hasPaywall: Bool {
        kind != nil && kind != "none" && (headline != nil || !(benefits ?? []).isEmpty || !(locked ?? []).isEmpty)
    }

    var kindLabel: String {
        switch kind {
        case "one-time-unlock": "한 번 잠금 해제"
        case "subscription": "구독"
        case "tip-jar": "후원"
        case "consumable-pack": "소모성 팩"
        case "mixed": "여러 방식"
        default: "없음"
        }
    }
}

struct BusinessSignal {
    enum Level: Int, Comparable {
        case red = 0, yellow, green, unknown
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        var color: Color {
            switch self {
            case .red: .red
            case .yellow: .orange
            case .green: .green
            case .unknown: .secondary
            }
        }
        var label: String {
            switch self {
            case .red: "빨강"
            case .yellow: "노랑"
            case .green: "초록"
            case .unknown: "모름"
            }
        }
    }

    let level: Level
    let model: String
    let headline: String
    /// 판정의 근거 — 한 줄씩.
    let reasons: [String]
    /// 다음에 할 일. 초록이면 비어 있을 수 있다.
    let next: String?

    /// 최근 30일 App Store 판매에서 이 앱 몫.
    struct Sales {
        let purchases: Int
        let hasProceeds: Bool
        let firstDownloads: Int
    }

    static func modelName(_ key: String?) -> String {
        switch key {
        case "paid": "유료 앱"
        case "freemium": "부분 유료"
        case "freemium-subscription": "무료 + 구독"
        case "paid+subscription": "유료 + 구독"
        case "paid+iap": "유료 + 인앱"
        case "free": "무료"
        default: "모름"
        }
    }

    static func make(app: PortfolioApp?, paywall: PaywallInfo?, sales: Sales?) -> BusinessSignal {
        guard let app, let price = app.price else {
            return .init(level: .unknown, model: "모름", headline: "app-portfolio 에 가격 정보가 없어요",
                         reasons: [], next: "app-portfolio 의 sync-pricing.py 로 가격을 모으면 판정해요")
        }
        let model = price.pricingModel ?? (price.isFree == false ? "paid" : "free")
        let name = modelName(model)
        let money = app.serviceMaturity?.money ?? [:]
        let tipJar = (money["tipJar"] ?? nil) == true || paywall?.kind == "tip-jar"
        let hasIAP = price.hasInAppPurchases == true || !(price.iapItems ?? []).isEmpty
        let isPaidApp = model.hasPrefix("paid")
        let canEarn = isPaidApp || hasIAP || tipJar
        let paywallLive = (paywall?.hasPaywall ?? false) && paywall?.hidden != true
        let restore = money["restore"] ?? nil

        var reasons = ["수익 모델: \(name)" + (hasIAP ? " · 인앱 상품 \(price.iapItems?.count ?? 0)개" : "")
                       + (tipJar ? " · 후원" : "")]
        if let paywall {
            reasons.append(paywall.hidden == true ? "결제 화면: 출시 빌드에서 꺼 둠"
                           : paywall.hasPaywall ? "결제 화면: \(paywall.kindLabel)" : "결제 화면: 없음")
        }

        // 실제로 들어오나 — 판매 리포트가 먼저, 없으면 매출 관문.
        let earning: Bool?
        /// 판매 리포트가 아니라 매출 관문으로 판정했나 — 문구가 달라진다(관문은 "결제 있음" 이 아니다).
        var byGate = false
        if let sales {
            earning = sales.purchases > 0 || sales.hasProceeds
            reasons.append("최근 30일: 결제 \(sales.purchases)건" + (sales.hasProceeds ? " · 수익 있음" : " · 수익 없음")
                           + " · 첫 다운로드 \(sales.firstDownloads)회")
        } else if let gate = app.revenueGates?.revenue {
            earning = gate
            byGate = true
            reasons.append("매출 관문(app-portfolio): " + (gate ? "통과" : "아직"))
        } else {
            earning = nil
            reasons.append("매출: 판매 리포트가 없어 모름")
        }

        if !canEarn {
            // 아직 다듬는 단계(제품 여정 2단계까지)면 무료가 계획일 수 있다 — 빨강은 넓혀 가는 앱만.
            let stage = app.lifecycle?.stage
            if let stage { reasons.append("제품 여정: \(stage)단계") }
            if (stage ?? 0) <= 2 {
                return .init(level: .yellow, model: name, headline: "아직 돈을 받지 않는 단계예요", reasons: reasons,
                             next: "3단계로 넘어가기 전에 언제 무엇에 돈을 받을지 정해 두기")
            }
            return .init(level: .red, model: name, headline: "넓혀 가는 앱인데 돈을 받는 길이 없어요", reasons: reasons,
                         next: "후원이나 한 번 잠금 해제부터 — 쓰는 사람이 늘수록 늦어진다")
        }
        if hasIAP && !isPaidApp && !paywallLive && !tipJar {
            return .init(level: .red, model: name, headline: "상품은 있는데 앱 안에서 팔지 않아요", reasons: reasons,
                         next: paywall?.hidden == true ? "출시 빌드에서 결제 화면을 켜기" : "결제 화면(페이월)을 붙이기")
        }
        if hasIAP && restore == false {
            return .init(level: .yellow, model: name, headline: "구매 복원이 없어요", reasons: reasons,
                         next: "설정에 구매 복원 버튼 — 인앱 구입이 있으면 Apple 이 요구해요")
        }
        switch earning {
        case true?:
            return .init(level: .green, model: name, headline: "돈이 들어오고 있어요", reasons: reasons, next: nil)
        case false?:
            return .init(level: .yellow, model: name,
                         headline: byGate ? "받을 길은 있는데 매출 관문을 아직 못 넘었어요" : "받을 길은 있는데 최근 30일 결제가 없어요",
                         reasons: reasons,
                         next: paywallLive ? "결제 화면이 뜨는 때(무료 문턱)를 앞당기거나 할인 제안" : "결제 화면을 보이게")
        case nil:
            return .init(level: .yellow, model: name, headline: "받을 길은 있는데 매출을 몰라요", reasons: reasons,
                         next: "App Store Connect 키 · 판매 리포트(공급자 번호)를 넣으면 판정해요")
        }
    }
}

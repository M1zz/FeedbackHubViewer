//
//  AppPotential.swift
//  FeedbackHubViewer
//
//  앱 하나의 잠재력 판정 — "얼마나 팔리나" 가 아니라 "어디서 새고, 고치면 얼마나 오르나".
//
//  많이 팔리는 앱은 대개 시간을 많이 들인 앱이라, 매출 순위는 노력의 순위에 가깝다. 어느 앱에
//  시간을 더 들일지는 다른 물음이다. 여기서는 스토어의 깔때기를 단계마다 업계 평균과 견준다.
//
//    노출 → 페이지 조회   평균 6~12%      낮으면 아이콘 · 제목 · 부제
//    페이지 조회 → 받기   평균 25% 안팎   낮으면 스크린샷 · 설명
//    받기 → 유료          무료+유료 2.1% · 처음부터 유료 10.7%   낮으면 페이월
//
//  세 줄의 뜻이 서로 다르다는 것이 요점이다.
//   · 노출은 많은데 전환이 낮다 → **세팅 문제.** 고치면 오른다. 가장 확실한 후보.
//   · 전환은 평균 이상인데 노출이 적다 → 세팅은 됐고 수요 · 키워드가 작다.
//   · 받는데 안 산다 → 페이월이 없거나 너무 관대하다.
//  그리고 손을 안 댄 지 오래인데도 받는 앱은 방치 상태의 숫자가 곧 수요라 따로 표시한다.
//
//  기준값은 Adapty · RevenueCat 이 공개한 업계 평균이다. 카테고리마다 크게 다르므로(비즈니스
//  앱의 페이지 전환은 60%대, 보드게임은 1%대) "평균보다 낮다" 는 **볼 곳**을 가리킬 뿐 판결이
//  아니다. 화면도 그렇게 적는다.
//
//  판정은 화면과 떨어진 순수 함수다(`make`) — 같은 숫자면 같은 말이 나온다.
//

import Foundation

struct AppPotential: Identifiable {

    // MARK: - 기준

    enum Benchmark {
        /// 노출 → 페이지 조회. 평균 6~12% 의 아래쪽.
        static let tapThrough = 0.06
        /// 페이지 조회 → 받기.
        static let pageConversion = 0.25
        /// 받기 → 유료, 무료로 쓰다 사는 앱의 중앙값.
        static let freemiumPaid = 0.021
        /// 받기 → 유료, 처음부터 막는 앱의 중앙값.
        static let hardPaywallPaid = 0.107
        /// 스토어 수수료를 뗀 몫(소규모 사업자 15%).
        static let payout = 0.85

        /// 이보다 적은 표본으로는 비율을 말하지 않는다 — 노출 40에 받기 1은 2.5% 가 아니라 "모름" 이다.
        static let minImpressions = 500
        static let minPageViews = 100
        static let minDownloads = 100
        /// 손을 안 댄 지 이만큼 지났으면 방치로 본다(일).
        static let neglectDays = 90
    }

    // MARK: - 재료

    /// 최근 30일의 숫자. 모르는 것은 nil — 0 과 다르다.
    struct Input {
        var project: String
        var name: String
        /// 스토어 분석 리포트를 받았나.
        var hasFunnel = false
        var impressions = 0
        var pageViews = 0
        /// 제품 페이지에서 받은 첫 다운로드. 페이지 조회와 견줄 수 있는 것은 이것뿐이다.
        var pageDownloads = 0
        var downloads = 0
        /// 검색으로 온 첫 다운로드의 몫.
        var searchShare: Double?
        /// 돈을 낸 결제 건수. 상품 목록을 모르면 nil.
        var paid: Int?
        /// 개발자 수익(원). 환율 · 판매 기록이 없으면 nil.
        var proceedsKRW: Double?
        /// 마지막 업데이트 뒤 지난 날.
        var daysSinceUpdate: Int?
        /// 허브가 본 7일 활성.
        var active7 = 0
    }

    // MARK: - 판정

    /// 어디가 문제인가. 무거운(고치면 크게 오르는) 차례.
    enum Leak: String, CaseIterable, Identifiable {
        /// 노출은 있는데 눌러 보지 않는다.
        case listing
        /// 페이지는 보는데 받지 않는다.
        case page
        /// 받는데 사지 않는다.
        case paywall
        var id: String { rawValue }

        var title: String {
            switch self {
            case .listing: return "눌러 보지 않음"
            case .page: return "보고도 안 받음"
            case .paywall: return "받고도 안 삼"
            }
        }

        var fix: String {
            switch self {
            case .listing: return "아이콘 · 제목 · 부제 — 검색 목록에서 보이는 것부터"
            case .page: return "스크린샷 첫 세 장 · 설명 첫 줄 · 리뷰 수"
            case .paywall: return "페이월 — 쓰는 흐름 안에서 보이게, 유료 전용 기능을 분명히"
            }
        }

        var systemImage: String {
            switch self {
            case .listing: return "hand.tap"
            case .page: return "rectangle.on.rectangle"
            case .paywall: return "creditcard"
            }
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        /// 노출 · 다운로드가 있는데 깔때기가 샌다 — 고치면 오른다.
        case fixable = "고치면 오름"
        /// 손을 안 댄 지 오래인데 받는다.
        case sleeper = "방치해도 받음"
        /// 깔때기가 기준 이상이고 돈이 들어온다.
        case working = "잘 되는 중"
        /// 전환은 괜찮은데 노출이 적다.
        case smallDemand = "수요가 작음"
        /// 받는 사람도 쓰는 사람도 거의 없다.
        case retire = "정리 후보"
        /// 스토어 숫자가 없다.
        case unknown = "숫자 없음"
        var id: String { rawValue }
    }

    /// 시간을 어떻게 나눌까.
    enum Tier: String {
        case a = "A 집중", b = "B 후보", c = "C 유지", d = "D 정리"
    }

    /// 깔때기 한 단계 — 이 앱의 비율과 기준.
    struct Step: Identifiable {
        let name: String
        /// 표본이 모자라면 nil.
        let rate: Double?
        let benchmark: Double
        /// 몇 중 몇.
        let from: Int
        let to: Int
        var id: String { name }
        var isBelow: Bool { rate.map { $0 < benchmark } ?? false }
    }

    let input: Input
    let kind: Kind
    var tier: Tier
    /// 새는 단계들, 무거운 것부터.
    let leaks: [Leak]
    let steps: [Step]
    /// 한 줄 결론.
    let headline: String
    /// 지금 할 일. 없으면 nil.
    let action: String?
    /// 방치 상태인데 받는가.
    let isSleeper: Bool
    /// 깔때기를 기준만큼만 올리면 한 달에 더 붙을 유료 사용자(어림).
    let upsidePayers: Double

    var id: String { input.project }

    /// 손 안 댄 날 하루당 다운로드가 아니라, **방치한 채로 한 달에 받는 수** — 노력을 빼고 본 반응.
    var passiveDownloads: Int? {
        guard let days = input.daysSinceUpdate, days >= Benchmark.neglectDays else { return nil }
        return input.downloads
    }

    // MARK: - 만들기

    static func make(_ input: Input) -> AppPotential {
        let tap = input.impressions >= Benchmark.minImpressions
            ? Double(input.pageViews) / Double(input.impressions) : nil
        let page = input.pageViews >= Benchmark.minPageViews
            ? Double(input.pageDownloads) / Double(input.pageViews) : nil
        let paidRate: Double? = input.paid.flatMap { paid in
            input.downloads >= Benchmark.minDownloads ? Double(paid) / Double(input.downloads) : nil
        }
        let steps = [
            Step(name: "노출 → 조회", rate: tap, benchmark: Benchmark.tapThrough,
                 from: input.impressions, to: input.pageViews),
            Step(name: "조회 → 받기", rate: page, benchmark: Benchmark.pageConversion,
                 from: input.pageViews, to: input.pageDownloads),
            Step(name: "받기 → 유료", rate: paidRate, benchmark: Benchmark.freemiumPaid,
                 from: input.downloads, to: input.paid ?? 0),
        ]

        var leaks: [Leak] = []
        if let tap, tap < Benchmark.tapThrough { leaks.append(.listing) }
        if let page, page < Benchmark.pageConversion { leaks.append(.page) }
        if let paidRate, paidRate < Benchmark.freemiumPaid { leaks.append(.paywall) }

        // 기준만큼만 올렸을 때의 다운로드와 유료 — 지금보다 나은 쪽만 센다.
        let benchDownloads = Double(input.impressions) * Benchmark.tapThrough * Benchmark.pageConversion
        let reachable = max(Double(input.downloads), input.impressions >= Benchmark.minImpressions ? benchDownloads : 0)
        let upside = max(0, reachable * Benchmark.freemiumPaid - Double(input.paid ?? 0))

        let isSleeper = (input.daysSinceUpdate ?? 0) >= Benchmark.neglectDays && input.downloads >= 50
        let earns = (input.proceedsKRW ?? 0) > 0

        let kind: Kind
        if !input.hasFunnel && input.paid == nil && input.downloads == 0 {
            kind = .unknown
        } else if input.downloads < 10 && !earns && input.active7 < 5 {
            kind = .retire
        } else if !leaks.isEmpty {
            kind = .fixable
        } else if isSleeper {
            kind = .sleeper
        } else if input.hasFunnel && input.impressions < Benchmark.minImpressions {
            kind = .smallDemand
        } else if earns {
            kind = .working
        } else {
            kind = .smallDemand
        }

        let headline: String
        let action: String?
        switch kind {
        case .unknown:
            headline = "스토어 숫자가 아직 없습니다."
            action = "App Store Connect 분석 리포트 요청이 있는지 확인"
        case .retire:
            headline = "30일 동안 받은 사람이 \(input.downloads)명, 쓰는 사람이 \(input.active7)명입니다."
            action = "내리거나 다른 앱에 합칠지 정하기 — 새 OS 마다 드는 유지 비용이 남습니다"
        case .fixable:
            let leak = leaks[0]
            headline = Self.sentence(for: leak, input: input, tap: tap, page: page, paidRate: paidRate)
            action = leak.fix
        case .sleeper:
            headline = "업데이트한 지 \(input.daysSinceUpdate ?? 0)일이 지났는데 한 달에 \(Self.count(input.downloads))명이 받습니다. 손을 안 댄 채 나오는 숫자라 수요에 가장 가깝습니다."
            action = "같은 조건의 작은 실험 하나 — 키워드 · 스크린샷 개편으로 반응 보기"
        case .working:
            headline = "깔때기가 기준 이상이고 수익이 납니다."
            action = "지키기 — 크래시 · 낮은 별 리뷰부터, 새 기능은 그다음"
        case .smallDemand:
            headline = input.hasFunnel
                ? "전환은 괜찮은데 한 달 노출이 \(Self.count(input.impressions))회뿐입니다. 세팅은 됐고 찾는 사람이 적습니다."
                : "받는 사람은 있는데 스토어 깔때기를 잴 숫자가 없습니다."
            action = input.hasFunnel ? "키워드를 넓히거나 다른 나라 말로 — 페이지를 고쳐도 크게 오르지 않습니다" : nil
        }

        let tier: Tier
        switch kind {
        case .retire: tier = .d
        case .fixable, .sleeper: tier = .b
        case .working: tier = .b
        case .smallDemand, .unknown: tier = .c
        }

        return AppPotential(input: input, kind: kind, tier: tier, leaks: leaks, steps: steps,
                            headline: headline, action: action, isSleeper: isSleeper, upsidePayers: upside)
    }

    /// 여러 앱을 한꺼번에 — 수익이 가장 큰 앱 하나가 A, 고치면 가장 많이 오를 앱부터 차례.
    static func rank(_ inputs: [Input]) -> [AppPotential] {
        var all = inputs.map(make)
        if let top = all.indices.max(by: { (all[$0].input.proceedsKRW ?? 0) < (all[$1].input.proceedsKRW ?? 0) }),
           (all[top].input.proceedsKRW ?? 0) > 0 {
            all[top].tier = .a
        }
        return all.sorted {
            if $0.upsidePayers != $1.upsidePayers { return $0.upsidePayers > $1.upsidePayers }
            return $0.input.downloads > $1.input.downloads
        }
    }

    private static func sentence(for leak: Leak, input: Input, tap: Double?, page: Double?, paidRate: Double?) -> String {
        switch leak {
        case .listing:
            return "한 달에 \(count(input.impressions))번 보였는데 \(percent(tap))만 눌러 봅니다(평균 6~12%). 노출은 이미 있으니 고치면 바로 오릅니다."
        case .page:
            return "페이지를 본 \(count(input.pageViews))명 중 \(percent(page))만 받습니다(평균 25% 안팎). 들어온 사람을 페이지가 놓칩니다."
        case .paywall:
            if input.paid == 0 {
                return "한 달에 \(count(input.downloads))명이 받는데 산 사람이 없습니다. 페이월이 없거나 너무 관대합니다."
            }
            return "받은 \(count(input.downloads))명 중 \(percent(paidRate))만 삽니다(무료+유료 앱 평균 2.1%)."
        }
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return value < 0.1 ? String(format: "%.1f%%", value * 100) : String(format: "%.0f%%", value * 100)
    }

    private static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - 역산

/// 목표 매출에서 거꾸로 — 유료 몇 명, 다운로드 몇 건이 필요한가.
///
/// "매출이 날 정도" 가 어느 만큼인지 가늠하는 자리다. 한 달에 새로 붙는 유료만 센다 — 구독이면
/// 달마다 쌓이므로 실제로는 이보다 빨리 닿는다.
struct RevenueGoal {
    /// 한 달 목표(원).
    var target: Double
    /// 한 사람이 내는 값(원).
    var price: Double

    /// 필요한 유료 사용자.
    var payersNeeded: Double {
        let each = price * AppPotential.Benchmark.payout
        return each > 0 ? target / each : 0
    }

    /// 그 전환율이면 필요한 다운로드.
    func downloadsNeeded(at rate: Double) -> Double {
        rate > 0 ? payersNeeded / rate : 0
    }

    /// 이 앱의 지금 다운로드로 어디까지 닿나.
    func reading(downloads: Int) -> String {
        guard downloads > 0, payersNeeded > 0 else { return "받는 사람이 없어 가늠할 수 없습니다." }
        let soft = Double(downloads) * AppPotential.Benchmark.freemiumPaid
        let hard = Double(downloads) * AppPotential.Benchmark.hardPaywallPaid
        if soft >= payersNeeded {
            return "유입은 충분합니다 — 평균 전환(2.1%)만 나와도 목표에 닿습니다. 남은 것은 페이월입니다."
        }
        if hard >= payersNeeded {
            return "유료 전용으로 막으면(10.7%) 닿고, 무료로 열어 두면(2.1%) 목표의 \(AppPotential.percent(soft / payersNeeded))입니다."
        }
        let times = downloadsNeeded(at: AppPotential.Benchmark.hardPaywallPaid) / Double(downloads)
        return "유입이 모자랍니다 — 가장 잘 막아도(10.7%) 다운로드가 지금의 \(String(format: times >= 10 ? "%.0f" : "%.1f", times))배 필요합니다. 페이지가 아니라 시장 크기 문제입니다."
    }
}

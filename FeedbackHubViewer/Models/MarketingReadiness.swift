//
//  MarketingReadiness.swift
//  FeedbackHubViewer
//
//  앱마다 홍보할 채비가 됐나 — 서비스 숙성도의 "홍보" 칸을 허브에서 읽는다.
//
//  숙성도는 app-portfolio 의 `sync-service-maturity.py` 가 앱 리포를 훑어 앱 JSON
//  (`serviceMaturity.marketing`)에 적는다. 두 무리다.
//
//   · 리포에 함께 있는 홍보 파이프라인 — 스토어 문구 원고, 스크린샷 자동 촬영, 문구 입힌 스크린샷,
//     언어별 스크린샷, 사용 영상 도구, 사용 영상, 홍보 글 원고
//   · 앱 안의 장치 — 촬영용 데모 모드, 앱 공유, 공유 이미지 · 영상, 딥링크, 프로모션 코드, 초대, 설치 유도
//
//  허브는 그 값을 그대로 늘어놓지 않고(원본은 접는다), "무엇이 빠졌고 먼저 무엇을 할지" 로 바꿔
//  보여 준다. 값은 true(있음) / false(없음) / nil(확인 불가 — 소스를 못 찾음)이고, 모른다를
//  없다로 세지 않는다.
//

import Foundation

/// app-portfolio 의 앱 JSON 한 개 중 허브가 쓰는 것만.
struct PortfolioApp: Decodable {
    let name: String?
    let bundleId: String?
    let appStoreId: String?
    let serviceMaturity: Maturity?
    /// 사람이 확인한 홍보 기록 — 채널 → 기록(레딧에 올렸다 등).
    let marketing: [String: Post]?
    /// App Store 실데이터로 모은 가격 — 수익 모델 · 인앱 상품.
    let price: Price?
    /// 매출 자료가 있던 컴퓨터가 남긴 관문 통과 여부(금액 없이). 대부분 비어 있다.
    let revenueGates: RevenueGates?
    /// 제품 여정 단계(1~5). 무료로 두는 게 맞는 단계인지 가를 때 쓴다.
    let lifecycle: Lifecycle?
    /// App Store 마케팅 URL(소개 페이지)을 열어 본 판정 — app-portfolio 의 sync-intro-pages.py.
    let introPage: IntroPage?
    /// 앱이 줘야 하는 경험 — 핵심 가치 · 경험 목표 · 디자인 원칙(사람이 쓴 것, 앱 20개쯤만 있다).
    let vision: Vision?

    struct Vision: Decodable {
        let tagline: String?
        let coreValue: String?
        let targetUsers: String?
        let uniqueSellingPoint: String?
        let userExperienceGoals: [String]?
        let designPrinciples: [String]?
    }

    struct IntroPage: Decodable {
        let url: String?
        let urlEn: String?
        /// 스토어에 마케팅 URL 을 걸어 두었나.
        let set: Bool?
        let reachable: Bool?
        let intro: Bool?
        let screens: Bool?
        let video: Bool?
        let tryIt: Bool?
        let scenario: Bool?
        let steps: Bool?
        let proof: Bool?
        let storeLink: Bool?
        let ogImage: Bool?
        let english: Bool?
        let evaluatedAt: String?

        /// (이름, 값) — 페이지가 갖췄나 하나씩. 빠진 것을 할 일로 바꾸는 순서이기도 하다.
        var checks: [(name: String, value: Bool?)] {
            [("한 줄 소개", intro), ("스크린샷", screens), ("사용 영상", video), ("App Store 링크", storeLink),
             ("써 보는 장면", scenario), ("쓰는 법 단계", steps), ("써 본 사람의 말", proof),
             ("바로 해 보기", tryIt), ("공유 미리보기 그림", ogImage), ("영어", english)]
        }

        var headline: String {
            if set == false { return "스토어에 소개 페이지(마케팅 URL)가 없어요" }
            if reachable == false { return "소개 페이지가 열리지 않아요" }
            let measured = checks.filter { $0.value != nil }
            let present = measured.filter { $0.value == true }.count
            return measured.isEmpty ? "소개 페이지: 판정 전" : "소개 페이지 \(present)/\(measured.count) 갖춤"
        }
    }

    struct Lifecycle: Decodable {
        let stage: Int?
        let label: String?
    }

    struct Maturity: Decodable {
        let marketing: [String: Bool?]?
        let money: [String: Bool?]?
        let evaluatedAt: String?
    }

    struct Price: Decodable {
        let isFree: Bool?
        /// free · paid · freemium · freemium-subscription · paid+subscription · paid+iap
        let pricingModel: String?
        let hasInAppPurchases: Bool?
        let iapItems: [Item]?
        let priceKRW: Int?

        struct Item: Decodable {
            let name: String
            let price: String
        }
    }

    struct RevenueGates: Decodable {
        let revenue: Bool?
        let profit: Bool?
        let uptrend: Bool?
    }

    struct Post: Decodable {
        let posted: Bool?
        let recordedAt: String?
        let url: String?
        let subreddit: String?
        let note: String?
    }

    /// 판정에 쓸 값. 항목이 하나도 재지 않았으면 nil.
    var readiness: MarketingReadiness? {
        guard let values = serviceMaturity?.marketing, !values.isEmpty else { return nil }
        return MarketingReadiness(values: values, evaluatedAt: serviceMaturity?.evaluatedAt)
    }
}

struct MarketingReadiness {
    /// 키 → 있음 · 없음 · 모름.
    let values: [String: Bool?]
    let evaluatedAt: String?

    enum Group: String, CaseIterable {
        case pipeline = "리포의 홍보 파이프라인"
        case inApp = "앱 안의 홍보 장치"
    }

    struct Item {
        let key: String
        let name: String
        let group: Group
        /// 없을 때 할 일 — 판정 칸이 이 말을 그대로 쓴다.
        let todo: String
        /// 먼저 할수록 작은 수. 같은 노력에 효과가 큰 것부터.
        let priority: Int
    }

    /// 아는 항목. 스크립트가 새 항목을 더하면 이름 없이 키로라도 보인다(`items`).
    static let catalog: [Item] = [
        .init(key: "storeCopy", name: "스토어 문구 원고", group: .pipeline,
              todo: "스토어 설명 · 부제 · 키워드를 리포의 APPSTORE.md 로 관리하기", priority: 1),
        .init(key: "promoKit", name: "홍보 글 원고", group: .pipeline,
              todo: "리포에 marketing/ 폴더를 두고 채널별 글을 모아 두기", priority: 2),
        .init(key: "demoMode", name: "촬영용 데모 모드", group: .inApp,
              todo: "실행 인자 하나로 보기 좋은 예시 데이터를 채우는 데모 모드 넣기 — 스크린샷 · 영상의 바탕", priority: 3),
        .init(key: "screenshotCapture", name: "스크린샷 자동 촬영", group: .pipeline,
              todo: "시뮬레이터로 화면을 차례로 찍는 스크립트(capture 스크립트 · Snapfile) 두기", priority: 4),
        .init(key: "shareApp", name: "앱 공유", group: .inApp,
              todo: "설정에 \"친구에게 알리기\" — 스토어 링크를 공유 시트로", priority: 5),
        .init(key: "videoTool", name: "사용 영상 도구", group: .pipeline,
              todo: "시뮬레이터 화면 녹화(recordVideo)로 사용 영상을 뽑는 스크립트 두기", priority: 6),
        .init(key: "videoAsset", name: "사용 영상", group: .pipeline,
              todo: "30초 사용 영상을 만들어 리포(docs · marketing)에 두기 — 스토어 미리보기 · 쇼츠에 같이 씀", priority: 7),
        .init(key: "marketingScreens", name: "문구 입힌 스크린샷", group: .pipeline,
              todo: "스크린샷 위에 한 줄 문구를 입힌 스토어용 그림 만들기", priority: 8),
        .init(key: "shareImage", name: "공유 이미지", group: .inApp,
              todo: "앱이 만든 결과를 그림으로 공유하게 — 쓰는 사람이 대신 알려 준다", priority: 9),
        .init(key: "deepLink", name: "딥링크", group: .inApp,
              todo: "링크로 특정 화면을 열게(onOpenURL) — 글 · 캠페인에서 바로 그 기능으로", priority: 10),
        .init(key: "localizedScreens", name: "언어별 스크린샷", group: .pipeline,
              todo: "지원 언어마다 그 언어 화면으로 스크린샷 찍기(3개 언어 이상)", priority: 11),
        .init(key: "offerCode", name: "프로모션 코드", group: .inApp,
              todo: "앱 안에서 오퍼 코드를 받게(offerCodeRedemption) — 딜 커뮤니티 · 이벤트에 뿌릴 수 있게", priority: 12),
        .init(key: "shareVideo", name: "공유 영상", group: .inApp,
              todo: "결과를 짧은 영상으로 내보내 공유하게", priority: 13),
        .init(key: "invite", name: "초대", group: .inApp,
              todo: "초대 링크 · 코드로 친구를 데려오게", priority: 14),
        .init(key: "installNudge", name: "설치 유도", group: .inApp,
              todo: "앱 클립 · 다른 앱에서 설치 배너(SKOverlay) 띄우기", priority: 15),
    ]

    /// 영상 만들기를 돕는 것 — 사용자가 따로 묻는 물음("사용 영상을 만드는 데 도움 주는 모듈이 있나").
    static let videoKeys = ["demoMode", "videoTool", "videoAsset", "screenshotCapture"]

    /// 재 본 항목 전부(아는 것은 정한 차례로, 모르는 키는 뒤에).
    var items: [(item: Item, value: Bool?)] {
        let known = Self.catalog.compactMap { item in values[item.key].map { (item, $0) } }
        let unknown = values.keys.filter { key in !Self.catalog.contains { $0.key == key } }.sorted()
            .map { key in (Item(key: key, name: key, group: .inApp, todo: key, priority: 99), values[key] ?? nil) }
        return known + unknown
    }

    var measured: Int { values.values.filter { $0 != nil }.count }
    var present: Int { values.values.filter { $0 == true }.count }
    /// 소스를 못 찾아 하나도 못 쟀다.
    var isUnknown: Bool { measured == 0 }

    /// 없는 것, 먼저 할 것부터.
    var missing: [Item] {
        items.filter { $0.value == false }.map(\.item).sorted { $0.priority < $1.priority }
    }

    func has(_ key: String) -> Bool? { values[key] ?? nil }

    /// 판정 한 줄.
    var headline: String {
        if isUnknown { return "소스를 못 찾아 확인 불가" }
        let ratio = Double(present) / Double(max(measured, 1))
        switch ratio {
        case 0.75...: return "홍보 채비가 잘 됐어요"
        case 0.4..<0.75: return "기본은 있어요 — 빠진 것 \(measured - present)개"
        default: return "홍보할 채비가 거의 없어요"
        }
    }

    /// 영상 만들기 도구 한 줄 — "데모 모드 ○ · 영상 도구 ○ · 사용 영상 × · 스크린샷 촬영 ○".
    var videoLine: String {
        Self.videoKeys.compactMap { key -> String? in
            guard let item = Self.catalog.first(where: { $0.key == key }) else { return nil }
            let mark = switch has(key) { case true?: "있음"; case false?: "없음"; case nil: "모름" }
            return "\(item.name) \(mark)"
        }.joined(separator: " · ")
    }
}

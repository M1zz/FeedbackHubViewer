//
//  AppStoreConnect+OfferCodes.swift
//  FeedbackHubViewer
//
//  선물 코드 묶음을 **App Store Connect API 로** 채운다. 코드 파일을 손으로 받아 넣지 않아도 된다.
//
//   1. 앱의 Pro 비소모성 상품을 찾는다.
//   2. 그 상품에 "LeeoKit Gift" 오퍼 코드(무료, 누구나)가 있으면 쓰고, 없으면 만든다 — 앱이
//      팔리는 나라마다 무료 가격점을 붙여서.
//   3. 일회용 코드 n장을 만들고 값(CSV)을 받는다.
//
//  키의 역할이 App Manager 이상이어야 한다(오퍼 코드를 만든다). 403 이면 그것이다.
//

import Foundation

extension AppStoreConnect {

    /// 허브가 만든 오퍼 코드의 이름 — 다음에 이 이름으로 다시 찾는다. 바꾸지 않는다.
    static let giftOfferName = "LeeoKit Gift"
    /// 일회용 코드의 유효 기간. Apple 한도(6개월) 안쪽.
    static let giftCodeLifetimeDays = 170

    struct GiftCodeBatch {
        let productID: String
        let codes: [String]
        let expires: Date
    }

    enum OfferCodeFailure: LocalizedError {
        case noProProduct
        case noFreePrice
        case noTerritories
        case valuesNotReady

        var errorDescription: String? {
            switch self {
            case .noProProduct:
                return "비소모성 Pro 상품이 없어 건너뜁니다(구독만 있는 앱)."
            case .noFreePrice:
                return "무료 가격점을 찾지 못했습니다. App Store Connect 에서 Pro 상품에 \"\(AppStoreConnect.giftOfferName)\" 이라는 무료 오퍼 코드를 한 번 직접 만들면, 그다음부터는 여기서 채웁니다."
            case .noTerritories:
                return "Pro 상품이 팔리는 나라를 읽지 못했습니다(판매 국가 설정을 확인하세요)."
            case .valuesNotReady:
                return "App Store 가 코드를 아직 만드는 중입니다. 잠시 뒤 새로고침하세요."
            }
        }
    }

    /// Apple 이 받는 일회용 코드 수. 이 밖의 수는 409 로 거절된다.
    static let oneTimeCodeSizes = [500, 1000, 1500, 2000, 2500, 5000, 7500, 10000, 15000, 20000, 25000]

    /// `count` 장 이상을 담는 가장 작은 묶음 크기.
    static func batchSize(for count: Int) -> Int {
        oneTimeCodeSizes.first { $0 >= count } ?? oneTimeCodeSizes.last!
    }

    /// Pro 상품에 일회용 오퍼 코드를 적어도 `count` 장 만들어 값까지 받는다(Apple 묶음 크기로 올림 —
    /// 500장 아래는 못 만든다).
    /// `sandbox` 면 샌드박스 코드(개발 빌드 · TestFlight 에서 쓰는 것).
    func makeGiftCodes(appID: String, count: Int, sandbox: Bool) async throws -> GiftCodeBatch {
        let pro = try await proProduct(appID: appID)
        let offerID = try await giftOffer(productID: pro.id)

        let expires = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: Self.giftCodeLifetimeDays, to: Date()) ?? Date()
        let created = try await write("POST", "v1/inAppPurchaseOfferCodeOneTimeUseCodes", body: [
            "data": [
                "type": "inAppPurchaseOfferCodeOneTimeUseCodes",
                "attributes": [
                    "numberOfCodes": Self.batchSize(for: count),
                    "expirationDate": Self.day.string(from: expires),
                    "environment": sandbox ? "SANDBOX" : "PRODUCTION"
                ],
                "relationships": [
                    "offerCode": ["data": ["type": "inAppPurchaseOfferCodes", "id": offerID]]
                ]
            ]
        ])
        guard let batch = try? JSONDecoder().decode(ASCSingleDocument.self, from: created).data else {
            throw Failure.decoding
        }

        // 값은 만들어지는 데 잠깐 걸린다.
        for attempt in 0..<8 {
            if attempt > 0 { try await Task.sleep(nanoseconds: 2_000_000_000) }
            let (data, status) = try await send(url("v1/inAppPurchaseOfferCodeOneTimeUseCodes/\(batch.id)/values"),
                                                accept: "text/csv")
            if status == 404 { continue }
            try check(data, status)
            let codes = GiftCodePool.parseCodes(String(decoding: data, as: UTF8.self))
            if !codes.isEmpty { return GiftCodeBatch(productID: pro.productID, codes: codes, expires: expires) }
        }
        throw OfferCodeFailure.valuesNotReady
    }

    // MARK: - 안쪽

    /// Pro 비소모성 — 하나면 그것, 여럿이면 판매 중이고 이름에 pro · lifetime 이 든 것.
    private func proProduct(appID: String) async throws -> (id: String, productID: String) {
        let doc = try await list("v1/apps/\(appID)/inAppPurchasesV2", [
            "fields[inAppPurchases]": "productId,inAppPurchaseType,state",
            "limit": "200"
        ])
        let candidates = doc.data.filter {
            $0.string("inAppPurchaseType") == StoreProduct.Kind.nonConsumable.rawValue
                && !($0.string("productId") ?? "").lowercased().contains("gift")
                && !($0.string("productId") ?? "").lowercased().contains("tip")
        }
        func score(_ item: ASCResource) -> Int {
            let id = (item.string("productId") ?? "").lowercased()
            var value = 0
            if item.string("state") == "APPROVED" { value += 4 }
            if id.contains("pro") || id.contains("lifetime") || id.contains("premium") || id.contains("unlock") { value += 2 }
            return value
        }
        guard let best = candidates.max(by: { score($0) < score($1) }) else { throw OfferCodeFailure.noProProduct }
        return (best.id, best.string("productId") ?? best.id)
    }

    /// "LeeoKit Gift" 오퍼 코드 id — 있으면 그것, 없으면 무료로 만든다.
    private func giftOffer(productID id: String) async throws -> String {
        let existing = try await list("v2/inAppPurchases/\(id)/offerCodes", [
            "fields[inAppPurchaseOfferCodes]": "name,active",
            "limit": "200"
        ])
        if let found = existing.data.first(where: { $0.string("name") == Self.giftOfferName && $0.bool("active") != false }) {
            return found.id
        }

        let territories = try await availableTerritories(productID: id)
        guard !territories.isEmpty else { throw OfferCodeFailure.noTerritories }
        let points = try await freePricePoints(productID: id, territories: territories)
        guard !points.isEmpty else { throw OfferCodeFailure.noFreePrice }

        let included: [[String: Any]] = points.sorted { $0.key < $1.key }.map { territory, point in
            [
                "type": "inAppPurchaseOfferPrices",
                "id": "${price-\(territory)}",
                "relationships": [
                    "territory": ["data": ["type": "territories", "id": territory]],
                    "pricePoint": ["data": ["type": "inAppPurchasePricePoints", "id": point]]
                ]
            ]
        }
        let data = try await write("POST", "v1/inAppPurchaseOfferCodes", body: [
            "data": [
                "type": "inAppPurchaseOfferCodes",
                "attributes": [
                    "name": Self.giftOfferName,
                    "customerEligibilities": ["NON_SPENDER", "ACTIVE_SPENDER", "CHURNED_SPENDER"]
                ],
                "relationships": [
                    "inAppPurchase": ["data": ["type": "inAppPurchases", "id": id]],
                    "prices": ["data": included.map { ["type": "inAppPurchaseOfferPrices", "id": $0["id"] as! String] }]
                ]
            ],
            "included": included
        ])
        guard let offer = try? JSONDecoder().decode(ASCSingleDocument.self, from: data).data else { throw Failure.decoding }
        return offer.id
    }

    private func availableTerritories(productID id: String) async throws -> [String] {
        let availability = try await single("v2/inAppPurchases/\(id)/inAppPurchaseAvailability")
        let doc = try await list("v1/inAppPurchaseAvailabilities/\(availability.id)/availableTerritories", ["limit": "200"])
        return doc.data.map(\.id)
    }

    /// 나라 → 그 나라의 무료(0) 가격점 id. 나라마다 묻되 둘씩만 함께 — 요청 한도(429)에 덜 걸리게.
    private func freePricePoints(productID id: String, territories: [String]) async throws -> [String: String] {
        var found: [String: String] = [:]
        for chunk in stride(from: 0, to: territories.count, by: 2).map({ Array(territories[$0..<min($0 + 2, territories.count)]) }) {
            try await withThrowingTaskGroup(of: (String, String?).self) { group in
                for territory in chunk {
                    group.addTask { (territory, try await self.freePricePoint(productID: id, territory: territory)) }
                }
                for try await (territory, point) in group {
                    if let point { found[territory] = point }
                }
            }
        }
        return found
    }

    private func freePricePoint(productID id: String, territory: String) async throws -> String? {
        var next: URL? = url("v2/inAppPurchases/\(id)/pricePoints", [
            "filter[territory]": territory,
            "fields[inAppPurchasePricePoints]": "customerPrice",
            "limit": "200"
        ])
        while let current = next {
            let (data, status) = try await send(current)
            try check(data, status)
            guard let page = try? JSONDecoder().decode(ASCDocument.self, from: data) else { throw Failure.decoding }
            if let free = page.data.first(where: { Double($0.string("customerPrice") ?? "") == 0 }) { return free.id }
            next = page.next
        }
        return nil
    }
}

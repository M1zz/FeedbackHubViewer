//
//  AppStoreConnect+ProductNames.swift
//  FeedbackHubViewer
//
//  인앱 상품 · 구독의 표시 이름(언어마다). App Store 검색은 이 이름도 읽는다 — 키워드 칸
//  100자 밖에서 검색어를 더 거는 자리다. "Large Tip" 처럼 상품 종류만 적은 이름은 그 자리를 버린다.
//

import Foundation

/// 상품 하나의 한 언어 표시 이름.
struct ProductLocaleName: Identifiable, Hashable {
    /// 현지화 id — 고칠 때 쓴다.
    let id: String
    let product: StoreProduct
    let locale: String
    var name: String

    /// 표시 이름 한도(애플).
    static let limit = 30

    /// 상품 종류만 말하는 말. 이것뿐인 이름은 검색에 아무것도 걸지 않는다.
    static let genericWords: Set<String> = [
        "tip", "tips", "small", "medium", "large", "big", "pro", "plus", "premium", "lifetime", "life", "time",
        "monthly", "weekly", "yearly", "annual", "month", "week", "year", "subscription", "subscriber", "subscribers",
        "upgrade", "gift", "unlock", "full", "version", "for", "from", "the", "and", "of", "to", "a",
        "팁", "작은", "보통", "큰", "평생", "월간", "주간", "연간", "구독", "구독자", "프로", "플러스", "선물",
        "업그레이드", "이용권", "전체", "잠금", "해제", "무제한",
    ]

    /// 이름에서 상품 종류 · 앱 이름이 아닌 말. 비어 있으면 검색어가 없는 이름이다.
    func searchWords(appName: String) -> [String] {
        let appWords = Set(Self.words(appName))
        return Self.words(name).filter { !Self.genericWords.contains($0) && !appWords.contains($0) && $0.count > 1 }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

extension AppStoreConnect {

    /// 상품마다 모든 언어의 표시 이름.
    func productNames(_ products: [StoreProduct]) async throws -> [ProductLocaleName] {
        var names: [ProductLocaleName] = []
        for product in products {
            let isSubscription = product.kind == .autoRenewable
            let path = isSubscription
                ? "v1/subscriptions/\(product.id)/subscriptionLocalizations"
                : "v1/inAppPurchasesV2/\(product.id)/inAppPurchaseLocalizations"
            let field = isSubscription ? "fields[subscriptionLocalizations]" : "fields[inAppPurchaseLocalizations]"
            let doc = try await list(path, [field: "name,locale", "limit": "50"])
            for item in doc.data {
                guard let locale = item.string("locale") else { continue }
                names.append(ProductLocaleName(id: item.id, product: product, locale: locale,
                                               name: item.string("name") ?? ""))
            }
        }
        return names
    }

    /// 한 언어의 표시 이름을 바꾼다. 승인된 상품은 다음 앱 심사 때 같이 심사받는다.
    func rename(_ entry: ProductLocaleName, to name: String) async throws {
        let type = entry.product.kind == .autoRenewable ? "subscriptionLocalizations" : "inAppPurchaseLocalizations"
        _ = try await write("PATCH", "v1/\(type)/\(entry.id)", body: [
            "data": ["type": type, "id": entry.id, "attributes": ["name": name]]
        ])
    }
}

extension AppStoreConnectStore {

    func productNames(bundleID: String) async throws -> [ProductLocaleName] {
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        await loadCatalog(bundleID: bundleID)
        guard case .loaded(_, let products)? = catalogs[bundleID] else { return [] }
        return try await client.productNames(products)
    }

    func rename(_ entry: ProductLocaleName, to name: String) async throws {
        guard let client else { throw AppStoreConnect.Failure.missing("App Store Connect 키") }
        try await client.rename(entry, to: name)
    }
}

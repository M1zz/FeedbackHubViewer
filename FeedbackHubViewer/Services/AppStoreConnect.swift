//
//  AppStoreConnect.swift
//  FeedbackHubViewer
//
//  App Store Connect API — 앱 내 구입 상품과 판매 리포트를 읽는 문.
//
//  iTunes Search API(`AppStoreSearch.swift`)와 달리 이쪽은 **내 계정**의 문이다.
//  그래서 키가 필요하다: App Store Connect의 "사용자 및 액세스 → 통합"에서 만든
//  API 키(.p8)와 Issuer ID · Key ID. 요청마다 그 키로 서명한 JWT(ES256)를 붙인다.
//
//  읽는 것은 둘이다.
//
//    상품 — 앱마다 인앱 상품·구독의 이름, 상품 ID, 상태, 가격. 스토어에 지금 무엇이
//      걸려 있는지는 여기서만 참이다(스펙의 `purchases.products`는 손으로 적은 목록).
//
//    판매 리포트 — 하루 단위 요약(SALES · SUMMARY). 계정 전체가 한 파일이라, 하루치를
//      한 번 받으면 모든 앱의 숫자가 거기 있다. 지난 날의 리포트는 바뀌지 않으므로
//      날짜별로 한 번만 받는다. 판매자 번호(vendor number)가 있어야 한다.
//
//  **지금은 읽기만 한다.** 이 API는 가격을 바꾸고 상품을 지우는 것도 되지만, 그런
//  요청은 실수하면 곧바로 스토어에 나간다. 읽기가 믿을 만해진 다음에 붙인다.
//

import Foundation
import CryptoKit
import Security

// MARK: - 자격 증명

/// App Store Connect API 키 한 벌.
struct AppStoreConnectCredentials: Codable, Equatable {
    var issuerID: String
    var keyID: String
    /// .p8 파일 내용 그대로(-----BEGIN PRIVATE KEY----- …).
    var privateKey: String
    /// 판매 리포트용. 없으면 상품만 읽는다.
    var vendorNumber: String?

    var hasVendorNumber: Bool { !(vendorNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// 키가 실제로 읽히는가 — 저장하기 전에 확인한다. 틀린 키를 저장해 두면
    /// 화면은 매번 401만 보여 주고, 무엇이 틀렸는지는 말하지 못한다.
    func validate() throws {
        guard !issuerID.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppStoreConnect.Failure.missing("Issuer ID") }
        guard !keyID.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppStoreConnect.Failure.missing("Key ID") }
        do {
            _ = try P256.Signing.PrivateKey(pemRepresentation: privateKey.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw AppStoreConnect.Failure.badKey
        }
    }
}

/// 키는 리포도 UserDefaults도 아니라 키체인에 둔다. 한 벌을 JSON 하나로.
enum AppStoreConnectKeychain {
    private static let service = "com.Ysoup.FeedbackHubViewer.appstoreconnect"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> AppStoreConnectCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AppStoreConnectCredentials.self, from: data)
    }

    static func save(_ credentials: AppStoreConnectCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppStoreConnect.Failure.keychain(status) }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - 모델

/// 스토어에 걸린 상품 하나 — 인앱 구입이든 구독이든.
struct StoreProduct: Identifiable, Hashable {
    /// App Store Connect의 id. 판매 리포트의 Apple Identifier와 같은 값이다.
    let id: String
    let name: String
    let productID: String
    let kind: Kind
    let state: String
    /// 구독만 — 그룹 이름과 기간.
    var groupName: String?
    var period: String?
    /// "₩4,400" — 못 읽었으면 nil.
    var price: String?

    enum Kind: String, Hashable {
        case consumable = "CONSUMABLE"
        case nonConsumable = "NON_CONSUMABLE"
        case nonRenewing = "NON_RENEWING_SUBSCRIPTION"
        case autoRenewable = "AUTO_RENEWABLE"
        case unknown

        var label: String {
            switch self {
            case .consumable: return "소모성"
            case .nonConsumable: return "비소모성"
            case .nonRenewing: return "비갱신 구독"
            case .autoRenewable: return "자동 갱신 구독"
            case .unknown: return "알 수 없음"
            }
        }
    }

    /// 상태를 사람 말로. 모르는 값은 원문 그대로 — 감추면 새 상태가 생긴 걸 모른다.
    var stateLabel: String {
        switch state {
        case "APPROVED": return "판매 중"
        case "READY_TO_SUBMIT": return "제출 준비됨"
        case "WAITING_FOR_REVIEW": return "심사 대기"
        case "IN_REVIEW": return "심사 중"
        case "PENDING_BINARY_APPROVAL": return "앱 심사와 함께 대기"
        case "DEVELOPER_ACTION_NEEDED": return "조치 필요"
        case "REJECTED": return "거절됨"
        case "MISSING_METADATA": return "정보 부족"
        case "DEVELOPER_REMOVED_FROM_SALE": return "판매 중지"
        case "REMOVED_FROM_SALE": return "판매 중지 (Apple)"
        case "PREPARE_FOR_SUBMISSION": return "제출 준비 중"
        default: return state
        }
    }

    var isOnSale: Bool { state == "APPROVED" }

    var periodLabel: String? {
        switch period {
        case "ONE_WEEK": return "1주"
        case "ONE_MONTH": return "1개월"
        case "TWO_MONTHS": return "2개월"
        case "THREE_MONTHS": return "3개월"
        case "SIX_MONTHS": return "6개월"
        case "ONE_YEAR": return "1년"
        default: return period
        }
    }
}

/// App Store Connect에 있는 앱 하나.
struct ConnectApp: Hashable {
    let id: String
    let name: String
    let bundleID: String
}

/// 판매 리포트 한 줄에서 필요한 것만.
struct SalesLine: Hashable {
    let appleID: String
    let productType: String
    let units: Int
    /// 한 건당 개발자 수익(세금·수수료 뺀 것).
    let proceedsPerUnit: Double
    let proceedsCurrency: String

    /// 앱 첫 다운로드(업데이트·재다운로드 제외).
    var isFirstDownload: Bool { ["1", "1F", "1T", "F1"].contains(productType) }
    /// 인앱 구입·구독 결제.
    var isPurchase: Bool { productType.hasPrefix("IA") || productType == "FI1" }
}

// MARK: - 클라이언트

actor AppStoreConnect {

    enum Failure: LocalizedError {
        case missing(String)
        case badKey
        case keychain(OSStatus)
        case unauthorized
        case forbidden(String?)
        case http(Int, String?)
        case decoding
        case appNotFound(String)

        var errorDescription: String? {
            switch self {
            case .missing(let field): return "\(field)가 비어 있습니다."
            case .badKey: return "개인 키를 읽을 수 없습니다. .p8 파일 내용 전체(BEGIN/END 줄 포함)를 넣어 주세요."
            case .keychain(let status): return "키체인에 저장하지 못했습니다 (\(status))."
            case .unauthorized: return "App Store Connect가 키를 거절했습니다(401). Issuer ID · Key ID · 개인 키가 한 벌인지, 키가 폐기되지 않았는지 확인해 주세요."
            case .forbidden(let detail): return "이 키의 역할로는 볼 수 없는 정보입니다(403)." + (detail.map { " \($0)" } ?? "")
            case .http(let code, let detail): return "App Store Connect 오류 \(code)" + (detail.map { " — \($0)" } ?? "")
            case .decoding: return "App Store Connect 응답을 읽지 못했습니다."
            case .appNotFound(let bundle): return "App Store Connect에 번들 ID \(bundle)인 앱이 없습니다."
            }
        }
    }

    private let credentials: AppStoreConnectCredentials
    private var token: (value: String, expires: Date)?
    private static let base = URL(string: "https://api.appstoreconnect.apple.com")!

    init(credentials: AppStoreConnectCredentials) {
        self.credentials = credentials
    }

    // MARK: 인증

    /// 20분이 한도라 15분짜리를 만들어 두고 돌려 쓴다.
    private func bearer() throws -> String {
        if let token, token.expires > Date().addingTimeInterval(60) { return token.value }
        let key = try P256.Signing.PrivateKey(
            pemRepresentation: credentials.privateKey.trimmingCharacters(in: .whitespacesAndNewlines))
        let now = Date()
        let expires = now.addingTimeInterval(15 * 60)
        let header = ["alg": "ES256", "kid": credentials.keyID.trimmingCharacters(in: .whitespaces), "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": credentials.issuerID.trimmingCharacters(in: .whitespaces),
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expires.timeIntervalSince1970),
            "aud": "appstoreconnect-v1"
        ]
        let head = try Self.base64URL(JSONSerialization.data(withJSONObject: header))
        let body = try Self.base64URL(JSONSerialization.data(withJSONObject: payload))
        let input = Data("\(head).\(body)".utf8)
        let signature = try key.signature(for: input).rawRepresentation
        let value = "\(head).\(body).\(Self.base64URL(signature))"
        token = (value, expires)
        return value
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: 요청

    private func send(_ url: URL, accept: String = "application/json") async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func check(_ data: Data, _ status: Int) throws {
        guard !(200..<300).contains(status) else { return }
        let detail = (try? JSONDecoder().decode(ErrorDocument.self, from: data))?.errors.first
            .map { $0.detail ?? $0.title ?? "" }
        switch status {
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden(detail)
        default: throw Failure.http(status, detail)
        }
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// 목록 요청 — 다음 쪽이 있으면 끝까지 따라간다.
    private func list(_ path: String, _ query: [String: String] = [:]) async throws -> Document {
        var next: URL? = url(path, query)
        var merged = Document(data: [], included: [])
        while let current = next {
            let (data, status) = try await send(current)
            try check(data, status)
            guard let page = try? JSONDecoder().decode(Document.self, from: data) else { throw Failure.decoding }
            merged.data += page.data
            merged.included += page.included
            next = page.next
        }
        return merged
    }

    // MARK: 앱 · 상품

    func app(bundleID: String) async throws -> ConnectApp {
        let doc = try await list("v1/apps", ["filter[bundleId]": bundleID, "fields[apps]": "name,bundleId"])
        guard let app = doc.data.first(where: { $0.string("bundleId") == bundleID }) ?? doc.data.first else {
            throw Failure.appNotFound(bundleID)
        }
        return ConnectApp(id: app.id, name: app.string("name") ?? bundleID, bundleID: bundleID)
    }

    /// 이 앱의 인앱 상품과 구독 전부, 가격까지.
    func products(appID: String) async throws -> [StoreProduct] {
        var products: [StoreProduct] = []

        let iaps = try await list("v1/apps/\(appID)/inAppPurchasesV2", [
            "fields[inAppPurchases]": "name,productId,inAppPurchaseType,state",
            "limit": "200"
        ])
        for item in iaps.data {
            products.append(StoreProduct(
                id: item.id,
                name: item.string("name") ?? item.id,
                productID: item.string("productId") ?? "",
                kind: StoreProduct.Kind(rawValue: item.string("inAppPurchaseType") ?? "") ?? .unknown,
                state: item.string("state") ?? "UNKNOWN"))
        }

        let groups = try await list("v1/apps/\(appID)/subscriptionGroups", [
            "fields[subscriptionGroups]": "referenceName",
            "limit": "50"
        ])
        for group in groups.data {
            let subs = try await list("v1/subscriptionGroups/\(group.id)/subscriptions", [
                "fields[subscriptions]": "name,productId,state,subscriptionPeriod,groupLevel",
                "limit": "50"
            ])
            for item in subs.data.sorted(by: { ($0.int("groupLevel") ?? 0) < ($1.int("groupLevel") ?? 0) }) {
                products.append(StoreProduct(
                    id: item.id,
                    name: item.string("name") ?? item.id,
                    productID: item.string("productId") ?? "",
                    kind: .autoRenewable,
                    state: item.string("state") ?? "UNKNOWN",
                    groupName: group.string("referenceName"),
                    period: item.string("subscriptionPeriod")))
            }
        }

        // 가격은 상품마다 한 번씩 물어야 해서 따로 돈다. 하나를 못 읽어도 목록은 선다.
        for index in products.indices {
            products[index].price = try? await price(for: products[index])
        }
        return products
    }

    /// 지금 적용 중인 가격. 한국 가격이 따로 정해져 있으면 그것, 아니면 기준 국가의 가격.
    private func price(for product: StoreProduct) async throws -> String? {
        let today = Self.day.string(from: Date())
        func isCurrent(_ resource: Resource) -> Bool {
            let start = resource.string("startDate") ?? "0000-00-00"
            let end = resource.string("endDate") ?? "9999-99-99"
            return start <= today && today < end
        }

        if product.kind == .autoRenewable {
            for territory in ["KOR", "USA"] {
                let doc = try await list("v1/subscriptions/\(product.id)/prices", [
                    "filter[territory]": territory,
                    "include": "subscriptionPricePoint,territory",
                    "fields[subscriptionPricePoints]": "customerPrice",
                    "fields[territories]": "currency",
                    "limit": "50"
                ])
                if let current = doc.data.filter(isCurrent).max(by: { ($0.string("startDate") ?? "") < ($1.string("startDate") ?? "") }),
                   let text = Self.formatPrice(current, point: "subscriptionPricePoint", in: doc) {
                    return text
                }
            }
            return nil
        }

        let schedule = try await single("v2/inAppPurchases/\(product.id)/iapPriceSchedule")
        let doc = try await list("v1/inAppPurchasePriceSchedules/\(schedule.id)/manualPrices", [
            "include": "inAppPurchasePricePoint,territory",
            "fields[inAppPurchasePricePoints]": "customerPrice",
            "fields[territories]": "currency",
            "limit": "200"
        ])
        let current = doc.data.filter(isCurrent)
        let korean = current.first { $0.relationshipID("territory") == "KOR" }
        guard let chosen = korean ?? current.first else { return nil }
        return Self.formatPrice(chosen, point: "inAppPurchasePricePoint", in: doc)
    }

    private func single(_ path: String) async throws -> Resource {
        let (data, status) = try await send(url(path))
        try check(data, status)
        guard let doc = try? JSONDecoder().decode(SingleDocument.self, from: data) else { throw Failure.decoding }
        return doc.data
    }

    private static func formatPrice(_ price: Resource, point: String, in doc: Document) -> String? {
        guard let pointID = price.relationshipID(point),
              let pricePoint = doc.included.first(where: { $0.id == pointID }),
              let amount = pricePoint.string("customerPrice").flatMap(Double.init) else { return nil }
        let territoryID = price.relationshipID("territory")
        let currency = doc.included.first { $0.type == "territories" && $0.id == territoryID }?.string("currency")
        return formatMoney(amount, currency: currency)
    }

    static func formatMoney(_ amount: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "ko_KR")
        if let currency { formatter.currencyCode = currency }
        if currency == nil { formatter.numberStyle = .decimal }
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    // MARK: 판매 리포트

    /// 하루치 판매 요약. 그날 판매가 하나도 없거나 아직 안 나왔으면 빈 배열(404).
    func sales(on date: Date) async throws -> [SalesLine] {
        guard let vendor = credentials.vendorNumber?.trimmingCharacters(in: .whitespaces), !vendor.isEmpty else {
            throw Failure.missing("판매자 번호")
        }
        let (data, status) = try await send(url("v1/salesReports", [
            "filter[frequency]": "DAILY",
            "filter[reportType]": "SALES",
            "filter[reportSubType]": "SUMMARY",
            "filter[vendorNumber]": vendor,
            "filter[reportDate]": Self.day.string(from: date),
            "filter[version]": "1_1"
        ]), accept: "application/a-gzip")
        if status == 404 { return [] }
        try check(data, status)
        guard let text = Self.gunzip(data).flatMap({ String(data: $0, encoding: .utf8) }) else { throw Failure.decoding }
        return Self.parseSales(text)
    }

    static func parseSales(_ text: String) -> [SalesLine] {
        var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst()
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let apple = column("Apple Identifier"), let type = column("Product Type Identifier"),
              let units = column("Units"), let proceeds = column("Developer Proceeds"),
              let currency = column("Currency of Proceeds") else { return [] }
        return lines.compactMap { row in
            guard row.count > max(apple, type, units, proceeds, currency) else { return nil }
            return SalesLine(appleID: row[apple],
                             productType: row[type],
                             units: Int(Double(row[units]) ?? 0),
                             proceedsPerUnit: Double(row[proceeds]) ?? 0,
                             proceedsCurrency: row[currency])
        }
    }

    /// gzip 머리와 꼬리를 떼고 남은 DEFLATE를 푼다.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b else {
            // 이미 풀려서 온 경우.
            return data
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard bytes.count > offset + 2 else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // 판매 리포트의 하루는 태평양 시간 기준이다.
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - JSON:API

private struct ErrorDocument: Decodable {
    struct Item: Decodable { let title: String?; let detail: String? }
    let errors: [Item]
}

private struct SingleDocument: Decodable {
    let data: Resource
}

private struct Document: Decodable {
    var data: [Resource]
    var included: [Resource]
    var next: URL?

    init(data: [Resource], included: [Resource]) {
        self.data = data
        self.included = included
    }

    enum CodingKeys: String, CodingKey { case data, included, links }
    struct Links: Decodable { let next: URL? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([Resource].self, forKey: .data)
        included = try c.decodeIfPresent([Resource].self, forKey: .included) ?? []
        next = try c.decodeIfPresent(Links.self, forKey: .links)?.next
    }
}

private struct Resource: Decodable {
    let id: String
    let type: String
    let attributes: [String: JSONValue]?
    let relationships: [String: Relationship]?

    struct Relationship: Decodable {
        struct Link: Decodable { let id: String; let type: String }
        let data: Link?

        enum CodingKeys: String, CodingKey { case data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 여럿을 가리키는 관계(배열)는 여기서 안 쓴다.
            data = try? c.decodeIfPresent(Link.self, forKey: .data)
        }
    }

    func string(_ key: String) -> String? {
        if case .string(let value)? = attributes?[key] { return value }
        if case .number(let value)? = attributes?[key] { return String(value) }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .number(let value)? = attributes?[key] { return Int(value) }
        return nil
    }

    func relationshipID(_ key: String) -> String? { relationships?[key]?.data?.id }
}

private enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), null, other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else { self = .other }
    }
}

//
//  AppStoreConnect+Reviews.swift
//  FeedbackHubViewer
//
//  App Store 리뷰와 개발자 응답 — ReviewManager 에서 옮겨 온 문.
//
//  피드백 허브는 앱 안에서 **스스로 말하러 온** 사람의 목소리이고, 리뷰는 스토어에
//  **남들 보라고** 쓴 목소리다. 둘은 같은 사람이 다른 자리에서 하는 말이라 한 앱의
//  화면 안에 나란히 있어야 한다.
//
//  이 문은 **쓴다**. 응답을 달고, 고치고, 지운다. 앱 내 구입과 달리 쓰기를 허락하는
//  까닭은 실수의 크기다: 응답은 리뷰 한 건에 붙는 글이고, 틀렸으면 다시 달거나 지우면
//  된다. 가격처럼 모든 고객에게 한꺼번에 나가지 않는다.
//
//  응답 "수정"은 따로 없다. App Store Connect 는 같은 리뷰에 새 응답을 만들면 옛 것을
//  갈아 끼운다 — 그래서 달기와 고치기가 같은 요청이다.
//

import Foundation

// MARK: - 모델

/// 스토어에 달린 리뷰 한 건.
struct CustomerReview: Identifiable, Hashable, Codable {
    let id: String
    let rating: Int
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: Date
    /// "KOR", "USA" 같은 세 글자 지역 코드.
    let territory: String
    var response: ReviewResponse?

    /// 하루 안에 올라왔고 아직 답하지 않은 리뷰.
    var isNew: Bool {
        response == nil && createdDate > Date().addingTimeInterval(-24 * 3600)
    }

    /// 답이 필요한데 하루가 넘게 비어 있다.
    var isWaitingForResponse: Bool { response == nil && !isNew }

    /// 제목과 본문을 한 덩어리로 — 복사와 번역이 쓴다.
    var fullText: String {
        [title, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// "대한민국" — 세 글자 코드를 두 글자로 바꿔 지역 이름을 얻는다.
    var territoryName: String { ReviewTerritory.name(for: territory) }
}

/// 리뷰에 단 개발자 응답.
struct ReviewResponse: Identifiable, Hashable, Codable {
    let id: String
    let responseBody: String
    let lastModifiedDate: Date
    /// "PUBLISHED" 또는 "PENDING_PUBLISH". 모르는 값은 원문 그대로 둔다.
    let state: String

    var isPublished: Bool { state == "PUBLISHED" }

    var stateLabel: String {
        switch state {
        case "PUBLISHED": return "게시됨"
        case "PENDING_PUBLISH": return "게시 대기"
        default: return state
        }
    }
}

/// App Store 에 가장 최근에 만든 버전과 그 상태.
struct AppVersionStatus: Hashable, Codable {
    let version: String
    let state: String

    var stateLabel: String {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": return "판매 중"
        case "PREPARE_FOR_SUBMISSION": return "제출 준비 중"
        case "WAITING_FOR_REVIEW": return "심사 대기"
        case "IN_REVIEW": return "심사 중"
        case "PENDING_DEVELOPER_RELEASE": return "출시 대기 (직접 출시)"
        case "PENDING_APPLE_RELEASE": return "출시 대기"
        case "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION": return "처리 중"
        case "REJECTED": return "거절됨"
        case "METADATA_REJECTED": return "메타데이터 거절"
        case "DEVELOPER_REJECTED": return "개발자가 철회"
        case "INVALID_BINARY": return "바이너리 오류"
        case "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE": return "판매 중지"
        case "WAITING_FOR_EXPORT_COMPLIANCE": return "수출 규정 대기"
        default: return state
        }
    }

    /// 초록(나가 있음) · 주황(움직이는 중) · 빨강(막힘).
    var tone: Tone {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": return .live
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
             "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE": return .blocked
        default: return .moving
        }
    }

    enum Tone { case live, moving, blocked }
}

enum ReviewTerritory {
    /// App Store Connect 는 ISO 3166-1 alpha-3 를 쓰고, `Locale` 은 alpha-2 만 안다.
    private static let alpha2: [String: String] =
        Dictionary(uniqueKeysWithValues: alpha3.map { ($0.value, $0.key) })

    /// 리뷰가 실제로 오는 지역만 손으로 적은 표. 여기 없는 코드는 원문 그대로 보인다.
    private static let alpha3: [String: String] = [
        "KR": "KOR", "US": "USA", "JP": "JPN", "CN": "CHN", "TW": "TWN", "HK": "HKG",
        "GB": "GBR", "DE": "DEU", "FR": "FRA", "IT": "ITA", "ES": "ESP", "NL": "NLD",
        "CA": "CAN", "AU": "AUS", "NZ": "NZL", "BR": "BRA", "MX": "MEX", "AR": "ARG",
        "IN": "IND", "ID": "IDN", "TH": "THA", "VN": "VNM", "PH": "PHL", "MY": "MYS",
        "SG": "SGP", "RU": "RUS", "UA": "UKR", "PL": "POL", "TR": "TUR", "SA": "SAU",
        "AE": "ARE", "IL": "ISR", "SE": "SWE", "NO": "NOR", "DK": "DNK", "FI": "FIN",
        "CH": "CHE", "AT": "AUT", "BE": "BEL", "PT": "PRT", "IE": "IRL", "CZ": "CZE",
        "HU": "HUN", "RO": "ROU", "GR": "GRC", "ZA": "ZAF", "EG": "EGY", "CL": "CHL",
        "CO": "COL", "PE": "PER", "KZ": "KAZ", "PK": "PAK", "BD": "BGD"
    ]

    static func name(for code: String) -> String {
        let two = alpha2[code] ?? (code.count == 2 ? code : nil)
        guard let two else { return code }
        return AppFormat.locale.localizedString(forRegionCode: two) ?? code
    }
}

// MARK: - 요청

extension AppStoreConnect {

    /// 이 앱의 리뷰 전부, 달린 응답까지. 최신이 앞이다.
    func reviews(appID: String) async throws -> [CustomerReview] {
        let doc = try await list("v1/apps/\(appID)/customerReviews", [
            "include": "response",
            "sort": "-createdDate",
            "limit": "200"
        ])
        var responses: [String: ReviewResponse] = [:]
        for item in doc.included where item.type == "customerReviewResponses" {
            responses[item.id] = ReviewResponse(
                id: item.id,
                responseBody: item.string("responseBody") ?? "",
                lastModifiedDate: Self.parseDate(item.string("lastModifiedDate")) ?? .distantPast,
                state: item.string("state") ?? "PUBLISHED")
        }
        return doc.data.map { item in
            CustomerReview(
                id: item.id,
                rating: item.int("rating") ?? 0,
                title: item.string("title"),
                body: item.string("body"),
                reviewerNickname: item.string("reviewerNickname"),
                createdDate: Self.parseDate(item.string("createdDate")) ?? .distantPast,
                territory: item.string("territory") ?? "",
                response: item.relationshipID("response").flatMap { responses[$0] })
        }
    }

    /// 가장 최근에 만든 App Store 버전. 버전이 하나도 없으면 nil.
    ///
    /// 이 관계는 정렬을 받지 않아서 한 쪽(최대 200개)을 받아 만든 날짜로 고른다. `list` 는
    /// 다음 쪽을 끝까지 따라가므로 쓰지 않는다 — 버전이 200개를 넘는 앱은 없다.
    func latestVersion(appID: String) async throws -> AppVersionStatus? {
        let (data, status) = try await send(url("v1/apps/\(appID)/appStoreVersions", [
            "fields[appStoreVersions]": "versionString,appStoreState,createdDate",
            "limit": "200"
        ]))
        try check(data, status)
        guard let page = try? JSONDecoder().decode(ASCDocument.self, from: data) else { throw Failure.decoding }
        let latest = page.data.max {
            (Self.parseDate($0.string("createdDate")) ?? .distantPast) < (Self.parseDate($1.string("createdDate")) ?? .distantPast)
        }
        guard let latest else { return nil }
        return AppVersionStatus(version: latest.string("versionString") ?? "?",
                                state: latest.string("appStoreState") ?? "UNKNOWN")
    }

    /// 응답을 달거나 갈아 끼운다. 스토어가 받아들인 응답을 돌려준다.
    @discardableResult
    func respond(to reviewID: String, body text: String) async throws -> ReviewResponse {
        let data = try await write("POST", "v1/customerReviewResponses", body: [
            "data": [
                "type": "customerReviewResponses",
                "attributes": ["responseBody": text],
                "relationships": [
                    "review": ["data": ["type": "customerReviews", "id": reviewID]]
                ]
            ]
        ])
        guard let created = try? JSONDecoder().decode(ASCSingleDocument.self, from: data).data else {
            throw Failure.decoding
        }
        return ReviewResponse(id: created.id,
                              responseBody: created.string("responseBody") ?? text,
                              lastModifiedDate: Self.parseDate(created.string("lastModifiedDate")) ?? Date(),
                              state: created.string("state") ?? "PENDING_PUBLISH")
    }

    func deleteResponse(id: String) async throws {
        var request = URLRequest(url: url("v1/customerReviewResponses/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// "2025-03-01T09:12:44-08:00" — 소수 초가 붙어 올 때도 있다.
    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        if let date = isoPlain.date(from: text) { return date }
        return isoFractional.date(from: text)
    }

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

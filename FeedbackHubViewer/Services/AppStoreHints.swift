//
//  AppStoreHints.swift
//  FeedbackHubViewer
//
//  App Store 검색창의 자동완성. 검색량을 대신하는 유일한 공개 신호다.
//
//  자동완성에는 사람들이 실제로 많이 치는 말이 앞에 뜬다. 그래서 "몇 글자를 쳐야
//  그 검색어가 뜨는가"가 곧 얼마나 많이 검색되는가의 근사다. "키"만 쳐도 뜨는
//  "키보드"는 많이 찾는 말이고, 다 쳐도 안 뜨는 "상용구"는 거의 안 찾는 말이다.
//
//  숫자가 아니라 **차례**다. Apple 은 검색량을 내놓지 않고, 이것도 검색량이 아니다.
//  같은 가게 안에서 검색어끼리 견주는 데까지만 믿는다.
//
//  응답에는 검색어와 앱 이름이 섞여 온다("복붙 성경! - 복사&붙여넣기 성경"). 앱 이름은
//  그 말로 찾는 사람이 적어 앱 쪽이 자리를 채운 것이므로, 검색어로 치지 않는다.
//

import Foundation

actor AppStoreHints {

    static let shared = AppStoreHints()

    /// 검색 API(`AppStoreDirectory`)와는 다른 문이라 제한도 따로다. 한 글자씩 늘려 가며
    /// 묻다 보니 요청이 많아, 1초 간격으로 줄 세운다.
    private static let minimumInterval: TimeInterval = 1

    private var lastRequest = Date.distantPast
    /// (가게, 입력) → 자동완성. "키보"를 물은 결과는 "키보드"와 "키보드 테마"가 함께 쓴다.
    private var cache: [String: [String]] = [:]

    /// 자동완성이 되는 가게. 헤더에 가게 번호가 들어가야 그 나라의 자동완성이 온다.
    static let storefrontIds: [String: Int] = [
        "kr": 143466, "us": 143441, "jp": 143462, "gb": 143444, "de": 143443,
        "fr": 143442, "ca": 143455, "au": 143460, "cn": 143465, "tw": 143470,
        "hk": 143463, "sg": 143464, "mx": 143468, "br": 143503, "es": 143454,
        "it": 143450, "in": 143467, "id": 143476, "th": 143475, "vn": 143471,
    ]

    static func supports(_ country: String) -> Bool { storefrontIds[country] != nil }

    /// `input` 을 쳤을 때 뜨는 자동완성, 뜨는 차례대로.
    func hints(for input: String, country: String) async throws -> [String] {
        let key = "\(country)/\(input)"
        if let cached = cache[key] { return cached }
        guard let storefront = Self.storefrontIds[country] else { return [] }

        try await pace()
        var components = URLComponents(string: "https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints")!
        components.queryItems = [URLQueryItem(name: "clientApplication", value: "Software"),
                                 URLQueryItem(name: "term", value: input)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("FeedbackHubViewer/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("\(storefront),29", forHTTPHeaderField: "X-Apple-Store-Front")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 403 ? AppStoreDirectory.Failure.throttled
                                         : AppStoreDirectory.Failure.badResponse(http.statusCode)
        }
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let terms = (plist?["hints"] as? [[String: Any]] ?? []).compactMap { $0["term"] as? String }
        cache[key] = terms
        return terms
    }

    private func pace() async throws {
        let wait = Self.minimumInterval - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequest = Date()
    }
}

//
//  KeywordRecommendation.swift
//  FeedbackHubViewer
//
//  "검색이 많이 되고, 내가 올라갈 수 있는 검색어" 순위.
//
//  두 가지를 곱한다.
//
//   검색 인기 — 자동완성(`AppStoreHints`)에서 몇 글자 만에 뜨는가. 첫 글자에 맨 앞에
//               뜨면 100, 다 쳐야 겨우 뜨면 낮고, 다 쳐도 안 뜨면 0. 짧게 쳐서 뜰수록
//               그 말을 치는 사람이 많다는 뜻이다.
//   닿을 거리 — 그 검색어에서 지금 몇 위인가. 이미 10위 안이면 지키기만 하면 되고,
//               200위 밖이면 이름 · 부제 · 키워드 칸에 넣어야 시작된다.
//
//  그리고 **관련 없는 말은 뺀다.** 자동완성은 "키보드"에서 "키보드 연습"을, "문구"에서
//  "문구도매"를 이어 붙인다. 그 검색 결과 상위 10개에 이 앱의 이웃(같은 검색어에서
//  함께 뜨는 앱)이 거의 없고 나도 없으면, 사람은 많이 찾아도 이 앱을 찾는 사람이 아니다.
//
//  여기는 계산만 한다. 요청은 `KeywordStore.recommend(for:)` 가 한다.
//

import Foundation

enum KeywordRecommendation {

    /// 한 번 돌린 결과. 앱 · 가게마다 하나, 다음 번까지 디스크에 남는다.
    struct Report: Codable, Equatable {
        let country: String
        let measuredAt: Date
        let items: [Item]
        /// 후보였지만 관련이 없어 뺀 것. 왜 이 말이 없냐는 물음에 답하려고 둔다.
        let dropped: [String]
    }

    struct Item: Codable, Equatable, Identifiable {
        let term: String
        /// 0~100. 자동완성에 다 쳐도 안 뜨면 0.
        let popularity: Int
        /// 몇 글자를 쳤을 때 처음 떴는가. 안 뜨면 nil.
        let typedToAppear: Int?
        /// 지금 순위. 200위 안에 없으면 nil.
        let rank: Int?
        /// 상위 10개 중 이 앱의 이웃 수.
        let neighbours: Int
        /// 상위 5개 앱의 평점 수 중앙값. 뚫기 어려운 정도의 거친 근사.
        let topRatings: Int
        var id: String { term }

        var verdict: Verdict { KeywordRecommendation.verdict(self) }
        var score: Double { KeywordRecommendation.score(self) }
    }

    enum Verdict: String, Codable {
        /// 10위 안. 지금 오는 사람을 잃지 않는 게 일이다.
        case keep
        /// 11~100위. 메타데이터를 다듬으면 올라갈 만한 자리.
        case climb
        /// 100위 밖이거나 안 잡힘. 이름 · 부제 · 키워드 칸에 넣어야 시작된다.
        case target

        var label: String {
            switch self {
            case .keep: return "지키기"
            case .climb: return "올릴 만함"
            case .target: return "새로 노리기"
            }
        }
    }

    /// 이 아래는 추천에서 뺀다. 자동완성에 늦게 뜨는 말은 쳐 봐야 오는 사람이 적다.
    static let minimumPopularity = 30
    /// 상위 10개 중 이웃이 이만큼은 있어야 이 앱을 찾는 사람의 검색어로 본다
    /// (내가 이미 100위 안이면 이것 없이도 관련 있다).
    static let minimumNeighbours = 2
    /// 평점이 이만큼 넘는 앱은 이웃으로 치지 않는다. 어느 검색에나 끼는 앱이라
    /// 관련성을 가르는 데 쓸모가 없다.
    static let giantRatings = 50_000

    // MARK: - 검색 인기

    /// `term` 을 한 글자씩 쳐 가며 받은 자동완성에서 처음 뜬 자리.
    /// `hintsByPrefix[i]` 는 앞 `i + 1` 글자를 쳤을 때의 자동완성이다.
    ///
    /// 점수는 두 가지로 깎인다. 늦게 뜰수록(친 글자 / 전체 글자), 목록 뒤에 뜰수록.
    /// 띄어쓰기는 글자로 세지 않는다 — "키보드 테마"는 다섯 글자다.
    static func popularity(of term: String, hintsByPrefix: [[String]]) -> (score: Int, typed: Int?) {
        let target = compact(term)
        let length = max(target.count, 1)
        for (index, hints) in hintsByPrefix.enumerated() {
            guard let position = hints.firstIndex(where: { compact($0) == target }) else { continue }
            let typed = compact(prefixes(of: term)[safe: index] ?? term).count
            let early = 1 - Double(typed - 1) / Double(length)
            let front = 1 - 0.5 * Double(position) / Double(max(hints.count, 1))
            return (Int((100 * early * front).rounded()), typed)
        }
        return (0, nil)
    }

    /// 한 글자씩 늘린 입력. 띄어쓰기로 끝나는 것은 앞 것과 같은 질문이라 뺀다.
    static func prefixes(of term: String) -> [String] {
        let characters = Array(term.trimmingCharacters(in: .whitespaces))
        return (1...max(characters.count, 1)).compactMap { length in
            guard length <= characters.count else { return nil }
            let prefix = String(characters[0..<length])
            return prefix.hasSuffix(" ") ? nil : prefix
        }
    }

    static func compact(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: - 후보

    /// 자동완성 줄 중 검색어로 보이는 것. 앱 이름("복붙 성경! - 복사&붙여넣기 성경")은
    /// 그 말로 찾는 사람이 적어 앱이 자리를 채운 것이라 뺀다.
    static func looksLikeSearchTerm(_ hint: String) -> Bool {
        guard hint.count <= 14 else { return false }
        let appNameMarks = CharacterSet(charactersIn: "-:!&()|·,–—・/+[]")
        return hint.unicodeScalars.allSatisfy { !appNameMarks.contains($0) }
    }

    // MARK: - 판정

    static func verdict(_ item: Item) -> Verdict {
        guard let rank = item.rank else { return .target }
        if rank <= 10 { return .keep }
        if rank <= 100 { return .climb }
        return .target
    }

    /// 관련 있는 말인가. 이미 100위 안이면 스토어가 관련 있다고 본 것이다.
    static func isRelevant(rank: Int?, neighbours: Int) -> Bool {
        if let rank, rank <= 100 { return true }
        return neighbours >= minimumNeighbours
    }

    /// 순위에 쓰는 값. 인기 × 닿을 거리 × 뚫기 쉬움.
    ///
    /// 닿을 거리는 이미 가진 것을 가장 높게 친다. 새 검색어 하나를 여는 것보다
    /// 20위를 5위로 올리는 쪽이 오는 사람이 확실히 는다.
    static func score(_ item: Item) -> Double {
        let reach: Double
        switch item.rank {
        case let rank? where rank <= 10: reach = 1.0
        case let rank? where rank <= 30: reach = 0.85
        case let rank? where rank <= 100: reach = 0.65
        case .some: reach = 0.45
        case nil: reach = 0.35
        }
        // 상위 앱들이 평점 수만 개면 새로 들어가 뚫기 어렵다. 이미 10위 안이면 상관없다.
        let crowd: Double
        if let rank = item.rank, rank <= 10 {
            crowd = 1
        } else {
            switch item.topRatings {
            case ..<1_000: crowd = 1
            case ..<10_000: crowd = 0.85
            default: crowd = 0.7
            }
        }
        return Double(item.popularity) * reach * crowd
    }

    /// 추천에 올릴 것만, 점수 순으로.
    static func ranked(_ items: [Item]) -> [Item] {
        items
            .filter { $0.popularity >= minimumPopularity && isRelevant(rank: $0.rank, neighbours: $0.neighbours) }
            .sorted { $0.score == $1.score ? $0.term < $1.term : $0.score > $1.score }
    }

    /// 행 아래에 붙는 이유 한 줄. 숫자가 아니라 그 숫자가 뜻하는 것을 적는다.
    static func reason(_ item: Item) -> String {
        var parts: [String] = []
        switch item.typedToAppear {
        case 1?: parts.append("첫 글자에 자동완성")
        case let typed?: parts.append("\(typed)글자 치면 자동완성")
        case nil: parts.append("자동완성에 안 뜸")
        }
        if let rank = item.rank { parts.append("지금 \(rank)위") } else { parts.append("200위 안에 없음") }
        if item.rank.map({ $0 > 10 }) ?? true {
            switch item.topRatings {
            case ..<1_000: parts.append("상위 앱 평점 적음")
            case 10_000...: parts.append("상위 앱 평점 많음")
            default: break
            }
        }
        return parts.joined(separator: " · ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

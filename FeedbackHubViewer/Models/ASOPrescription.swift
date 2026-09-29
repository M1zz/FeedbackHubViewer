//
//  ASOPrescription.swift
//  FeedbackHubViewer
//
//  검색으로 들어오는 길을 고치는 처방. "키워드 필드에서 무엇을 빼고 무엇을 넣을지"를
//  정해서 새 필드까지 만들어 준다.
//
//  재료는 전부 허브가 이미 가진 것이다.
//   · 지금 스토어에 나가 있는 이름 · 부제 · 키워드 필드 (App Store Connect)
//   · 추적 중인 검색어마다 이 앱의 순위 (KeywordStore)
//   · 그 검색어들에서 이 앱보다 위에 선 경쟁 앱의 이름
//
//  규칙:
//   빼기  1) 두 번 적은 단어 · 이름이나 부제에 이미 있는 단어 — 빼도 똑같이 잡힌다
//         2) 순위를 재 봤는데 결과창(상위 30) 안에 없는 단어 — 자리만 차지한다
//         3) 50위 밖 — 오르기 어렵다
//   넣기  1) 이미 순위가 있는데 메타데이터 어디에도 없는 단어 — 넣으면 더 오른다
//         2) 위에 선 경쟁 앱 이름 여러 곳에 공통으로 든 단어 — 이 카테고리가 쓰는 말
//   순위를 안 잰 단어는 **빼지도 남기지도 판단하지 않는다.** 그건 "정보가 필요하다"로 돌린다.
//
//  순수 함수라 뷰도 네트워크도 모른다.
//

import Foundation

struct ASOPrescription {

    /// 키워드 필드의 한 단어를 어떻게 볼 것인가.
    struct Removal: Identifiable {
        let term: String
        let reason: String
        var id: String { term }
    }

    struct Addition: Identifiable {
        let term: String
        let reason: String
        var id: String { term }
    }

    /// "A → B" 한 쌍. `from` 이 nil 이면 정리해서 생긴 빈 자리에 넣는 것.
    struct Swap: Identifiable {
        let from: Removal?
        let to: Addition
        var id: String { (from?.term ?? "+") + "→" + to.term }
    }

    let locale: String
    let currentField: String
    let proposedField: String
    let swaps: [Swap]
    /// 짝 없이 빼기만 하는 것(넣을 후보가 모자람).
    let dropsOnly: [Removal]
    /// 순위를 안 재서 판단을 미룬 키워드 필드의 단어.
    let untracked: [String]
    /// 순위가 잡힌 검색어 중 상위 10 안.
    let topTen: [String]
    let rankedCount: Int
    let trackedCount: Int
    /// 부제에 가장 잘 잡히는 검색어가 없으면 그 말.
    let subtitleHint: String?

    var hasChange: Bool { proposedField != currentField }

    /// 한 줄 요약. "지금 할 일"에 그대로 들어간다.
    var headline: String? {
        if !swaps.isEmpty {
            let pairs = swaps.prefix(3).map { swap in
                swap.from.map { "'\($0.term)' → '\(swap.to.term)'" } ?? "'\(swap.to.term)' 추가"
            }
            let more = swaps.count > 3 ? " 외 \(swaps.count - 3)개" : ""
            return "키워드 필드에서 " + pairs.joined(separator: ", ") + more
        }
        if !dropsOnly.isEmpty {
            return "키워드 필드에서 " + dropsOnly.prefix(3).map { "'\($0.term)'" }.joined(separator: ", ") + " 빼기"
        }
        return nil
    }

    // MARK: - 입력

    struct Ranking {
        let term: String
        /// nil 이면 재 봤는데 결과창 안에 없음.
        let rank: Int?
        /// 한 번도 안 재 봄.
        let unchecked: Bool
    }

    static let weakRank = 50

    static func make(text: StoreMetadata.LocaleText,
                     rankings: [Ranking],
                     rivalNames: [String]) -> ASOPrescription {
        let limit = StoreMetadata.Limit.keywords
        let audit = MetadataAudit.keywordField(text)
        let byTerm = Dictionary(rankings.map { (MetadataAudit.normalize($0.term), $0) },
                                uniquingKeysWith: { a, _ in a })

        // 빼기 ----------------------------------------------------------------
        var removals: [Removal] = []
        for term in audit.duplicates {
            removals.append(.init(term: term, reason: "두 번 적었어요"))
        }
        for term in audit.alreadyIndexed {
            removals.append(.init(term: term, reason: "이름이나 부제에 이미 있어 빼도 똑같이 잡혀요"))
        }
        var untracked: [String] = []
        var keptTerms: [String] = []
        let cleanedTerms = audit.cleaned.split(separator: ",").map(String.init)
        for term in cleanedTerms {
            guard let ranking = byTerm[MetadataAudit.normalize(term)], !ranking.unchecked else {
                untracked.append(term)
                keptTerms.append(term)
                continue
            }
            if let rank = ranking.rank {
                if rank > weakRank {
                    removals.append(.init(term: term, reason: "\(rank)위라 오르기 어려워요"))
                } else {
                    keptTerms.append(term)
                }
            } else {
                removals.append(.init(term: term, reason: "검색해도 상위 30 안에 안 나와요"))
            }
        }

        // 넣기 ----------------------------------------------------------------
        let indexed = [text.name, text.subtitle, keptTerms.joined(separator: " ")].joined(separator: " ")
        var additions: [Addition] = []
        var seen: Set<String> = Set(removals.map { MetadataAudit.normalize($0.term) })

        // 1) 이미 순위가 있는데 메타데이터에 없는 말.
        for ranking in rankings.sorted(by: { ($0.rank ?? .max) < ($1.rank ?? .max) }) {
            guard let rank = ranking.rank, rank <= weakRank else { continue }
            let coverage = MetadataAudit.coverage(of: ranking.term, in: text)
            for word in coverage.missingWords where !MetadataAudit.contains(indexed, word) {
                let key = MetadataAudit.normalize(word)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                additions.append(.init(term: word, reason: "'\(ranking.term)' 에서 이미 \(rank)위인데 메타데이터에 없어요"))
            }
        }

        // 2) 위에 선 경쟁 앱 이름에 공통으로 든 말.
        var owners: [String: Int] = [:]
        for name in Set(rivalNames) {
            let words = Set(name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 })
            for word in words { owners[word, default: 0] += 1 }
        }
        for (word, count) in owners.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value })
        where count >= 2 {
            let key = MetadataAudit.normalize(word)
            guard !MetadataAudit.contains(indexed, word), seen.insert(key).inserted else { continue }
            additions.append(.init(term: word, reason: "위에 선 경쟁 앱 \(count)곳의 이름에 들어 있어요"))
        }

        // 필드 다시 짜기 --------------------------------------------------------
        var field = keptTerms
        var accepted: [Addition] = []
        for addition in additions {
            let candidate = (field + [addition.term]).joined(separator: ",")
            if candidate.count <= limit {
                field.append(addition.term)
                accepted.append(addition)
            }
        }
        let proposed = field.joined(separator: ",")

        var swaps: [Swap] = []
        var remainingRemovals = removals
        for addition in accepted {
            let from = remainingRemovals.isEmpty ? nil : remainingRemovals.removeFirst()
            swaps.append(.init(from: from, to: addition))
        }

        // 부제: 가장 잘 잡히는 검색어가 부제에 없으면 알린다. 부제는 키워드 필드보다 무겁다.
        let ranked = rankings.filter { $0.rank != nil }.sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
        var subtitleHint: String?
        if let best = ranked.first(where: { !MetadataAudit.contains(text.name + " " + text.subtitle, $0.term) }),
           let rank = best.rank {
            subtitleHint = "가장 잘 잡히는 검색어 '\(best.term)'(\(rank)위)가 이름 · 부제에 없어요. 부제에 넣으면 키워드 필드보다 무겁게 셉니다."
        }

        return ASOPrescription(
            locale: text.locale,
            currentField: text.keywords,
            proposedField: removals.isEmpty && accepted.isEmpty ? text.keywords : proposed,
            swaps: swaps,
            dropsOnly: remainingRemovals,
            untracked: untracked,
            topTen: ranked.filter { ($0.rank ?? .max) <= 10 }.map(\.term),
            rankedCount: ranked.count,
            trackedCount: rankings.count,
            subtitleHint: subtitleHint)
    }
}

//
//  MetadataAudit.swift
//  FeedbackHubViewer
//
//  스토어 메타데이터를 검색의 눈으로 읽는다 — 키워드 필드가 글자를 어디에 흘리고
//  있는지, 추적 중인 키워드가 메타데이터 어디에 들어 있는지.
//
//  App Store 검색은 이름 · 부제 · 키워드 필드를 한데 모아 색인한다. 그래서:
//
//   - 키워드 필드의 쉼표 옆 공백은 글자만 먹는다. 100자 중 16자를 공백에 쓰는 것은
//     단어 두세 개를 버리는 것과 같다.
//   - 이름이나 부제에 이미 있는 단어를 키워드 필드에 또 적어도 더 잡히지 않는다.
//   - 같은 단어를 두 번 적어도 마찬가지다.
//
//  네트워크와 떼어 둔 순수 문자열 작업이다. 형태소 분석은 하지 않는다 — 한국어
//  복합어는 부분 문자열로 비교하는 것이 가장 덜 틀린다(`KeywordCandidates`와 같은 까닭).
//

import Foundation

enum MetadataAudit {

    /// 키워드 필드 하나를 읽은 결과.
    struct KeywordField {
        let length: Int
        /// 쉼표 옆 공백으로 버린 글자 수.
        let wastedSpaces: Int
        /// 두 번 이상 적은 단어.
        let duplicates: [String]
        /// 이름 · 부제에 이미 있는 단어 — 빼도 똑같이 잡힌다.
        let alreadyIndexed: [String]
        /// 위 셋을 걷어낸 필드.
        let cleaned: String

        var unused: Int { max(0, StoreMetadata.Limit.keywords - length) }
        /// 정리하면 새로 생기는 글자 수.
        var reclaimable: Int { max(0, length - cleaned.count) }
        var isClean: Bool { wastedSpaces == 0 && duplicates.isEmpty && alreadyIndexed.isEmpty }
    }

    static func keywordField(_ text: StoreMetadata.LocaleText) -> KeywordField {
        let raw = text.keywords
        let terms = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let wasted = raw.split(separator: ",", omittingEmptySubsequences: false)
            .reduce(0) { total, piece in
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                return total + (piece.count - trimmed.count)
            }

        let indexed = text.name + " " + text.subtitle
        var seen: Set<String> = []
        var duplicates: [String] = []
        var alreadyIndexed: [String] = []
        var kept: [String] = []
        for term in terms {
            let key = normalize(term)
            if seen.contains(key) { duplicates.append(term); continue }
            seen.insert(key)
            if !key.isEmpty, contains(indexed, term) { alreadyIndexed.append(term); continue }
            kept.append(term)
        }
        return KeywordField(length: raw.count, wastedSpaces: wasted, duplicates: duplicates,
                            alreadyIndexed: alreadyIndexed, cleaned: kept.joined(separator: ","))
    }

    // MARK: - 추적 키워드가 어디에 있나

    enum Field: String {
        case name = "이름"
        case subtitle = "부제"
        case keywords = "키워드"
    }

    /// 추적 중인 키워드 하나가 메타데이터에 들어 있는 모양.
    struct Coverage {
        let term: String
        /// 단어마다 들어 있는 필드. 비어 있으면 그 단어는 어디에도 없다.
        let words: [(word: String, fields: [Field])]

        var isCovered: Bool { !words.isEmpty && words.allSatisfy { !$0.fields.isEmpty } }
        var isPartial: Bool { !isCovered && words.contains { !$0.fields.isEmpty } }
        var missingWords: [String] { words.filter { $0.fields.isEmpty }.map(\.word) }
        var fields: [Field] {
            var result: [Field] = []
            for field in words.flatMap(\.fields) where !result.contains(field) { result.append(field) }
            return result
        }
    }

    /// 검색어 하나를 단어로 쪼개 필드마다 찾아본다. 여러 단어 검색어는 단어들이 서로 다른
    /// 필드에 흩어져 있어도 잡힌다 — 스토어가 세 필드를 한데 모아 색인하기 때문이다.
    static func coverage(of term: String, in text: StoreMetadata.LocaleText) -> Coverage {
        let fields: [(Field, String)] = [
            (.name, text.name),
            (.subtitle, text.subtitle),
            (.keywords, text.keywords.replacingOccurrences(of: ",", with: " "))
        ]
        let words = term.split(whereSeparator: \.isWhitespace).map(String.init)
        return Coverage(term: term, words: words.map { word in
            (word, fields.filter { contains($0.1, word) }.map(\.0))
        })
    }

    /// `text`에 `term`이 들어 있는가.
    ///
    /// 라틴 문자는 **단어 단위**로 본다 — 부분 문자열로 보면 "app"이 "happy"에서 잡힌다.
    /// 한국어 · 한자 · 가나는 띄어쓰기 없이 붙는 복합어라 부분 문자열로 본다
    /// ("키보드"는 "클립키보드" 안에 있다).
    static func contains(_ text: String, _ term: String) -> Bool {
        let isLatin = term.unicodeScalars.allSatisfy { $0.isASCII }
        guard isLatin else {
            let key = normalize(term)
            return !key.isEmpty && normalize(text).contains(key)
        }
        let words = Set(latinWords(text))
        let needed = latinWords(term)
        return !needed.isEmpty && needed.allSatisfy(words.contains)
    }

    private static func latinWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// 공백 · 문장부호를 빼고 소문자로. "Clip Keyboard"와 "clipkeyboard"는 같은 단어다.
    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.map(Character.init))
    }

    // MARK: - 국가 → 로케일

    /// 이 국가의 검색이 읽는 로케일 — 앱에 있는 것 중에서 고른다. 없으면 영어(미국).
    ///
    /// 나라에 따라 스토어가 로케일을 둘 이상 읽기도 한다(미국은 영어와 스페인어(멕시코) 등).
    /// 여기서는 그 나라의 첫 로케일만 쓴다.
    static func locale(forStorefront country: String, available: [String]) -> String? {
        let preferred: [String]
        switch country.lowercased() {
        case "kr": preferred = ["ko"]
        case "us": preferred = ["en-US"]
        case "gb": preferred = ["en-GB", "en-US"]
        case "au": preferred = ["en-AU", "en-US"]
        case "ca": preferred = ["en-CA", "en-US"]
        case "jp": preferred = ["ja"]
        case "cn": preferred = ["zh-Hans"]
        case "tw", "hk": preferred = ["zh-Hant"]
        case "de": preferred = ["de-DE"]
        case "fr": preferred = ["fr-FR"]
        case "es": preferred = ["es-ES"]
        case "mx": preferred = ["es-MX"]
        case "br": preferred = ["pt-BR"]
        case "ru": preferred = ["ru"]
        case "it": preferred = ["it"]
        case "vn": preferred = ["vi"]
        case "th": preferred = ["th"]
        default: preferred = []
        }
        return (preferred + ["en-US"]).first(where: available.contains)
    }
}

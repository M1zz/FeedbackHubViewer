//
//  KeywordCandidates.swift
//  FeedbackHubViewer
//
//  Which search terms are worth trying, read out of the names of the apps that
//  already stand where yours does.
//
//  Pure string work, kept apart from the network (`AppStoreSearch`) so it can
//  be reasoned about — and argued with — on its own.
//

import Foundation

/// Mining candidate search terms out of app names.
///
/// Pure string work, kept apart from the network so it can be reasoned about
/// (and argued with) on its own.
enum KeywordCandidates {

    /// Terms worth trying, taken from the names of the apps that stand in the
    /// same part of the store as yours.
    ///
    /// There is no morphological analysis here. Korean app names are compounds
    /// — "복붙키보드", "문자복사 관리자", "자동 붙여넣기 키보드" — so a tokeniser
    /// that split on spaces would never find "키보드" inside the first of them.
    /// What works instead is agreement: every substring of two to six
    /// characters is counted across the neighbours' names, and the ones that
    /// turn up in several *different* apps are the words the category actually
    /// uses. A fragment only one app uses is that app's branding, not a search
    /// term, which is what `minimum` filters out.
    ///
    /// Overlapping segments collapse into the longest one that covers nearly
    /// the same apps: "키보" and "키보드" each appear in eleven names, and only
    /// one of them is a word.
    ///
    /// None of this decides anything by itself. Every candidate is then put to
    /// the store as a real search, and only the ones the app actually ranks for
    /// are kept — see `KeywordStore.discover(for:)`. That is what keeps this
    /// heuristic honest: it only has to be a good net, not a good judge.
    ///
    /// It does land fragments. "붙여넣기" is written with a space by some apps
    /// and without by others, so "붙여" and "넣기" each turn up in three names
    /// while the whole word turns up in one — and the absorption rule below
    /// cannot reach past a form that never appears. Both fragments then rank,
    /// because the store matches on substrings, and both get kept. Several
    /// rules were tried on real neighbours and none separated "붙여" from
    /// "복사", which is a genuine two-character word: the distinction is not in
    /// the names. Rather than tune a Korean tokeniser against one sample, the
    /// odd row is left for the reader to drop (우클릭 → 추적 중단). A term the
    /// store really does rank you for is never nonsense, only sometimes ugly.
    static func mined(from names: [String], appearingIn minimum: Int = 3,
                      excluding taken: Set<String> = [], limit: Int = 12) -> [String] {
        var owners: [String: Set<String>] = [:]

        for name in names {
            for run in hangulRuns(in: name) {
                let characters = Array(run)
                for length in 2...6 where characters.count >= length {
                    for start in 0...(characters.count - length) {
                        owners[String(characters[start..<(start + length)]), default: []].insert(name)
                    }
                }
            }
            for word in latinWords(in: name) {
                owners[word, default: []].insert(name)
            }
        }

        let shared = owners.filter { $0.value.count >= minimum }
        var kept: [(term: String, apps: Int)] = []
        for (term, apps) in shared {
            // Absorbed by a longer segment that covers nearly the same apps.
            let absorbed = shared.contains { longer, longerApps in
                longer.count > term.count && longer.contains(term)
                    && Double(longerApps.count) >= Double(apps.count) * 0.8
            }
            guard !absorbed, !taken.contains(TrackedKeyword.normalize(term)) else { continue }
            kept.append((term, apps.count))
        }

        kept.sort { $0.apps == $1.apps ? $0.term.count > $1.term.count : $0.apps > $1.apps }
        return kept.prefix(limit).map(\.term)
    }

    /// Runs of Hangul syllables, which is where compounds hide.
    private static func hangulRuns(in name: String) -> [String] {
        name.split(whereSeparator: { !("\u{AC00}"..."\u{D7A3}").contains($0) }).map(String.init)
    }

    /// Latin words long enough to be a search rather than an initialism.
    private static func latinWords(in name: String) -> [String] {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter || !$0.isASCII })
            .filter { $0.count >= 4 }
            .map(String.init)
    }
}

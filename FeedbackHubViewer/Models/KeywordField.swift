//
//  KeywordField.swift
//  FeedbackHubViewer
//
//  스토어 키워드 칸의 기록 — 언제 무엇이 걸려 있었나 — 과, 그걸 다시 짤 때가 됐는지.
//
//  키워드 칸은 앱 레포의 `APPSTORE.md` 가 원본이고 DeployBar 배포가 스토어에 올린다. 이 앱은
//  올라간 칸을 하루 한 번 App Store Connect 에서 읽어(`KeywordStore.syncStoreFields`)
//
//    1. 칸의 말을 저절로 추적하고 — 사람이 하나씩 넣지 않아도 순위가 쌓이게,
//    2. 칸이 바뀐 날을 적는다 — 그래야 "바꾸고 나서 순위가 올랐나" 를 견줄 수 있다.
//
//  바뀐 날은 이 앱이 처음 알아챈 날이다. 출시와 하루쯤 어긋날 수 있지만 키워드가 자리 잡는 데
//  두 주가 걸리니 그 정도면 충분하다.
//
//  다시 짜는 일은 이 앱이 하지 않는다. 순위 근거와 절차를 담은 지시문을 복사해 앱 레포를 연
//  Claude 에게 넘기고(`KeywordRefreshPrompt`), Claude 가 `APPSTORE.md` 를 고쳐 커밋하면 다음
//  배포가 올린다.
//

import Foundation

/// 한 번 본 키워드 칸.
struct KeywordFieldSnapshot: Codable, Hashable {
    /// 이 값을 처음 본 때.
    let seenAt: Date
    let terms: [String]
    /// 기록을 시작할 때 이미 걸려 있던 값 — 언제 걸었는지는 모른다.
    var isBaseline = false
}

enum KeywordField {

    /// 키워드를 바꾸고 순위가 자리 잡을 때까지. 그 전에 다시 짜면 바꾼 효과를 못 본 채 또 바꾼다.
    static let settleDays = 14

    /// 기록 하나에 남겨 둘 값의 수 — 두 주마다 바꿔도 일 년 치가 넘는다.
    static let keepSnapshots = 30

    static func key(project: String, locale: String) -> String { "\(project)|\(locale)" }

    /// 쉼표로 나뉜 칸 → 말들. 스토어는 쉼표 뒤 공백도 받으니 걷어 낸다.
    static func terms(in field: String) -> [String] {
        field.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 스토어 로케일 → 순위를 볼 가게. 키워드 칸은 로케일마다, 순위는 나라마다라 잇는다.
    /// 한 나라에 로케일이 여럿이면(캐나다의 영어 · 프랑스어) 그 나라 사람이 주로 보는 쪽 하나만.
    static func storefront(for locale: String) -> String? {
        storefronts[locale]
    }

    private static let storefronts: [String: String] = [
        "ko": "kr", "en-US": "us", "en-GB": "gb", "en-AU": "au", "en-CA": "ca",
        "ja": "jp", "zh-Hans": "cn", "zh-Hant": "tw", "de-DE": "de", "fr-FR": "fr",
        "es-ES": "es", "es-MX": "mx", "it": "it", "pt-BR": "br", "pt-PT": "pt",
        "nl-NL": "nl", "ru": "ru", "sv": "se", "da": "dk", "fi": "fi", "no": "no",
        "pl": "pl", "cs": "cz", "el": "gr", "tr": "tr", "th": "th", "vi": "vn",
        "id": "id", "ms": "my", "hu": "hu", "ro": "ro", "sk": "sk", "hr": "hr",
        "uk": "ua", "he": "il", "ar-SA": "sa", "hi": "in",
    ]
}

/// 한 앱 · 한 로케일의 키워드 칸이 지금 어디쯤인가.
struct KeywordRefreshState: Identifiable {
    let project: String
    let locale: String
    let country: String
    let current: KeywordFieldSnapshot
    /// 칸에 걸린 말마다 지금 순위와 바꿀 때 순위.
    let terms: [Term]
    let now: Date

    struct Term: Hashable {
        let term: String
        /// 마지막 확인의 순위. nil 이면 200위 안에 없거나 아직 확인 전.
        let rank: Int?
        /// 칸이 바뀐 날(또는 그 전) 마지막 확인의 순위. 그날 기록이 없으면 nil.
        let before: Int?
        /// 바뀐 날 전에 확인한 기록이 있었나 — `before == nil` 이 "안 잡힘" 인지 "모름" 인지 가른다.
        let checkedBefore: Bool
        let best: Int?
    }

    var id: String { KeywordField.key(project: project, locale: locale) }

    /// 바뀐 날. 기록을 시작하기 전부터 있던 값이면 nil — 그땐 처음 본 날부터 센다.
    var changedAt: Date? { current.isBaseline ? nil : current.seenAt }
    var days: Int { max(0, Calendar.current.dateComponents([.day], from: current.seenAt, to: now).day ?? 0) }
    var isSettled: Bool { days >= KeywordField.settleDays }

    var ranked: Int { terms.filter { $0.rank != nil }.count }
    var topTen: Int { terms.filter { ($0.rank ?? .max) <= 10 }.count }
    /// 바뀐 날보다 오른 말 · 내린 말 · 새로 잡힌 말.
    var rose: Int { terms.filter { t in t.rank.map { r in t.before.map { r < $0 } ?? t.checkedBefore } ?? false }.count }
    var fell: Int { terms.filter { t in t.before.map { b in t.rank.map { $0 > b } ?? true } ?? false }.count }
}

/// Claude 에게 넘길 지시문. 받는 쪽이 이 화면을 못 봐도 무엇을 근거로 무엇을 할지 알게,
/// 순위와 절차를 한 덩어리로 담는다.
enum KeywordRefreshPrompt {

    struct App {
        let name: String
        let project: String
        let trackId: Int?
        let isMac: Bool
        let states: [KeywordRefreshState]
        let competitors: [CompetitorStanding]
    }

    static func make(_ apps: [App]) -> String {
        var lines: [String] = []
        if apps.count == 1, let app = apps.first {
            lines.append("\(app.name) (\(app.project)) 의 App Store 키워드 칸을 다시 짜 줘.")
        } else {
            lines.append("앱 \(apps.count)개의 App Store 키워드 칸을 다시 짜 줘: " + apps.map(\.name).joined(separator: ", "))
        }
        lines.append("")
        for app in apps { lines += section(app, heading: apps.count > 1) }
        lines += procedure
        return lines.joined(separator: "\n")
    }

    private static func section(_ app: App, heading: Bool) -> [String] {
        var lines: [String] = []
        let id = app.trackId.map { " · App Store id \($0)" } ?? ""
        lines.append((heading ? "## " : "## 앱 · ") + "\(app.name) (\(app.project)\(id)\(app.isMac ? " · 맥 앱" : ""))")
        for state in app.states {
            let when = state.changedAt.map { "\(day($0))에 바뀜, \(state.days)일째" }
                ?? "\(day(state.current.seenAt))부터 기록, 그 전에 언제 걸었는지는 모름"
            let length = state.current.terms.joined(separator: ",").count
            lines.append("")
            lines.append("### \(state.locale) 칸 → \(state.country) 스토어 순위 (\(when) · \(length)/100자)")
            lines.append("200위 안 \(state.ranked)/\(state.terms.count)개 · 10위 안 \(state.topTen)개"
                         + (state.changedAt == nil ? "" : " · 바꾼 뒤 오름 \(state.rose) · 내림 \(state.fell)"))
            for term in state.terms {
                var parts = [term.rank.map { "지금 \($0)위" } ?? "지금 200위 밖"]
                if state.changedAt != nil {
                    if let before = term.before { parts.append("바꿀 때 \(before)위") }
                    else if term.checkedBefore { parts.append("바꿀 때 200위 밖") }
                    else { parts.append("바꿀 때 기록 없음(새로 넣은 말)") }
                }
                if let best = term.best { parts.append("최고 \(best)위") }
                lines.append("- \(term.term) — " + parts.joined(separator: ", "))
            }
        }
        let rivals = app.competitors.prefix(6)
        if !rivals.isEmpty {
            lines.append("")
            lines.append("### 내 위에 자주 서는 앱")
            for rival in rivals {
                lines.append("- \(rival.app.name) — 키워드 \(rival.keywords)개 중 \(rival.timesAbove)개에서 내 위, 최고 \(rival.bestRank)위")
            }
        }
        lines.append("")
        return lines
    }

    private static let procedure: [String] = [
        "## 할 일",
        "1. 앱 레포를 찾는다 — ~/Documents/workspace/Auto 아래에서 번들 id 로. 레포의 `APPSTORE.md` 가 원본이고, 각 언어 절의 `### 키워드` 줄만 고친다. 같은 절의 이름 · 부제를 먼저 읽는다 (그 단어는 키워드에 다시 넣지 않는다).",
        "2. 위 순위로 남길 말과 뺄 말을 가른다. 10위 안이거나 30위 안이면서 실제로 검색되는 말은 남긴다. 50위 밖이면서 경쟁이 센 말(상위 10개 앱 평점 수 중간값이 큰 말), 아무도 검색하지 않는 말은 뺀다. 바꾼 지 두 주가 안 된 말은 아직 판단하지 않는다.",
        "3. 교체 후보를 앱의 쓰임새에 맞게 고르고, 하나씩 실제로 검증한다.",
        "   - 순위 · 경쟁: `https://itunes.apple.com/search?term=…&country=…&entity=software&limit=200` (맥 앱은 `entity=macSoftware`). 요청 사이 3초 — 그보다 잦으면 403 으로 막힌다.",
        "   - 검색량: App Store 자동완성 `https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=…` 에 헤더 `X-Apple-Store-Front: 143466,29`(한국) / `143441,29`(미국), 1초 간격. 앞 글자 몇 개만 쳐도 뜨는 말일수록 많이 찾는다.",
        "   - 경쟁이 약하고(상위 앱 평점 수가 적고) 실제로 검색되는 말을 먼저 넣는다.",
        "4. 100자를 채운다. 쉼표 뒤 공백 없이. 이름 · 부제에 있는 단어, 남의 상표(브랜드 · 다른 앱 이름)는 넣지 않는다.",
        "5. `APPSTORE.md` 의 키워드 줄만 고치고 그 파일만 커밋 · 푸시한다. 스토어 반영은 DeployBar 배포가 한다 — App Store Connect 를 직접 고치지 않는다.",
        "6. 남긴 말 · 뺀 말 · 새로 넣은 말을 순위 근거와 함께 짧게 보고한다.",
    ]

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}

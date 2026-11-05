//
//  KeywordStore+StoreField.swift
//  FeedbackHubViewer
//
//  스토어에 걸린 키워드 칸을 이 가게로 들인다 — 저절로 추적하고, 바뀐 날을 적는다
//  (`KeywordField.swift`).
//
//  App Store Connect 에서 읽는 것은 지금 스토어에 **나가 있는** 버전(`StoreMetadata.live`)이다.
//  검색이 지금 읽는 것이 그것이고, 심사 중인 다음 버전의 칸은 아직 순위에 아무 일도 하지 않는다.
//
//  추적은 순위를 보는 나라(`countries`)의 로케일만 한다. 칸 하나가 스무 말 남짓이고 한 말이
//  하루 한 번 3초짜리 검색이라, 나라를 다 들이면 하루 확인이 몇 시간이 된다. 칸에서 빠진 말은
//  추적에서 빼지 않는다 — 뺀 뒤의 순위도 근거다. 지우고 싶으면 화면에서 지운다.
//

import Foundation

extension KeywordStore {

    private static let fieldSyncDayKey = "keywordFieldSyncDay"
    /// 하루 확인이 도는 중인가 — 링크가 바뀔 때마다 불려서, 겹쳐 돌면 같은 앱을 두 번 읽는다.
    private static var isSyncingFields = false

    /// 하루 한 번, 스토어에 걸린 키워드 칸을 모든 앱에 대해 읽어 들인다. App Store Connect
    /// 키가 없으면 아무것도 하지 않는다.
    func syncStoreFieldsIfDue(connect: AppStoreConnectStore, projects: [String], now: Date = Date()) async {
        let today = UsageRollups.dayKey(now)
        guard connect.isConfigured, !Self.isSyncingFields,
              UserDefaults.standard.string(forKey: Self.fieldSyncDayKey) != today,
              projects.contains(where: { trackId(for: $0) != nil }) else { return }
        Self.isSyncingFields = true
        defer { Self.isSyncingFields = false }
        var added: [TrackedKeyword] = []
        var read = 0
        for project in projects where trackId(for: project) != nil {
            await connect.loadMetadata(bundleID: project, force: true)
            guard let metadata = connect.metadata[project]?.value else { continue }
            added += absorb(metadata, for: project, now: now)
            read += 1
        }
        // 한 곳도 못 읽었으면(키가 막혔거나 네트워크) 오늘을 쓴 것으로 치지 않는다.
        guard read > 0 else { return }
        UserDefaults.standard.set(today, forKey: Self.fieldSyncDayKey)
        // 새로 들인 말은 내일까지 빈칸으로 두지 않는다. 요청은 `ITunesGate` 가 줄 세운다.
        for keyword in added { checkNow(keyword) }
    }

    /// 한 앱의 메타데이터를 들인다. 화면이 메타데이터를 읽었을 때도 부른다 — 이미 본 값이면
    /// 아무것도 바뀌지 않는다. 새로 추적하게 된 말을 돌려준다.
    @discardableResult
    func absorb(_ metadata: StoreMetadata, for project: String, now: Date = Date()) -> [TrackedKeyword] {
        var added: [TrackedKeyword] = []
        var logChanged = false
        for (locale, text) in metadata.live.locales {
            let terms = KeywordField.terms(in: text.keywords)
            guard !terms.isEmpty else { continue }
            let key = KeywordField.key(project: project, locale: locale)
            var log = fieldLog[key] ?? []
            if log.last.map({ Self.sameField($0.terms, terms) }) != true {
                log.append(KeywordFieldSnapshot(seenAt: now, terms: terms, isBaseline: log.isEmpty))
                fieldLog[key] = Array(log.suffix(KeywordField.keepSnapshots))
                logChanged = true
            }
            guard let country = KeywordField.storefront(for: locale), countries.contains(country) else { continue }
            for term in terms where !isTracked(term, country: country, for: project) {
                add(term: term, countries: [country], for: project)
                added.append(TrackedKeyword(term: term, country: country))
            }
        }
        if logChanged { CacheFile.write(fieldLog, to: CacheFile.url(Self.fieldLogFile)) }
        return added
    }

    /// 순서 · 대소문자만 다른 칸은 같은 칸이다 — 스토어가 다시 줄 때 순서를 바꾸기도 한다.
    private static func sameField(_ lhs: [String], _ rhs: [String]) -> Bool {
        Set(lhs.map(TrackedKeyword.normalize)) == Set(rhs.map(TrackedKeyword.normalize))
    }

    // MARK: - 읽기

    /// 한 앱의 칸들 — 순위를 보는 나라의 것만, 고른 나라 차례로.
    func refreshStates(for project: String, now: Date = Date()) -> [KeywordRefreshState] {
        let trackId = trackId(for: project)
        return fieldLog.compactMap { key, log -> KeywordRefreshState? in
            guard key.hasPrefix(project + "|"), let current = log.last else { return nil }
            let locale = String(key.dropFirst(project.count + 1))
            guard let country = KeywordField.storefront(for: locale), countries.contains(country) else { return nil }
            let changeDay = current.isBaseline ? nil : UsageRollups.dayKey(current.seenAt)
            let terms = current.terms.map { term -> KeywordRefreshState.Term in
                let keyword = TrackedKeyword(term: term, country: country)
                let standing = history.standing(keyword, trackId: trackId)
                // 바뀐 날 그날까지의 마지막 확인. 바뀐 날 확인이 그날 바뀐 칸을 이미 반영했을 수도 있지만,
                // 순위는 며칠에 걸쳐 움직이니 그날 것을 "바꿀 때" 로 본다.
                let before = changeDay.flatMap { day in
                    (history.checks[keyword.id] ?? [:]).filter { $0.key <= day }.max { $0.key < $1.key }?.value
                }
                return .init(term: term, rank: standing.rank,
                             before: before.flatMap { check in trackId.flatMap { check.rank(of: $0) } },
                             checkedBefore: before != nil, best: standing.best)
            }
            return KeywordRefreshState(project: project, locale: locale, country: country,
                                       current: current, terms: terms, now: now)
        }
        .sorted { (countries.firstIndex(of: $0.country) ?? .max, $0.locale) < (countries.firstIndex(of: $1.country) ?? .max, $1.locale) }
    }

    /// 다시 짤 때가 된 앱 — 순위를 보는 칸이 하나라도 두 주를 넘겼다. 오래된 것부터.
    func refreshDue(projects: [String], now: Date = Date()) -> [(project: String, days: Int)] {
        projects.compactMap { project in
            let settled = refreshStates(for: project, now: now).filter(\.isSettled)
            return settled.map(\.days).max().map { (project, $0) }
        }
        .sorted { $0.days > $1.days }
    }
}

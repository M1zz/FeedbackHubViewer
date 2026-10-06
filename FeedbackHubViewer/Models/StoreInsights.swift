//
//  StoreInsights.swift
//  FeedbackHubViewer
//
//  분석 리포트의 원본 행에서 "그래서 무엇이 문제인가" 를 읽는다 — 순수 함수만 있다.
//
//  `StoreAnalytics` 가 창 전체를 합친 숫자라면, 이쪽은 기간을 나누고 칸끼리 견준다.
//  2026-10 에 클립키보드 숫자를 손으로 읽으며 찾은 것들을 규칙으로 옮겼다.
//
//  ── 행사와 평상시를 가른다 ──
//
//  한 주의 무료 행사가 한 달 치 첫 다운로드의 93% 를 차지하면, 창 전체를 합친 숫자는
//  평소의 앱을 말하지 못한다. 그래서 첫 다운로드가 튄 날들을 "몰린 기간" 으로 떼고,
//  나머지(평상시)로 순증 · 전환 · 세션을 다시 잰다. 판정은 평상시 숫자로 한다.
//
//  ── 말하지 않는 것 ──
//
//  표본이 작으면(칸마다 적어 둔 최소치 아래) 그 규칙은 아무 말도 하지 않는다. 6일 치
//  데이터로 "줄고 있다" 고 말하는 것보다 말이 없는 편이 낫다.
//

import Foundation

struct StoreInsights {

    enum Level: Int, Comparable {
        case bad, watch, good, info
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Finding: Identifiable, Hashable {
        let id: String
        let level: Level
        let title: String
        let detail: String
        /// 할 일 한 줄. 없으면 읽을거리.
        var action: String?
    }

    /// 한 기간의 숫자.
    struct Period: Hashable {
        let label: String
        let firstDay: String
        let lastDay: String
        let days: Int
        let firstDownloads: Double
        let newInstalls: Double
        let deletions: Double
        let impressions: Double
        let pageViews: Double
        let searchImpressions: Double
        let searchFirstDownloads: Double
        let sessions: Double
        let sessionDays: Int
        let sessionDuration: Double

        var firstDownloadsPerDay: Double { days > 0 ? firstDownloads / Double(days) : 0 }
        var sessionsPerDay: Double? { sessionDays > 0 ? sessions / Double(sessionDays) : nil }
        var averageDuration: Double? { sessions > 0 ? sessionDuration / sessions : nil }
        var searchConversion: Double? { searchImpressions > 0 ? searchFirstDownloads / searchImpressions : nil }
        var range: String { firstDay == lastDay ? Self.short(firstDay) : "\(Self.short(firstDay))~\(Self.short(lastDay))" }

        /// "2026-08-30" → "8/30".
        static func short(_ day: String) -> String {
            let parts = day.split(separator: "-")
            guard parts.count == 3, let month = Int(parts[1]), let date = Int(parts[2]) else { return day }
            return "\(month)/\(date)"
        }
    }

    /// 첫 다운로드가 몰린 기간. 없으면 nil.
    let surge: Period?
    /// 몰린 기간을 뺀 나머지. 판정은 이것으로 한다.
    let baseline: Period?
    let findings: [Finding]

    var isEmpty: Bool { findings.isEmpty && surge == nil }
}

// MARK: - 읽기

extension StoreInsights {

    typealias Row = [String: String]

    /// 몰린 날의 기준 — 평소(중앙값)의 다섯 배이면서 하루 20건 이상.
    static let surgeMultiple = 5.0
    static let surgeMinimum = 20.0

    init(_ analytics: StoreAnalytics) {
        let raw = analytics.raw
        func rows(_ report: StoreAnalyticsReport) -> [String: [Row]] { raw[report]?.byDate ?? [:] }
        let downloads = rows(.downloads)
        let engagement = rows(.engagement)
        let installs = rows(.installsDeletions)
        let sessions = rows(.sessions)

        // 1. 몰린 날 — 다운로드 리포트와 설치 리포트는 시작일이 다르다(클립키보드는 설치가
        // 나흘 먼저 시작). 하나만 보면 행사 초반이 평상시로 섞여 "늘고 있다" 고 잘못 말한다.
        // 그래서 날마다 둘 중 큰 값을 새로 온 사람으로 본다.
        let fresh: Set<String> = ["First-time download", "Redownload"]
        let firstByDay = downloads.mapValues { Self.sum($0.filter { $0["Download Type"] == "First-time download" }, "Counts") }
        let installsByDay = installs.mapValues {
            Self.sum($0.filter { $0["Event"] == "Install" && fresh.contains($0["Download Type"] ?? "") }, "Counts")
        }
        let newcomersByDay = firstByDay.merging(installsByDay, uniquingKeysWith: max)
        let surgeDays = Self.surgeDays(newcomersByDay)
        let allDays = Set(downloads.keys).union(engagement.keys).union(installs.keys).union(sessions.keys).sorted()

        func period(_ label: String, _ include: (String) -> Bool) -> Period? {
            let days = allDays.filter(include)
            guard let first = days.first, let last = days.last else { return nil }
            let pick: ([String: [Row]]) -> [Row] = { source in days.flatMap { source[$0] ?? [] } }
            let dl = pick(downloads), eng = pick(engagement), ins = pick(installs), ses = pick(sessions)
            let firstTime = dl.filter { $0["Download Type"] == "First-time download" }
            let added = ins.filter { $0["Event"] == "Install" && fresh.contains($0["Download Type"] ?? "") }
            let deleted = ins.filter { $0["Event"] == "Delete" }
            let shown = eng.filter { $0["Event"] == "Impression" }
            let opened = eng.filter { $0["Event"] == "Page view" }
            let searched = shown.filter { $0["Source Type"] == "App Store search" }
            let searchFirst = firstTime.filter { $0["Source Type"] == "App Store search" }
            let downloadDays = days.filter { downloads[$0] != nil }.count
            let sessionDays = days.filter { sessions[$0] != nil }.count
            return Period(label: label, firstDay: first, lastDay: last,
                          days: downloadDays,
                          firstDownloads: Self.sum(firstTime, "Counts"),
                          newInstalls: Self.sum(added, "Counts"),
                          deletions: Self.sum(deleted, "Counts"),
                          impressions: Self.uniqueSum(shown),
                          pageViews: Self.uniqueSum(opened),
                          searchImpressions: Self.uniqueSum(searched),
                          searchFirstDownloads: Self.sum(searchFirst, "Counts"),
                          sessions: Self.sum(ses, "Sessions"),
                          sessionDays: sessionDays,
                          sessionDuration: Self.sum(ses, "Total Session Duration"))
        }

        var surgePeriod: Period?
        if let start = surgeDays.first, let end = surgeDays.last {
            surgePeriod = period("몰린 기간") { $0 >= start && $0 <= end }
        }
        let inBaseline: (String) -> Bool = { day in
            guard let surgePeriod else { return true }
            return day < surgePeriod.firstDay || day > surgePeriod.lastDay
        }
        let baselinePeriod = period(surgePeriod == nil ? "데이터가 있는 기간" : "평상시", inBaseline)
        surge = surgePeriod
        baseline = baselinePeriod

        // 2. 규칙
        var found: [Finding] = []
        let pickBaseline: ([String: [Row]]) -> [Row] = { source in
            source.filter { inBaseline($0.key) }.values.flatMap { $0 }
        }

        let totalFirst = firstByDay.values.reduce(0, +)
        if let surgePeriod, totalFirst > 0 {
            found.append(Self.surgeFinding(surgePeriod, baseline: baselinePeriod, total: totalFirst,
                                           purchases: rows(.purchases)))
        }
        if let baselinePeriod {
            if let finding = Self.netGrowth(baselinePeriod) { found.append(finding) }
            if let finding = Self.pageOpenRate(baselinePeriod) { found.append(finding) }
        }
        if let finding = Self.earlyDeletion(installs.values.flatMap { $0 }) { found.append(finding) }
        found += Self.newUserSources(downloads: pickBaseline(downloads), engagement: pickBaseline(engagement),
                                     period: baselinePeriod?.label ?? "")
        found += Self.territories(downloads: pickBaseline(downloads), engagement: pickBaseline(engagement),
                                  sessions: sessions.values.flatMap { $0 })
        if let finding = Self.durationByVersion(sessions.values.flatMap { $0 }) { found.append(finding) }
        if let finding = Self.money(analytics.purchases) { found.append(finding) }
        if let finding = Self.installFailures(analytics.installPerformance) { found.append(finding) }
        if let finding = Self.webPreview(rows(.webPreview).values.flatMap { $0 }) { found.append(finding) }
        if let finding = Self.optIn(analytics.optIn) { found.append(finding) }

        findings = found.enumerated()
            .sorted { $0.element.level != $1.element.level ? $0.element.level < $1.element.level : $0.offset < $1.offset }
            .map(\.element)
    }

    // MARK: 몰린 기간

    /// 첫 다운로드가 평소의 다섯 배 넘게 튄 날들. 사이에 낀 날도 같은 기간으로 본다.
    static func surgeDays(_ firstByDay: [String: Double]) -> [String] {
        let values = firstByDay.values.sorted()
        guard values.count >= 7 else { return [] }
        let median = values[values.count / 2]
        let threshold = max(surgeMinimum, surgeMultiple * max(median, 1))
        return firstByDay.filter { $0.value >= threshold }.keys.sorted()
    }

    static func surgeFinding(_ surge: Period, baseline: Period?, total: Double, purchases: [String: [Row]]) -> Finding {
        let share = surge.firstDownloads / total
        var detail = "\(surge.range) \(surge.days)일에 첫 다운로드 \(AnalyticsFormat.count(surge.firstDownloads))건 — 창 전체의 \(AnalyticsFormat.percent(share))가 이때 왔습니다."
        if let baseline {
            detail += " 평상시는 하루 \(AnalyticsFormat.decimal(baseline.firstDownloadsPerDay))건입니다."
            if let before = surge.sessionsPerDay, let after = baseline.sessionsPerDay, before > 0 {
                detail += " 하루 세션은 \(AnalyticsFormat.count(before)) → \(AnalyticsFormat.count(after))(\(AnalyticsFormat.percent(after / before)) 남음)."
            }
        }
        // 몰린 날에 0원 구매가 첫 다운로드의 절반을 넘으면 무료 행사다.
        let surgeRows = purchases.filter { $0.key >= surge.firstDay && $0.key <= surge.lastDay }.values.flatMap { $0 }
        let freePurchases = surgeRows.filter { (number($0["Proceeds in USD"]) ?? 0) == 0 }.reduce(0) { $0 + (number($1["Purchases"]) ?? 0) }
        var title = "\(surge.range)에 다운로드가 몰렸습니다"
        if freePurchases >= surge.firstDownloads * 0.5 {
            title = "\(surge.range) 무료 행사로 들어온 사람이 대부분입니다"
            detail += " 그 기간 0원 구매가 \(AnalyticsFormat.count(freePurchases))건 — 받은 날 바로 무료로 풀린 상품을 가져갔어요."
        }
        return Finding(id: "surge", level: .info, title: title, detail: detail,
                       action: "아래 판정은 이 기간을 뺀 평상시 숫자로 합니다.")
    }

    // MARK: 평상시

    static func netGrowth(_ period: Period) -> Finding? {
        guard period.days >= 10, period.deletions + period.newInstalls >= 20 else { return nil }
        let ratio = period.newInstalls > 0 ? period.deletions / period.newInstalls : .infinity
        let numbers = "\(period.label)(\(period.range)) \(period.days)일: 새로 설치 \(AnalyticsFormat.count(period.newInstalls)) · 삭제 \(AnalyticsFormat.count(period.deletions))."
        if ratio >= 1.2 {
            let times = ratio.isFinite ? String(format: "%.1f배", ratio) : "훨씬 많이"
            return Finding(id: "net", level: .bad, title: "사용자가 줄고 있습니다 — 지우는 사람이 새로 오는 사람의 \(times)",
                           detail: numbers, action: "새로 데려오는 것보다 지우는 이유를 먼저 막으세요.")
        }
        if ratio <= 0.8 {
            return Finding(id: "net", level: .good, title: "사용자가 늘고 있습니다", detail: numbers)
        }
        return Finding(id: "net", level: .watch, title: "들어오는 만큼 나갑니다", detail: numbers)
    }

    static func pageOpenRate(_ period: Period) -> Finding? {
        guard period.impressions >= 300 else { return nil }
        let rate = period.pageViews / period.impressions
        guard rate < 0.05 else { return nil }
        return Finding(id: "page-open", level: .watch,
                       title: "스토어에서 보이는데 페이지를 안 엽니다 (\(AnalyticsFormat.percent(rate)))",
                       detail: "\(period.label) 노출 \(AnalyticsFormat.count(period.impressions))대 중 페이지를 연 기기 \(AnalyticsFormat.count(period.pageViews))대. 검색 결과에서 보이는 것만으로 판단하고 지나갑니다.",
                       action: "아이콘 · 이름 · 부제 · 첫 스크린샷을 고치세요.")
    }

    // MARK: 삭제

    static func earlyDeletion(_ rows: [Row]) -> Finding? {
        let deletes = rows.filter { $0["Event"] == "Delete" }
        let total = sum(deletes, "Counts")
        guard total >= 10 else { return nil }
        let ages = StoreAnalytics.ageTally(deletes, value: "Counts")
        let early = ages.filter { $0.key == StoreAnalytics.ageBuckets[0] || $0.key == StoreAnalytics.ageBuckets[1] }
            .reduce(0) { $0 + $1.value }
        let sameDay = ages.first { $0.key == StoreAnalytics.ageBuckets[0] }?.value ?? 0
        let share = early / total
        guard share >= 0.4 else { return nil }
        var detail = "지운 \(AnalyticsFormat.count(total))대 중 받은 날 \(AnalyticsFormat.count(sameDay)) · 일주일 안 \(AnalyticsFormat.count(early - sameDay))."
        let versions = StoreAnalytics.tally(deletes, by: "App Version", value: "Counts")
        if versions.count >= 2 {
            let topTwo = versions.prefix(2)
            let topShare = topTwo.reduce(0) { $0 + $1.value } / total
            if topShare >= 0.4 {
                detail += " 지운 기기의 \(AnalyticsFormat.percent(topShare))가 \(topTwo.map(\.key).joined(separator: " · ")) 입니다."
            }
        }
        return Finding(id: "early-delete", level: share >= 0.6 ? .bad : .watch,
                       title: "지운 사람의 \(AnalyticsFormat.percent(share))가 받고 일주일 안에 지웠습니다",
                       detail: detail,
                       action: "첫 실행에서 쓸모를 못 찾고 떠납니다 — 첫 화면 · 권한 요청 · 처음 해야 하는 설정(키보드 켜기 같은)을 보세요.")
    }

    // MARK: 신규 유입

    static func newUserSources(downloads: [Row], engagement: [Row], period: String) -> [Finding] {
        let first = downloads.filter { $0["Download Type"] == "First-time download" }
        let total = sum(first, "Counts")
        guard total >= 10 else { return [] }
        let unique: (Row) -> Double = { number($0["Unique Counts"]) ?? number($0["Counts"]) ?? 0 }
        let bySource = StoreAnalytics.tally(first, by: "Source Type", value: "Counts")
        guard let top = bySource.first else { return [] }
        var findings: [Finding] = []
        var detail = "\(period) 첫 다운로드 \(AnalyticsFormat.count(total))건: "
            + bySource.prefix(4).map { "\(StoreAnalytics.word($0.key)) \(AnalyticsFormat.percent($0.value / total))" }.joined(separator: " · ") + "."
        let searchImpressions = engagement.filter { $0["Event"] == "Impression" && $0["Source Type"] == "App Store search" }.reduce(0) { $0 + unique($1) }
        let searchFirst = bySource.first { $0.key == "App Store search" }?.value ?? 0
        if searchImpressions > 0 {
            detail += " 검색 전환 \(AnalyticsFormat.percent(searchFirst / searchImpressions))(노출 \(AnalyticsFormat.count(searchImpressions)))."
        }
        findings.append(Finding(id: "sources", level: .info,
                                title: "새 사람은 주로 \(StoreAnalytics.word(top.key))으로 들어옵니다 (\(AnalyticsFormat.percent(top.value / total)))",
                                detail: detail,
                                action: top.key == "App Store search" ? "검색이 생명줄입니다 — 키워드 탭의 처방부터." : nil))

        // 둘러보기 노출은 많은데 첫 다운로드가 거의 없으면, 그 노출은 업데이트 목록이다.
        let browseImpressions = engagement.filter { $0["Event"] == "Impression" && $0["Source Type"] == "App Store browse" }.reduce(0) { $0 + unique($1) }
        let browseFirst = bySource.first { $0.key == "App Store browse" }?.value ?? 0
        if browseImpressions >= 1000, browseFirst / browseImpressions < 0.005 {
            findings.append(Finding(id: "browse", level: .info,
                                    title: "둘러보기 노출은 새 사람이 아닙니다",
                                    detail: "둘러보기 노출 \(AnalyticsFormat.count(browseImpressions))대에서 첫 다운로드 \(AnalyticsFormat.count(browseFirst))건. 대부분 이미 가진 사람이 업데이트 목록에서 본 것이라, 노출 합계로 성장을 읽으면 안 됩니다."))
        }
        return findings
    }

    // MARK: 나라

    static func territories(downloads: [Row], engagement: [Row], sessions: [Row]) -> [Finding] {
        let unique: (Row) -> Double = { number($0["Unique Counts"]) ?? number($0["Counts"]) ?? 0 }
        let first = downloads.filter { $0["Download Type"] == "First-time download" }
        var impressions: [String: Double] = [:], searchFirst: [String: Double] = [:]
        for row in engagement where row["Event"] == "Impression" && row["Source Type"] == "App Store search" {
            impressions[row["Territory"] ?? "", default: 0] += unique(row)
        }
        for row in first where row["Source Type"] == "App Store search" {
            searchFirst[row["Territory"] ?? "", default: 0] += number(row["Counts"]) ?? 0
        }
        let totalImpressions = impressions.values.reduce(0, +)
        let totalFirst = searchFirst.values.reduce(0, +)
        guard totalImpressions >= 300 else { return [] }
        let overall = totalFirst / totalImpressions
        var findings: [Finding] = []

        // 보이는데 아무도 안 받는 나라.
        let dead = impressions.filter { $0.value >= 150 && (searchFirst[$0.key] ?? 0) == 0 }.sorted { $0.value > $1.value }
        if !dead.isEmpty {
            let names = dead.prefix(3).map { "\(StoreAnalytics.word($0.key)) \(AnalyticsFormat.count($0.value))" }.joined(separator: " · ")
            findings.append(Finding(id: "dead-territory", level: .bad,
                                    title: "검색에 보이는데 아무도 안 받는 나라: \(dead.prefix(3).map { StoreAnalytics.word($0.key) }.joined(separator: " · "))",
                                    detail: "검색 노출 \(names), 첫 다운로드 0건.",
                                    action: "그 나라 말로 된 부제 · 키워드 · 스크린샷이 검색어와 맞는지 보세요."))
        }
        // 노출이 큰데 전환이 평균의 절반이 안 되는 나라.
        let weak = impressions.filter { territory, count in
            count >= 300 && (searchFirst[territory] ?? 0) > 0 && overall > 0 && (searchFirst[territory] ?? 0) / count < overall * 0.5
        }.sorted { $0.value > $1.value }
        if let worst = weak.first {
            let conversion = (searchFirst[worst.key] ?? 0) / worst.value
            findings.append(Finding(id: "weak-territory", level: .watch,
                                    title: "\(StoreAnalytics.word(worst.key)) 검색 전환이 평균의 절반 아래입니다",
                                    detail: "검색 노출 \(AnalyticsFormat.count(worst.value)) · 전환 \(AnalyticsFormat.percent(conversion)) (전체 \(AnalyticsFormat.percent(overall))).",
                                    action: "그 나라 스토어 페이지의 첫 스크린샷과 부제를 보세요."))
        }
        // 가장 잘 받는 나라.
        if let best = impressions.filter({ $0.value >= 100 && (searchFirst[$0.key] ?? 0) >= 3 })
            .max(by: { (searchFirst[$0.key] ?? 0) / $0.value < (searchFirst[$1.key] ?? 0) / $1.value }),
           overall > 0, (searchFirst[best.key] ?? 0) / best.value >= overall * 1.3 {
            let conversion = (searchFirst[best.key] ?? 0) / best.value
            findings.append(Finding(id: "best-territory", level: .good,
                                    title: "\(StoreAnalytics.word(best.key))에서 가장 잘 받습니다 (검색 전환 \(AnalyticsFormat.percent(conversion)))",
                                    detail: "검색 노출 \(AnalyticsFormat.count(best.value)) · 첫 다운로드 \(AnalyticsFormat.count(searchFirst[best.key] ?? 0)). 전체 평균 \(AnalyticsFormat.percent(overall))."))
        }
        // 받는 몫보다 쓰는 몫이 훨씬 큰 나라 — 받으면 오래 쓴다.
        let sessionTotal = sum(sessions, "Sessions")
        let firstTotal = sum(first, "Counts")
        if sessionTotal >= 200, firstTotal >= 10 {
            let sessionShare = StoreAnalytics.tally(sessions, by: "Territory", value: "Sessions")
            let firstShare = Dictionary(StoreAnalytics.tally(first, by: "Territory", value: "Counts").map { ($0.key, $0.value / firstTotal) },
                                        uniquingKeysWith: { a, _ in a })
            if let loyal = sessionShare.first(where: { share in
                let used = share.value / sessionTotal
                return used >= 0.1 && used >= 2 * (firstShare[share.key] ?? 0)
            }) {
                let used = loyal.value / sessionTotal
                findings.append(Finding(id: "loyal-territory", level: .good,
                                        title: "\(StoreAnalytics.word(loyal.key)) 사람은 받으면 오래 씁니다",
                                        detail: "세션의 \(AnalyticsFormat.percent(used))가 \(StoreAnalytics.word(loyal.key)) — 첫 다운로드 몫(\(AnalyticsFormat.percent(firstShare[loyal.key] ?? 0)))의 몇 배입니다.",
                                        action: "그 나라 말 현지화 · 키워드에 쓰는 품이 남는 장사입니다."))
            }
        }
        return findings
    }

    // MARK: 버전

    static func durationByVersion(_ rows: [Row]) -> Finding? {
        var totals: [String: (sessions: Double, duration: Double)] = [:]
        for row in rows {
            guard let version = row["App Version"], !version.isEmpty else { continue }
            totals[version, default: (0, 0)].sessions += number(row["Sessions"]) ?? 0
            totals[version, default: (0, 0)].duration += number(row["Total Session Duration"]) ?? 0
        }
        let versions = totals.filter { $0.value.sessions >= 30 }.keys.sorted(by: versionLess)
        guard versions.count >= 4 else { return nil }
        let newer = Array(versions.suffix(versions.count / 2)), older = Array(versions.prefix(versions.count - newer.count))
        func average(_ list: [String]) -> Double {
            let sessions = list.reduce(0) { $0 + totals[$1]!.sessions }
            return sessions > 0 ? list.reduce(0) { $0 + totals[$1]!.duration } / sessions : 0
        }
        let before = average(older), after = average(newer)
        guard before > 0, abs(after - before) / before >= 0.3 else { return nil }
        let shorter = after < before
        return Finding(id: "duration-version", level: .watch,
                       title: "새 버전에서 세션이 \(shorter ? "짧아졌습니다" : "길어졌습니다") (\(AnalyticsFormat.seconds(before)) → \(AnalyticsFormat.seconds(after)))",
                       detail: "\(older.first ?? "")~\(older.last ?? "") 평균 \(AnalyticsFormat.seconds(before)), \(newer.first ?? "")~\(newer.last ?? "") 평균 \(AnalyticsFormat.seconds(after)).",
                       action: shorter ? "할 일이 빨라진 것인지 쓰다 마는 것인지는 통계 탭의 핵심 행동률과 같이 보세요." : nil)
    }

    /// "5.1.10" 이 "5.1.9" 뒤에 오게.
    static func versionLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }

    // MARK: 돈 · 설치 · 웹 · 동의

    static func money(_ purchases: StoreAnalytics.Purchases?) -> Finding? {
        guard let purchases, purchases.purchases >= 5 else { return nil }
        let free = purchases.purchases - purchases.payingUsers
        if purchases.payingUsers == 0 {
            return Finding(id: "money", level: .watch, title: "돈을 낸 구매가 없습니다",
                           detail: "구매 \(AnalyticsFormat.count(purchases.purchases))건이 모두 0원입니다.")
        }
        return Finding(id: "money", level: purchases.payingUsers < 3 ? .watch : .info,
                       title: "돈을 낸 사람 \(AnalyticsFormat.count(purchases.payingUsers))명 · 수익 \(AnalyticsFormat.usd(purchases.proceeds))",
                       detail: "구매 \(AnalyticsFormat.count(purchases.purchases))건 중 \(AnalyticsFormat.count(free))건은 0원(무료 상품 · 오퍼 코드 · 가족 공유)입니다.")
    }

    static func installFailures(_ performance: StoreAnalytics.InstallPerformance?) -> Finding? {
        guard let performance, performance.attempts >= 50, let rate = performance.successRate else { return nil }
        let failure = 1 - rate
        guard failure >= 0.02 else { return nil }
        return Finding(id: "install-fail", level: .bad, title: "설치 \(AnalyticsFormat.percent(failure))가 실패합니다",
                       detail: "설치 시도 \(AnalyticsFormat.count(performance.attempts)) · 실패 \(AnalyticsFormat.count(performance.failures)).",
                       action: "설치 성능 카드의 실패한 OS 를 보세요.")
    }

    static func webPreview(_ rows: [Row]) -> Finding? {
        let views = rows.filter { $0["Event"] == "Page view" }
        let total = sum(views, "Counts")
        guard total >= 30 else { return nil }
        let desktop = sum(views.filter { $0["Device"] == "Desktop" || $0["Device"] == "Other" }, "Counts") / total
        guard desktop >= 0.6 else { return nil }
        return Finding(id: "web", level: .info, title: "웹 링크는 주로 컴퓨터에서 열립니다 (\(AnalyticsFormat.percent(desktop)))",
                       detail: "apps.apple.com 조회 \(AnalyticsFormat.count(total))회. 컴퓨터에서는 바로 받을 수 없습니다.",
                       action: "링크를 건 곳에 QR 이나 \"휴대폰에서 열기\" 안내를 붙이세요.")
    }

    static func optIn(_ optIn: StoreAnalytics.OptIn?) -> Finding? {
        guard let rate = optIn?.rate else { return nil }
        return Finding(id: "opt-in", level: .info, title: "세션 · 크래시 숫자는 \(AnalyticsFormat.percent(rate))만 본 것입니다",
                       detail: "받은 사람 중 \"앱 개발자와 공유\" 에 동의한 몫입니다. 세션 숫자는 크기가 아니라 증감과 비율로 읽으세요.")
    }

    // MARK: 셈

    static func number(_ text: String?) -> Double? { StoreAnalytics.number(text) }
    static func sum(_ rows: [Row], _ column: String) -> Double { StoreAnalytics.sum(rows, column) }

    /// 노출 · 조회는 고유 기기 수가 있으면 그것, 없으면 건수.
    static func uniqueSum(_ rows: [Row]) -> Double {
        rows.reduce(0) { $0 + (number($1["Unique Counts"]) ?? number($1["Counts"]) ?? 0) }
    }
}

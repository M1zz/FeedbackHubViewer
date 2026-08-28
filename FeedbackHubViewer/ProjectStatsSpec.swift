//
//  ProjectStatsSpec.swift
//  FeedbackHubViewer
//
//  각 앱이 자기 통계 화면에서 쓰는 어휘와 해석을, 뷰어가 그대로 쓸 수 있게 담은 스펙.
//
//  왜 필요한가: 허브가 받는 데이터(UsageSnapshot의 `metrics`, UsageEvent 이름)는 앱마다
//  뜻이 다르다. `shortcuts`는 ClipKeyboard의 단축어 수이고 `alertsMax`는 두번알림의
//  알림 개수 수요다. 무료 한도 10개·알림 1개 같은 경계도 그 앱에서만 뜻이 있다.
//  뷰어가 이걸 모르면 키 원문과 평균값만 늘어놓게 된다.
//
//  왜 JSON인가: 지표를 만드는 곳은 앱이다. 스펙 원본은 각 앱 리포의
//  `docs/usage-spec.json`에 두고(지표를 추가하는 커밋에서 라벨도 같이 쓰게 된다),
//  `scripts/sync-stats-specs.sh`로 여기 `Specs/`에 복사해 온다. 계산식이 아니라
//  **경계값과 규칙**만 데이터로 적으므로, 앱이 지표를 늘려도 뷰어 코드는 그대로다.
//
//  ⚠️ 스펙에 없는 키는 절대 감추지 않는다. 원문 그대로 계속 보여주고, 화면에는
//     "스펙에 없는 지표"로 모아 알린다 — 드리프트가 조용히 사라지는 대신 할 일이 된다.
//

import Foundation

// MARK: - Spec

struct ProjectStatsSpec: Decodable {
    /// 이 파일이 따르는 스키마 버전. 뷰어가 모르는 버전이면 무시하고 일반 화면으로 떨어진다.
    let specVersion: Int
    /// 이 앱의 CloudKit `appId`. 프로젝트 키와 맞춰 스펙을 고른다.
    let appId: String
    /// 사람이 읽는 이름. `appId` 대신 이 이름으로 기록된 프로젝트도 같은 스펙을 쓴다.
    let appName: String?
    /// 스냅샷 `metrics` 키 → 화면 라벨.
    var metricLabels: [String: MetricLabel] = [:]
    /// 접두사로 붙는 동적 키(`persona.memo`, `flag.ownsWatch`)의 라벨.
    var metricPrefixLabels: [String: String] = [:]
    /// 이벤트 이름 → 화면 라벨. 슬라이스(`paywall_view:memo`)는 앞부분만 맞춘다.
    var eventLabels: [String: String] = [:]
    /// 이 앱에서 제일 먼저 볼 숫자들. 여러 묶음을 둘 수 있다.
    var tileGroups: [TileGroupSpec] = []
    /// 설치를 어떤 지표의 구간으로 나눈 분포.
    var distributions: [DistributionSpec] = []
    /// 합이 전체인 몫(도넛/막대) — 종류별 비중.
    var shares: [ShareSpec] = []
    /// 규칙에서 이름으로 쓸 파생값.
    var derived: [DerivedSpec] = []
    /// 설치 하나하나를 무리로 나누는 규칙.
    var segments: SegmentSpec?
    /// 이벤트를 순서대로 세워 단계별로 몇이 남는지 본다(페이월 → 결제).
    var funnels: [FunnelSpec] = []

    static let supportedVersion = 1

    // 합성된 Decodable은 기본값이 있는 프로퍼티라도 키가 없으면 실패한다. 스펙은 앱마다
    // 쓰는 절(節)이 달라서(어떤 앱은 `shares`가 없고 어떤 앱은 `derived`가 없다) 빠진
    // 절은 빈 값으로 읽어야 한다.
    enum CodingKeys: String, CodingKey {
        case specVersion, appId, appName, metricLabels, metricPrefixLabels
        case eventLabels, tileGroups, distributions, shares, derived, segments, funnels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specVersion = try c.decode(Int.self, forKey: .specVersion)
        appId = try c.decode(String.self, forKey: .appId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        metricLabels = try c.decodeIfPresent([String: MetricLabel].self, forKey: .metricLabels) ?? [:]
        metricPrefixLabels = try c.decodeIfPresent([String: String].self, forKey: .metricPrefixLabels) ?? [:]
        eventLabels = try c.decodeIfPresent([String: String].self, forKey: .eventLabels) ?? [:]
        tileGroups = try c.decodeIfPresent([TileGroupSpec].self, forKey: .tileGroups) ?? []
        distributions = try c.decodeIfPresent([DistributionSpec].self, forKey: .distributions) ?? []
        shares = try c.decodeIfPresent([ShareSpec].self, forKey: .shares) ?? []
        derived = try c.decodeIfPresent([DerivedSpec].self, forKey: .derived) ?? []
        segments = try c.decodeIfPresent(SegmentSpec.self, forKey: .segments)
        funnels = try c.decodeIfPresent([FunnelSpec].self, forKey: .funnels) ?? []
    }

    struct MetricLabel: Decodable {
        let label: String
        /// "분", "개" 같은 꼬리. 없으면 붙이지 않는다.
        var unit: String?
        /// 이 지표를 "설치당 평균"에 넣지 않는다(플래그·최대값처럼 평균이 뜻 없는 값).
        var excludeFromAverages: Bool?
    }

    struct TileGroupSpec: Decodable {
        let title: String
        var note: String?
        let tiles: [TileSpec]
    }

    struct TileSpec: Decodable {
        let label: String
        let kind: Kind
        /// `kind`가 쓰는 지표 키.
        var metric: String?
        /// `sumPerMatchingInstall`에서 "어떤 설치를 셀지" 고르는 플래그 키.
        var condition: String?
        /// `kind == .segment`일 때 셀 무리 이름.
        var segment: String?
        var unit: String?
        var format: Format?
        var hint: String?

        enum Kind: String, Decodable {
            /// 이 지표가 0보다 큰 설치 수(그리고 전체 대비 비율).
            case installsWithMetric
            /// 모든 설치의 합계.
            case sum
            /// 설치당 평균.
            case average
            /// `condition` 플래그가 켜진 설치들만 놓고 본 `metric` 평균.
            case sumPerMatchingInstall
            /// 두 지표의 비율(metric ÷ condition).
            case ratio
            /// `segments` 규칙에서 이 이름으로 분류된 설치 수.
            case segment
        }

        enum Format: String, Decodable {
            case integer, decimal1, percent, countAndPercent
        }
    }

    struct DistributionSpec: Decodable {
        let title: String
        let metric: String
        var note: String?
        let buckets: [Bucket]

        struct Bucket: Decodable {
            let label: String
            let from: Double
            /// 없으면 위로 열린 구간.
            var to: Double?
        }
    }

    struct ShareSpec: Decodable {
        let title: String
        var note: String?
        let parts: [Part]

        struct Part: Decodable {
            let label: String
            let metric: String
        }
    }

    struct DerivedSpec: Decodable {
        let name: String
        let kind: Kind
        /// `choose`: 이 플래그가 켜져 있으면 `whenSet`, 아니면 `whenUnset`.
        var flag: String?
        var whenSet: Double?
        var whenUnset: Double?
        /// `difference`: `from` - `subtract` (0 아래로는 내려가지 않는다).
        var from: String?
        var subtract: String?
        /// `anyAbove`: 하나라도 참이면 1.
        var terms: [Condition]?

        enum Kind: String, Decodable {
            case choose, difference, anyAbove
        }
    }

    struct SegmentSpec: Decodable {
        let title: String
        var note: String?
        /// 위에서부터 처음 걸리는 규칙 하나로 정해진다 — 그래야 한 설치가 한 무리에만
        /// 속하고 합이 전체와 맞는다.
        let rules: [Rule]

        struct Rule: Decodable {
            let name: String
            var hint: String?
            /// 모두 참이어야 이 무리다. 비어 있으면 "나머지 전부".
            var when: [Condition]

            enum CodingKeys: String, CodingKey { case name, hint, when }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                hint = try c.decodeIfPresent(String.self, forKey: .hint)
                when = try c.decodeIfPresent([Condition].self, forKey: .when) ?? []
            }
        }
    }

    /// 이벤트를 순서대로 세운 퍼널. 다른 절과 달리 스냅샷 `metrics`가 아니라
    /// **이벤트 집계**를 읽는다 — 결제는 설치에 남는 상태가 아니라 일어난 일이다.
    ///
    /// 단계는 이벤트의 **기본형**으로 적는다. 앱이 슬라이스를 붙여 보내면
    /// (`paywall_cta_tapped:buy`, `:memo`) 같은 기본형끼리 합쳐서 한 단계로 센다.
    struct FunnelSpec: Decodable {
        let title: String
        var note: String?
        /// 무엇을 셀지. 기본은 `installs` — "몇 명이 여기까지 왔나"가 전환율이고,
        /// 건수는 한 사람이 페이월을 열 번 봐도 열로 세어 비율을 부풀린다.
        var basis: Basis?
        let steps: [Step]

        enum Basis: String, Decodable { case installs, events }

        struct Step: Decodable {
            let label: String
            /// 이벤트 기본형 하나.
            var event: String?
            /// 여러 이름을 한 단계로 묶을 때(`purchase_cancelled` + `purchase_failed`).
            var anyOf: [String]?
            var hint: String?

            var names: [String] {
                if let anyOf, !anyOf.isEmpty { return anyOf }
                return event.map { [$0] } ?? []
            }
        }
    }

    /// 값 하나를 읽어 비교하는 조건. 값은 지표 키 하나, 여러 키의 합, 두 키의 비율,
    /// 또는 `derived`가 정의한 이름이다.
    struct Condition: Decodable {
        var metric: String?
        var sum: [String]?
        /// [분자, 분모]. 분모가 0이면 0으로 본다.
        var ratio: [String]?
        var derived: String?

        var lt: Double?
        var lte: Double?
        var gt: Double?
        var gte: Double?
        var eq: Double?
    }
}

// MARK: - Evaluation

extension ProjectStatsSpec {

    /// 스펙이 만들어 내는 화면 조각. 뷰는 이것만 그린다.
    enum Insight: Identifiable {
        case tiles(title: String, note: String?, items: [Tile])
        case bars(title: String, note: String?, rows: [Bar])
        case funnel(title: String, note: String?, steps: [Step])

        var id: String {
            switch self {
            case .tiles(let title, _, _), .bars(let title, _, _), .funnel(let title, _, _):
                return title
            }
        }

        struct Tile: Identifiable {
            let label: String
            let value: String
            var hint: String?
            var id: String { label }
        }

        struct Bar: Identifiable {
            let label: String
            let value: String
            /// 0~1. 막대 길이.
            let ratio: Double
            var hint: String?
            var id: String { label }
        }

        /// 퍼널 한 칸.
        struct Step: Identifiable {
            let label: String
            let count: Int
            /// 첫 단계 대비 0~1 — 막대 길이이자 전체 전환율. 첫 단계는 1.
            let ratio: Double
            /// 바로 앞 단계 대비. 첫 단계는 nil.
            let fromPrevious: Double?
            /// 이 단계의 이벤트가 **한 건도 도착한 적이 없다**. 0건과는 다른 말이다:
            /// 아무도 결제를 안 한 게 아니라 앱이 그 이벤트를 안 보내고 있다는 뜻이고,
            /// 스펙이 아니라 앱을 고쳐야 한다.
            let isMissing: Bool
            /// 앞 단계보다 **많다**. 퍼널이 성립하려면 각 단계가 앞 단계의 부분집합이어야
            /// 하는데, 이벤트 이름만으로는 "앞을 거쳐서 왔다"를 강제할 수 없다
            /// (페이월은 넛지 말고 다른 데서도 열린다). 그래서 전환율인 척하지 않고
            /// 포함 관계가 아니라는 사실을 그대로 드러낸다.
            let exceedsPrevious: Bool
            var hint: String?
            var id: String { label }
        }
    }

    /// 스냅샷 지표 묶음을 이 앱의 화면 조각으로 바꾼다.
    func insights(for snapshots: [[String: Double]]) -> [Insight] {
        guard !snapshots.isEmpty else { return [] }
        var result: [Insight] = []

        let segmentNames = segments.map { spec in
            snapshots.map { segmentName(for: $0, rules: spec.rules) }
        }

        for group in tileGroups {
            let tiles = group.tiles.map { tile in
                Insight.Tile(label: tile.label,
                             value: value(of: tile, in: snapshots, segmentNames: segmentNames ?? []),
                             hint: tile.hint)
            }
            result.append(.tiles(title: group.title, note: group.note, items: tiles))
        }

        for distribution in distributions {
            let counts = distribution.buckets.map { bucket in
                snapshots.filter { metrics in
                    let n = metrics[distribution.metric] ?? 0
                    return n >= bucket.from && n <= (bucket.to ?? .greatestFiniteMagnitude)
                }.count
            }
            let maximum = max(counts.max() ?? 0, 1)
            let rows = zip(distribution.buckets, counts).map { bucket, count in
                Insight.Bar(label: bucket.label,
                            value: "\(count)곳",
                            ratio: Double(count) / Double(maximum))
            }
            result.append(.bars(title: distribution.title, note: distribution.note, rows: rows))
        }

        for share in shares {
            let totals = share.parts.map { part in
                snapshots.reduce(0.0) { $0 + ($1[part.metric] ?? 0) }
            }
            let sum = totals.reduce(0, +)
            guard sum > 0 else { continue }
            let rows = zip(share.parts, totals).map { part, total in
                Insight.Bar(label: part.label,
                            value: "\(Int(total)) (\(Self.percent(total / sum)))",
                            ratio: total / sum)
            }
            result.append(.bars(title: share.title, note: share.note, rows: rows))
        }

        if let segments, let segmentNames {
            var counts: [String: Int] = [:]
            for name in segmentNames { counts[name, default: 0] += 1 }
            let total = Double(snapshots.count)
            // 같은 이름의 규칙이 여러 개일 수 있다 — 조건의 OR를 그렇게 적는다.
            // 화면에는 한 줄로 합쳐 보여준다.
            var seen = Set<String>()
            let rows = segments.rules.compactMap { rule -> Insight.Bar? in
                guard seen.insert(rule.name).inserted else { return nil }
                let count = counts[rule.name] ?? 0
                guard count > 0 else { return nil }
                return Insight.Bar(label: rule.name,
                                   value: "\(count)곳 (\(Self.percent(Double(count) / total)))",
                                   ratio: Double(count) / total,
                                   hint: rule.hint)
            }
            if !rows.isEmpty {
                result.append(.bars(title: segments.title, note: segments.note, rows: rows))
            }
        }

        return result
    }

    /// 이벤트 퍼널. 스냅샷이 아니라 이벤트 집계를 받는다 — `tallies`의 키는 앱이 보낸
    /// 이름 원문(슬라이스 포함)이고, 값은 전 기간 합계다(`UsageRollups.eventTotals`).
    ///
    /// 슬라이스는 여기서 합친다. `paywall_cta_tapped:buy`와 `:memo`는 "버튼을 누른
    /// 사람"이라는 한 단계이고, 설치 수를 셀 때는 두 집합의 **합집합**이어야 한다 —
    /// 둘 다 누른 사람을 두 명으로 세면 전환율이 100%를 넘는다.
    func funnelInsights(for tallies: [String: UsageNameTotal]) -> [Insight] {
        funnels.compactMap { funnel in
            let basis = funnel.basis ?? .installs
            var steps: [Insight.Step] = []
            var first: Int?
            var previous: Int?

            for step in funnel.steps {
                let wanted = Set(step.names)
                let matching = tallies.filter { wanted.contains(Self.eventBase($0.key)) }
                let count: Int
                switch basis {
                case .events:
                    count = matching.values.reduce(0) { $0 + $1.count }
                case .installs:
                    var installs: Set<String> = []
                    for total in matching.values { installs.formUnion(total.installs) }
                    count = installs.count
                }

                let base = first ?? count
                if first == nil { first = count }
                steps.append(Insight.Step(
                    label: step.label,
                    count: count,
                    ratio: base > 0 ? min(1, Double(count) / Double(base)) : 0,
                    fromPrevious: previous.map { $0 > 0 ? Double(count) / Double($0) : 0 },
                    // 도착한 적이 아예 없는 것과 0건은 다른 말이다: 앞은 앱이 그
                    // 이벤트를 안 보낸다는 뜻이라 스펙이 아니라 앱을 고쳐야 한다.
                    isMissing: matching.isEmpty,
                    exceedsPrevious: previous.map { count > $0 } ?? false,
                    hint: step.hint))
                previous = count
            }

            guard !steps.isEmpty else { return nil }
            return .funnel(title: funnel.title, note: funnel.note, steps: steps)
        }
    }

    /// 스펙이 이름을 붙이지 않은 지표 키 — 앱이 새 지표를 보내기 시작했다는 신호다.
    func unknownMetricKeys(in snapshots: [[String: Double]]) -> [String] {
        var keys = Set<String>()
        for metrics in snapshots { keys.formUnion(metrics.keys) }
        return keys
            .subtracting(metricLabels.keys)
            .filter { key in !metricPrefixLabels.keys.contains { key.hasPrefix($0) } }
            .sorted()
    }

    /// 스펙이 이름을 붙이지 않은 이벤트 이름.
    func unknownEventNames(in names: [String]) -> [String] {
        Set(names.map(Self.eventBase)).subtracting(eventLabels.keys).sorted()
    }

    // MARK: Labels

    /// `shortcuts` → "단축어 수". 모르는 키는 원문 그대로 (사라지면 안 된다).
    func label(forMetric key: String) -> String {
        if let entry = metricLabels[key] {
            guard let unit = entry.unit, !unit.isEmpty else { return entry.label }
            return "\(entry.label) (\(unit))"
        }
        // `persona.memo` 처럼 앱이 값에 따라 만들어 보내는 키. 접두사만 번역하고
        // 뒤는 그대로 살린다 — 그 꼬리가 무엇을 세는지의 답이다.
        if let (prefix, label) = metricPrefixLabels.first(where: { key.hasPrefix($0.key) }) {
            let tail = key.dropFirst(prefix.count)
            return tail.isEmpty ? label : "\(label) (\(tail))"
        }
        return key
    }

    /// `paywall_view:memo` → "페이월을 봄 (memo)". 꼬리는 살린다 — 어느 한도가 결제를
    /// 만드는가의 답이 거기 있다.
    func label(forEvent raw: String) -> String {
        let base = Self.eventBase(raw)
        guard let named = eventLabels[base] else { return raw }
        let slice = raw.dropFirst(base.count).dropFirst()
        return slice.isEmpty ? named : "\(named) (\(slice))"
    }

    func excludesFromAverages(_ key: String) -> Bool {
        metricLabels[key]?.excludeFromAverages ?? false
    }

    static func eventBase(_ raw: String) -> String {
        String(raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    // MARK: Internals

    private func value(of tile: TileSpec,
                       in snapshots: [[String: Double]],
                       segmentNames: [String]) -> String {
        let count = Double(snapshots.count)
        switch tile.kind {
        case .installsWithMetric:
            guard let key = tile.metric else { return "—" }
            let matching = Double(snapshots.filter { ($0[key] ?? 0) > 0 }.count)
            if tile.format == .percent { return Self.percent(count > 0 ? matching / count : 0) }
            return "\(Int(matching))곳 (\(Self.percent(count > 0 ? matching / count : 0)))"
        case .sum:
            guard let key = tile.metric else { return "—" }
            let total = snapshots.reduce(0.0) { $0 + ($1[key] ?? 0) }
            return Self.format(total, as: tile.format, unit: tile.unit)
        case .average:
            guard let key = tile.metric else { return "—" }
            let total = snapshots.reduce(0.0) { $0 + ($1[key] ?? 0) }
            return Self.format(count > 0 ? total / count : 0, as: tile.format ?? .decimal1, unit: tile.unit)
        case .sumPerMatchingInstall:
            guard let key = tile.metric, let flag = tile.condition else { return "—" }
            let matching = snapshots.filter { ($0[flag] ?? 0) > 0 }
            let total = matching.reduce(0.0) { $0 + ($1[key] ?? 0) }
            let divisor = Double(matching.count)
            return Self.format(divisor > 0 ? total / divisor : 0, as: tile.format ?? .decimal1, unit: tile.unit)
        case .ratio:
            guard let key = tile.metric, let over = tile.condition else { return "—" }
            let numerator = snapshots.reduce(0.0) { $0 + ($1[key] ?? 0) }
            let denominator = snapshots.reduce(0.0) { $0 + ($1[over] ?? 0) }
            return Self.percent(denominator > 0 ? numerator / denominator : 0)
        case .segment:
            guard let name = tile.segment else { return "—" }
            let matching = Double(segmentNames.filter { $0 == name }.count)
            if tile.format == .percent { return Self.percent(count > 0 ? matching / count : 0) }
            return "\(Int(matching))곳"
        }
    }

    private func segmentName(for metrics: [String: Double], rules: [SegmentSpec.Rule]) -> String {
        let derivedValues = self.derivedValues(for: metrics)
        for rule in rules {
            if rule.when.allSatisfy({ matches($0, metrics: metrics, derived: derivedValues) }) {
                return rule.name
            }
        }
        return rules.last?.name ?? "기타"
    }

    private func derivedValues(for metrics: [String: Double]) -> [String: Double] {
        var values: [String: Double] = [:]
        for spec in derived {
            switch spec.kind {
            case .choose:
                let isSet = (metrics[spec.flag ?? ""] ?? 0) > 0
                values[spec.name] = isSet ? (spec.whenSet ?? 0) : (spec.whenUnset ?? 0)
            case .difference:
                let from = number(named: spec.from, metrics: metrics, derived: values)
                let subtract = number(named: spec.subtract, metrics: metrics, derived: values)
                values[spec.name] = max(0, from - subtract)
            case .anyAbove:
                let terms = spec.terms ?? []
                values[spec.name] = terms.contains { matches($0, metrics: metrics, derived: values) } ? 1 : 0
            }
        }
        return values
    }

    /// 파생값 이름이면 그 값을, 아니면 지표 키로 본다 — 규칙에서 둘을 같은 자리에 쓴다.
    private func number(named name: String?, metrics: [String: Double], derived: [String: Double]) -> Double {
        guard let name else { return 0 }
        return derived[name] ?? metrics[name] ?? 0
    }

    private func matches(_ condition: Condition,
                         metrics: [String: Double],
                         derived: [String: Double]) -> Bool {
        let value: Double
        if let key = condition.metric {
            value = metrics[key] ?? 0
        } else if let keys = condition.sum {
            value = keys.reduce(0.0) { $0 + (metrics[$1] ?? 0) }
        } else if let pair = condition.ratio, pair.count == 2 {
            let denominator = metrics[pair[1]] ?? 0
            value = denominator > 0 ? (metrics[pair[0]] ?? 0) / denominator : 0
        } else if let name = condition.derived {
            value = derived[name] ?? 0
        } else {
            return false
        }

        if let lt = condition.lt, !(value < lt) { return false }
        if let lte = condition.lte, !(value <= lte) { return false }
        if let gt = condition.gt, !(value > gt) { return false }
        if let gte = condition.gte, !(value >= gte) { return false }
        if let eq = condition.eq, value != eq { return false }
        return true
    }

    private static func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", (ratio * 100).rounded())
    }

    private static func format(_ value: Double, as format: TileSpec.Format?, unit: String?) -> String {
        let text: String
        switch format {
        case .percent: return percent(value)
        case .decimal1: text = String(format: "%.1f", value)
        default: text = String(Int(value.rounded()))
        }
        guard let unit, !unit.isEmpty else { return text }
        return "\(text)\(unit)"
    }
}

// MARK: - Catalog

/// 번들에 들어 있는 앱별 스펙 전부. 앱을 켜는 동안 한 번만 읽는다.
enum ProjectStatsSpecCatalog {

    private static let all: [ProjectStatsSpec] = load()

    /// 이 프로젝트 키에 맞는 스펙. `appId`로 먼저 찾고, 이름으로 기록된 프로젝트도 받는다.
    static func spec(for projectKey: String) -> ProjectStatsSpec? {
        all.first { $0.appId == projectKey }
            ?? all.first { $0.appName == projectKey }
    }

    private static func load() -> [ProjectStatsSpec] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let spec = try? decoder.decode(ProjectStatsSpec.self, from: data),
                  spec.specVersion == ProjectStatsSpec.supportedVersion
            else { return nil }
            return spec
        }
    }
}

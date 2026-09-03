//
//  ProjectStatsSpec+Evaluation.swift
//  FeedbackHubViewer
//
//  Turning a spec into the pieces the 통계 화면 draws.
//
//  The spec itself is a declaration — what an app wants counted, in JSON. This
//  is the half that reads the hub's own numbers through it and hands back
//  `Insight`s: tiles, bars, funnels. The view draws those and knows nothing
//  about the spec at all.
//

import Foundation

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
                            value: "\(count)개",
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
                                   value: "\(count)개 (\(Self.percent(Double(count) / total)))",
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
            return "\(Int(matching))개 (\(Self.percent(count > 0 ? matching / count : 0)))"
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
            return "\(Int(matching))개"
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

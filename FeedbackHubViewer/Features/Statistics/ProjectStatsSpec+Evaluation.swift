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

    /// 스펙이 만들어 내는 화면 조각. **뷰는 이것만 그리고 스펙을 전혀 모른다.**
    ///
    /// 종류가 셋뿐인 것은 게으름이 아니라 설계다. 앱마다 보고 싶은 것이 달라도
    /// 그리는 모양은 몇 가지로 수렴한다 — 숫자 몇 개(`tiles`), 길이로 견주는
    /// 줄들(`bars`), 단계마다 줄어드는 것(`funnel`). 새 지표가 생길 때마다 새
    /// 모양을 만들면 앱마다 화면이 달라져 두 앱을 나란히 못 읽는다. 그래서
    /// **카드 종류는 늘어나도 모양은 안 늘린다**: 새 종류는 이 셋 중 하나로
    /// 번역되어야 하고, 안 되면 그건 정말 새 모양이 필요한 것이다(드물다).
    enum Insight: Identifiable {
        case tiles(Frame, items: [Tile])
        case bars(Frame, rows: [Bar])
        case funnel(Frame, steps: [Step], goal: Goal? = nil)

        var frame: Frame {
            switch self {
            case .tiles(let f, _), .bars(let f, _), .funnel(let f, _, _): return f
            }
        }
        var id: String { frame.id }

        /// 카드의 겉 — 제목·아이콘·각주, 그리고 어느 묶음에 들어가는가.
        struct Frame: Identifiable {
            let title: String
            var note: String?
            /// SF Symbol. 앱이 안 정하면 모양마다의 기본값을 쓴다.
            var icon: String
            /// 이 카드가 들어갈 묶음의 이름. nil이면 묶지 않는다.
            var section: String?
            /// 카드 맨 밑 한 줄 결론. 숫자를 보고 나서 읽을 말이라 맨 밑이다.
            var verdict: String?
            var id: String { (section ?? "") + "/" + title }
        }

        /// 목표선. 있으면 카드가 "이 앱이 스스로 그은 선"과 견줘 말한다 —
        /// 선이 있어야 7%가 "낮다"가 아니라 "하한의 7분의 1"로 읽힌다.
        struct Goal {
            var target: Double?
            var floor: Double?
        }

        struct Tile: Identifiable {
            let label: String
            let value: String
            var hint: String?
            var id: String { label }
        }

        /// 줄 하나의 무게. 색을 직접 적지 않는 이유: 앱 스펙이 색을 고르기
        /// 시작하면 앱마다 같은 뜻이 다른 색이 된다. 뜻만 적고 색은 뷰가 정한다.
        enum Tone: String, Decodable {
            /// 보통.
            case normal
            /// 지금 손댈 자리 — 값을 낼 이유가 지금 있는 사람 같은 것.
            case hot
            /// 곧 그렇게 될 자리.
            case warn
            /// 셈에는 들지만 할 일이 아닌 자리.
            case muted
        }

        struct Bar: Identifiable {
            let label: String
            let value: String
            /// 0~1. 막대 길이.
            let ratio: Double
            var hint: String?
            var tone: Tone = .normal
            /// 이 줄을 재는 지표·이벤트가 **한 번도 안 왔다.** 0과는 다른 말이라
            /// 값 자리에 —를 두고 색을 죽인다.
            var isMissing: Bool = false
            /// 이 줄 앞에서 한 번 끊는다. 위아래의 뜻이 다를 때만(할 일 / 아닌 것).
            var startsGroup: Bool = false
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
            /// 이 단계의 이벤트·지표가 **한 건도 도착한 적이 없다**. 0건과는 다른
            /// 말이다: 아무도 못 간 게 아니라 앱이 아직 안 보낸다는 뜻이고,
            /// 스펙이 아니라 앱을 고쳐야 한다.
            let isMissing: Bool
            /// 앞 단계보다 **많다**. 퍼널이 성립하려면 각 단계가 앞 단계의
            /// 부분집합이어야 하는데, 이벤트 이름만으로는 "앞을 거쳐서 왔다"를
            /// 강제할 수 없다. 그래서 전환율인 척하지 않고 사실을 드러낸다.
            let exceedsPrevious: Bool
            var hint: String?
            var id: String { label }
        }
    }

    /// 한 묶음 — 제목 아래 카드 몇 장.
    struct Section: Identifiable {
        let title: String?
        let insights: [Insight]
        var id: String { title ?? "_" }
    }

    // MARK: - 입력

    /// 카드를 만드는 데 필요한 **모든** 입력을 한 자루에 담은 것.
    ///
    /// 왜 자루인가: 예전에는 카드 종류마다 입력이 달라서 함수 시그니처가 갈렸다
    /// (`insights(for: metrics)` · `funnelInsights(for: tallies, eventCountsAvailable:)`),
    /// 그래서 새 종류가 새 입력을 요구하면 호출부까지 따라 바뀌었다. 실제로 수익
    /// 카드는 권한(열림/안 열림)이 필요해서 스펙 밖 · 스토어 안에 따로 살았고,
    /// 카드 한 장 늘리는 데 파일 넷을 고쳐야 했다. 자루 하나면 종류를 더하는 일이
    /// **이 파일에 함수 하나**가 된다.
    struct Context {
        /// 설치마다 그 설치의 `metrics`. 카드 대부분이 이것만 읽는다.
        let installs: [[String: Double]]
        /// 이벤트 이름별 전 기간 집계(슬라이스 포함).
        let events: [String: UsageNameTotal]
        /// 건수를 말할 수 있는가. 무리를 고른 동안은 거짓이다
        /// (`FeedbackStore+Audience.swift`).
        var eventCountsAvailable: Bool = true
        /// 설치마다 유료 기능이 열려 있는가. `installs`와 같은 순서·같은 길이이고,
        /// `nil`은 권한을 못 읽는 설치다. 한도 카드가 "이미 열린 사람"을 모수에서
        /// 빼는 데 쓴다.
        var unlocked: [Bool?] = []

        var installCount: Int { installs.count }
    }

    // MARK: - 조립

    /// 이 앱의 대시보드 전체. 스펙이 정한 차례대로, 스펙이 정한 묶음으로.
    ///
    /// 카드 목록은 `cards`가 있으면 그것이고, 없으면 옛 절들(`tileGroups` ·
    /// `distributions` · …)을 지금까지의 차례대로 풀어 쓴 것이다. 그래서 이미
    /// 쓰던 스펙은 한 글자도 안 고쳐도 그대로 돈다.
    func dashboard(in context: Context) -> [Section] {
        var order: [String?] = []
        var grouped: [String?: [Insight]] = [:]
        for card in cards {
            guard let insight = build(card, in: context) else { continue }
            let key = insight.frame.section
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(insight)
        }
        return order.map { Section(title: $0, insights: grouped[$0] ?? []) }
    }

    /// 카드 한 장. **새 종류를 더하는 자리는 여기 한 곳이다** —
    /// `DashboardCardSpec`에 case 하나, 여기 분기 하나, 아래 만드는 함수 하나.
    private func build(_ card: DashboardCardSpec, in context: Context) -> Insight? {
        switch card {
        case .tiles(let spec):        return tilesInsight(spec, in: context)
        case .distribution(let spec): return distributionInsight(spec, in: context)
        case .share(let spec):        return shareInsight(spec, in: context)
        case .segments(let spec):     return segmentsInsight(spec, in: context)
        case .funnel(let spec):       return funnelInsight(spec, in: context)
        case .ladder(let spec):       return ladderInsight(spec, in: context)
        case .wall(let spec):         return wallInsight(spec, in: context)
        case .moments(let spec):      return momentsInsight(spec, in: context)
        }
    }

    // MARK: - 카드 만들기

    private func tilesInsight(_ spec: TileGroupSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let names = segments.map { s in context.installs.map { segmentName(for: $0, rules: s.rules) } }
        let items = spec.tiles.map { tile in
            Insight.Tile(label: tile.label,
                         value: value(of: tile, in: context.installs, segmentNames: names ?? []),
                         hint: tile.hint)
        }
        return .tiles(spec.frame(default: "star.circle"), items: items)
    }

    private func distributionInsight(_ spec: DistributionSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let counts = spec.buckets.map { bucket in
            context.installs.filter { metrics in
                let n = metrics[spec.metric] ?? 0
                return n >= bucket.from && n <= (bucket.to ?? .greatestFiniteMagnitude)
            }.count
        }
        let maximum = max(counts.max() ?? 0, 1)
        let rows = zip(spec.buckets, counts).map { bucket, count in
            Insight.Bar(label: bucket.label, value: "\(count)명",
                        ratio: Double(count) / Double(maximum))
        }
        return .bars(spec.frame(default: "chart.bar"), rows: rows)
    }

    private func shareInsight(_ spec: ShareSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let totals = spec.parts.map { part in
            context.installs.reduce(0.0) { $0 + ($1[part.metric] ?? 0) }
        }
        let sum = totals.reduce(0, +)
        guard sum > 0 else { return nil }
        let rows = zip(spec.parts, totals).map { part, total in
            Insight.Bar(label: part.label,
                        value: "\(Int(total)) (\(Self.percent(total / sum)))",
                        ratio: total / sum)
        }
        return .bars(spec.frame(default: "chart.pie"), rows: rows)
    }

    private func segmentsInsight(_ spec: SegmentSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let names = context.installs.map { segmentName(for: $0, rules: spec.rules) }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        let total = Double(context.installs.count)
        // 같은 이름의 규칙이 여럿일 수 있다 — 조건의 OR를 그렇게 적는다.
        var seen = Set<String>()
        let rows = spec.rules.compactMap { rule -> Insight.Bar? in
            guard seen.insert(rule.name).inserted else { return nil }
            let count = counts[rule.name] ?? 0
            guard count > 0 else { return nil }
            return Insight.Bar(label: rule.name,
                               value: "\(count)명 (\(Self.percent(Double(count) / total)))",
                               ratio: Double(count) / total,
                               hint: rule.hint)
        }
        guard !rows.isEmpty else { return nil }
        return .bars(spec.frame(default: "person.3"), rows: rows)
    }

    /// 이벤트 퍼널. 슬라이스는 여기서 합친다 — `paywall_cta_tapped:buy`와 `:memo`는
    /// "버튼을 누른 사람"이라는 한 단계이고, 설치 수를 셀 때는 두 집합의 **합집합**
    /// 이어야 한다(둘 다 누른 사람을 두 명으로 세면 전환율이 100%를 넘는다).
    ///
    /// 건수 기준 퍼널은 무리를 고른 동안 통째로 빠진다. 사람 수는 집합의 교집합으로
    /// 정확히 갈리지만 건수는 못 가르므로, 0으로 그리면 "아무도 안 했다"는 거짓말이
    /// 된다.
    private func funnelInsight(_ spec: FunnelSpec, in context: Context) -> Insight? {
        let basis = spec.basis ?? .installs
        guard basis == .installs || context.eventCountsAvailable else { return nil }
        var steps: [Insight.Step] = []
        var first: Int?
        var previous: Int?

        for step in spec.steps {
            let wanted = Set(step.names)
            let matching = context.events.filter { wanted.contains(Self.eventBase($0.key)) }
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
                isMissing: matching.isEmpty,
                exceedsPrevious: previous.map { count > $0 } ?? false,
                hint: step.hint))
            previous = count
        }
        guard !steps.isEmpty else { return nil }
        return .funnel(spec.frame(default: "arrow.down.right.circle"), steps: steps)
    }

    /// 사다리 — 설치에서 **가치를 받은 상태**까지 몇이 오는가.
    ///
    /// 퍼널과 모양은 같고 입력이 다르다. 퍼널은 일어난 일(이벤트)을 세고, 사다리는
    /// 설치에 남은 상태(지표)를 센다. 그래서 "앱을 지웠다 깐 사람"이 퍼널에서는
    /// 두 번 세어질 수 있어도 사다리에서는 한 번이다.
    private func ladderInsight(_ spec: LadderSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let first = context.installs.count
        var steps: [Insight.Step] = []
        var previous: Int?
        for rung in spec.steps {
            let count: Int
            let missing: Bool
            if let metric = rung.metric {
                let floor = rung.atLeast ?? 1
                count = context.installs.filter { ($0[metric] ?? 0) >= floor }.count
                // 그 지표를 **아무도 안 보내는** 것과 0명인 것은 다르다.
                missing = !context.installs.contains { $0[metric] != nil }
            } else {
                count = first
                missing = false
            }
            steps.append(Insight.Step(
                label: rung.label, count: count,
                ratio: first > 0 ? Double(count) / Double(first) : 0,
                fromPrevious: previous.map { $0 > 0 ? Double(count) / Double($0) : 0 },
                isMissing: missing, exceedsPrevious: false, hint: rung.hint))
            previous = count
        }
        guard !steps.isEmpty else { return nil }

        var frame = spec.frame(default: "figure.walk.arrival")
        frame.verdict = ladderVerdict(spec, steps: steps)
        return .funnel(frame, steps: steps, goal: .init(target: spec.target, floor: spec.floor))
    }

    /// 사다리 맨 밑 한 줄. 앱이 스스로 그어 둔 선과 견준다.
    private func ladderVerdict(_ spec: LadderSpec, steps: [Insight.Step]) -> String? {
        guard let last = steps.last, !last.isMissing else { return nil }
        let reached = last.ratio
        if let floor = spec.floor, reached < floor {
            var text = "마지막 칸이 \(Self.percent(reached))입니다. 이 앱이 정해 둔 하한 "
                     + "\(Self.percent(floor)) 아래예요."
            let worst = steps.filter { !$0.isMissing && $0.fromPrevious != nil }
                .min { ($0.fromPrevious ?? 1) < ($1.fromPrevious ?? 1) }
            if let worst, let drop = worst.fromPrevious {
                text += " 제일 크게 새는 칸은 \"\(worst.label)\"이고, 앞 칸의 "
                      + "\(Self.percent(drop))만 넘어옵니다."
            }
            return text
        }
        if let target = spec.target, reached < target {
            return "마지막 칸이 \(Self.percent(reached))로 목표 \(Self.percent(target))에 못 미칩니다."
        }
        return nil
    }

    /// 한도까지의 거리 — **값을 낼 이유가 생긴 사람이 몇인가.**
    ///
    /// 결제가 필요해지는 자리는 기능이 아니라 한도다. 그래서 잠재 고객은 "이 기능을
    /// 안 쓰는 사람"이 아니라 "한도에 닿았는데 아직 안 열린 사람"이다. 이미 열린
    /// 설치는 값을 낼 이유가 없으므로 모수에서 빼고 따로 센다 — 그 칸이 크면 손댈
    /// 곳은 가격표가 아니라 그 위다.
    private func wallInsight(_ spec: WallSpec, in context: Context) -> Insight? {
        guard !context.installs.isEmpty else { return nil }
        let near = max(1, spec.nearBy ?? 1)
        var blocked = 0, nearing = 0, roomLeft = 0, notStarted = 0, open = 0
        /// 모름은 두 갈래다 — 권한을 못 읽거나, 한도를 재는 지표를 안 보내거나.
        /// 둘 다 "어느 칸에도 못 넣는다"는 점은 같지만 고칠 것이 달라서 따로 센다.
        var noEntitlement = 0, noMetric = 0

        for (index, metrics) in context.installs.enumerated() {
            switch context.unlocked.indices.contains(index) ? context.unlocked[index] : nil {
            case true?: open += 1; continue
            case nil:   noEntitlement += 1; continue
            case false?: break
            }
            // 지표를 **안 보낸** 설치를 0으로 읽으면 "아직 시작 안 함"이 된다.
            // 안 보낸 것과 0인 것은 다른 말이다 — 한도 지표를 새 버전만 보내는
            // 앱에서는 그 차이가 설치의 95%가 되기도 한다.
            guard let raw = metrics[spec.metric] else { noMetric += 1; continue }
            let value = Int(raw)
            if value >= spec.limit { blocked += 1 }
            else if value >= spec.limit - near { nearing += 1 }
            else if value >= 1 { roomLeft += 1 }
            else { notStarted += 1 }
        }
        let unknown = noEntitlement + noMetric

        let scanned = blocked + nearing + roomLeft + notStarted + open + unknown
        guard scanned > 0 else { return nil }
        func row(_ label: String, _ count: Int, _ tone: Insight.Tone,
                 _ hint: String, startsGroup: Bool = false) -> Insight.Bar {
            .init(label: label, value: "\(count)명",
                  ratio: Double(count) / Double(scanned), hint: hint,
                  tone: count == 0 ? .muted : tone, startsGroup: startsGroup)
        }
        var rows = [
            row("지금 막혀 있음", blocked, .hot,
                "\(spec.label) \(spec.limit)개를 다 썼는데 유료 기능이 안 열린 설치. 값을 낼 이유가 지금 있는 사람입니다"),
            row("곧 막힘", nearing, .warn, "한도까지 얼마 안 남은 설치"),
            row("아직 여유", roomLeft, .normal, "쓰고는 있지만 한도가 아직 먼 설치"),
            row("아직 시작 안 함", notStarted, .muted,
                "\(spec.label)를 하나도 안 만든 설치. 값을 낼 이유가 아직 없습니다"),
            row("팔 대상 아님 (이미 열림)", open, .muted,
                "유료 기능이 이미 열려 있어 값을 낼 이유가 없는 설치", startsGroup: true)
        ]
        if unknown > 0 {
            var why: [String] = []
            if noEntitlement > 0 { why.append("권한을 안 보냄 \(noEntitlement)대") }
            if noMetric > 0 { why.append("\(spec.metric)을 안 보냄 \(noMetric)대") }
            rows.append(row("모름", unknown, .muted,
                            why.joined(separator: " · ") + " — 0이 아니라 못 셉니다"))
        }

        var frame = spec.frame(default: "person.badge.clock")
        let sellable = blocked + nearing
        var verdict = "지금 값을 낼 이유가 있는 사람은 \(scanned)대 중 \(sellable)명"
                    + "(\(Self.percent(Double(sellable) / Double(scanned))))입니다."
        if noMetric > scanned / 2 {
            verdict += " 다만 한도를 재는 \(spec.metric)을 보내는 설치가 "
                     + "\(scanned - noMetric)/\(scanned)대뿐이라, 이 숫자는 그 일부만 놓고 센 "
                     + "하한입니다. 나머지는 0이 아니라 못 셉니다."
        } else if open > sellable * 5, open > 0 {
            verdict += " 유료 기능이 이미 열린 설치가 \(open)대로 그보다 훨씬 많아요 — "
                     + "가격표보다 먼저, 그 권한이 어떻게 열렸는지를 보셔야 합니다."
        }
        frame.verdict = verdict
        return .bars(frame, rows: rows)
    }

    /// 결제 화면이 뜨기로 **설계된** 자리마다, 실제로 떴는가.
    ///
    /// 한 건도 없는 자리는 "아무도 안 왔다"가 아니라 "그 벽이 아직 안 섰다"다.
    /// 둘은 고칠 곳이 달라서(가격 대 코드) 화면이 반드시 갈라 말해야 한다.
    private func momentsInsight(_ spec: MomentsSpec, in context: Context) -> Insight? {
        guard !spec.moments.isEmpty else { return nil }

        /// 이름에 슬라이스가 있으면 그것만, 기본형만 있으면 모든 슬라이스를 합친다.
        func installs(firing name: String) -> Set<String> {
            if name.contains(":") { return context.events[name]?.installs ?? [] }
            var union: Set<String> = []
            for (key, total) in context.events where Self.eventBase(key) == name {
                union.formUnion(total.installs)
            }
            return union
        }
        let tapped = spec.tappedEvent.map(installs(firing:))
        let purchased = spec.purchasedEvent.map(installs(firing:))

        let shown = spec.moments.map { installs(firing: $0.event) }
        let top = shown.map(\.count).max() ?? 0
        let rows = zip(spec.moments, shown).map { moment, set -> Insight.Bar in
            var hint: [String] = []
            if set.isEmpty {
                hint = ["이 벽은 아직 한 번도 안 섰습니다 — \(moment.event)가 한 건도 안 왔어요. "
                        + "아무도 안 온 게 아니라 코드에 그 자리가 없거나, 조건에 닿는 사람이 없는 겁니다."]
            } else {
                // 누름·결제는 그 벽을 만난 설치와의 **교집합**이라, 다른 벽에서 온
                // 결제가 이 벽의 성과로 섞이지 않는다.
                if let tapped { hint.append("누름 \(set.intersection(tapped).count)명") }
                if let purchased { hint.append("결제 \(set.intersection(purchased).count)명") }
                if let note = moment.note { hint.append(note) }
            }
            return .init(label: moment.label,
                         value: set.isEmpty ? "—" : "\(set.count)명",
                         // 막대는 **가장 많이 뜬 자리** 대비다. 설치 대비로 그리면
                         // 전부 0에 붙어 어느 벽이 그나마 섰는지가 안 보인다.
                         ratio: top > 0 ? Double(set.count) / Double(top) : 0,
                         hint: hint.joined(separator: " · "),
                         tone: set.isEmpty ? .muted : .normal,
                         isMissing: set.isEmpty)
        }

        var frame = spec.frame(default: "rectangle.on.rectangle.angled")
        if shown.allSatisfy(\.isEmpty) {
            frame.verdict = "설계한 벽 \(spec.moments.count)개가 하나도 안 섰습니다. "
                          + "값을 고치기 전에 이 화면들이 실제로 뜨는지부터 보셔야 해요."
        } else if spec.tappedEvent == nil && spec.purchasedEvent == nil {
            frame.verdict = "누름·결제를 셀 이벤트 기본형이 스펙에 없어서 뜬 횟수까지만 셉니다. "
                          + "tappedEvent·purchasedEvent를 적으면 벽마다 성과가 갈립니다."
        }
        return .bars(frame, rows: rows)
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
            return "\(Int(matching))명 (\(Self.percent(count > 0 ? matching / count : 0)))"
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
            return "\(Int(matching))명"
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

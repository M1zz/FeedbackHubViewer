//
//  StatsAnalysis.swift
//  FeedbackHubViewer
//
//  통계 탭의 해석. 카드마다 "무엇을 묻는 카드인가"와 "그래서 답이 뭔가"를 계산한다.
//
//  통계 화면은 원래 숫자를 늘어놓았고, 늘어놓은 숫자를 합쳐 결론을 내는 일은 읽는
//  사람의 머리에 남았다. 여기가 그 일을 대신한다. 뷰는 `Finding` 을 그리기만 하고,
//  원본 숫자는 "자세히" 아래로 접는다.
//
//  기준선은 두 종류다.
//   · 앱이 스스로 그은 선(스펙의 target · floor) — 있으면 그것이 먼저다
//   · 흔한 모바일 앱의 대략적인 중앙값 — 선이 없을 때만. 절대 기준이 아니라 "이만큼이면
//     흔하다"는 눈금이라, 답에 그렇다고 적는다.
//

import Foundation

struct StatsFinding: Identifiable {
    enum Topic: String {
        case growth, lifecycle, retention, habit, capacity, paid, flow, release, feedback
    }

    enum State: Int, Comparable {
        case bad = 0, watch, good, unknown
        static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }
    }

    let topic: Topic
    /// 이 카드가 묻는 것.
    let question: String
    /// 계산한 답 한두 문장.
    let answer: String
    let state: State
    /// 나쁠 때 할 일.
    var action: String?
    /// 같은 topic 이 여럿일 때(핵심 흐름) 가른다.
    var key: String = ""
    var id: String { topic.rawValue + key }
}

enum StatsAnalysis {

    /// 흔한 모바일 앱의 대략적인 잔존 중앙값. 앱이 선을 안 그었을 때만 눈금으로 쓴다.
    static let typicalRetention: [FeedbackStore.Retention.Checkpoint: Double] = [
        .day1: 0.25, .day7: 0.10, .day30: 0.05
    ]

    // MARK: - 늘고 있나

    static func growth(_ active: FeedbackStore.ActiveUsers, new7: Int, previousNew7: Int) -> StatsFinding {
        let question = "쓰는 사람이 늘고 있나?"
        guard !active.isEmpty else {
            return .init(topic: .growth, question: question,
                         answer: "최근 30일에 도착한 이벤트가 없어 모릅니다.", state: .unknown)
        }
        let week = active.week
        guard week.previous > 0 else {
            return .init(topic: .growth, question: question,
                         answer: "이번 주 \(week.current)명이 썼습니다. 견줄 지난주가 없어요.", state: .unknown)
        }
        let change = Double(week.current - week.previous) / Double(week.previous)
        var answer = "이번 주 \(week.current)명, 지난주보다 \(signed(change))."
        if previousNew7 > 0 {
            let newChange = Double(new7 - previousNew7) / Double(previousNew7)
            answer += " 새로 깐 설치는 \(new7)대로 \(signed(newChange))."
            if change < 0 && newChange >= 0 {
                answer += " 새로 오는 사람은 그대로인데 줄었으니 기존 사용자가 빠지고 있어요."
            } else if change < 0 && newChange < 0 {
                answer += " 새로 오는 사람부터 줄었어요."
            }
        }
        let state: StatsFinding.State = change <= -0.15 ? .bad : change < -0.05 ? .watch : .good
        var action: String?
        if state == .bad {
            action = previousNew7 > 0 && new7 < previousNew7
                ? "유입 탭에서 어느 구역이 새는지 보기"
                : "잔존 카드에서 어느 날에 빠지는지 보기"
        }
        return .init(topic: .growth, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 누가 들어오고 누가 나가나 (Lifecycle)

    static func lifecycle(_ lifecycle: FeedbackStore.Lifecycle) -> StatsFinding {
        let question = "들어오는 사람이 나가는 사람을 메우나?"
        guard !lifecycle.isEmpty, let last = lifecycle.weeks.last else {
            return .init(topic: .lifecycle, question: question, answer: "잴 활동이 없습니다.", state: .unknown)
        }
        var answer = "지난 7일: 신규 \(last.new) · 복귀 \(last.resurrected)명이 들어오고 \(last.dormant)명이 빠졌습니다."
        // 최근 4주를 합쳐 본 Quick Ratio. 한 주는 흔들린다.
        let recent = lifecycle.weeks.suffix(4)
        let inflow = recent.reduce(0) { $0 + $1.new + $1.resurrected }
        let outflow = recent.reduce(0) { $0 + $1.dormant }
        var state: StatsFinding.State = .unknown
        var action: String?
        if outflow > 0 {
            let ratio = Double(inflow) / Double(outflow)
            answer += " 최근 4주 Quick Ratio \(String(format: "%.2f", ratio))(들어옴 ÷ 빠짐)."
            if ratio < 0.8 {
                state = .bad
                answer += " 빠지는 쪽이 커서 줄고 있어요."
            } else if ratio < 1 {
                state = .watch
                answer += " 겨우 메우는 중이에요."
            } else {
                state = .good
                answer += ratio >= 1.5 ? " 들어오는 쪽이 넉넉히 커요." : " 조금씩 늘고 있어요."
            }
            let retainedShare = last.active > 0 ? Double(last.retained) / Double(last.active) : 0
            if state != .good {
                action = retainedShare < 0.3
                    ? "한 주를 넘겨 남는 사람이 적음: 잔존 카드의 1~2주째를 보기"
                    : "신규가 적음: 유입 탭 보기"
            }
        }
        return .init(topic: .lifecycle, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 남나

    static func retention(_ retention: FeedbackStore.Retention, sendsDailyOpen: Bool) -> StatsFinding {
        let question = "깐 사람이 남나?"
        guard !retention.isEmpty,
              let d1 = retention.pooled[.day1]?.ratio else {
            return .init(topic: .retention, question: question,
                         answer: "아직 잴 설치가 없어 모릅니다.", state: .unknown)
        }
        let d7 = retention.pooled[.day7]?.ratio
        let d30 = retention.pooled[.day30]?.ratio

        var parts = ["다음 날 \(percent(d1))"]
        if let d7 { parts.append("7일 뒤 \(percent(d7))") }
        if let d30 { parts.append("30일 뒤 \(percent(d30))") }
        var answer = parts.joined(separator: ", ") + "가 돌아옵니다."

        // 흔한 값과 견줘 가장 모자란 자리를 찾는다.
        var worst: (FeedbackStore.Retention.Checkpoint, Double)?
        for (checkpoint, value) in [(FeedbackStore.Retention.Checkpoint.day1, d1),
                                    (.day7, d7), (.day30, d30)] {
            guard let value, let typical = typicalRetention[checkpoint] else { continue }
            let ratio = value / typical
            if ratio < (worst?.1 ?? 1) { worst = (checkpoint, ratio) }
        }

        var state: StatsFinding.State = .good
        var action: String?
        if let (checkpoint, ratio) = worst {
            let typical = typicalRetention[checkpoint] ?? 0
            answer += " \(checkpoint.label)가 흔한 앱(약 \(percent(typical)))의 \(String(format: "%.1f", ratio))배라 여기서 가장 많이 잃어요."
            state = ratio < 0.6 ? .bad : .watch
            switch checkpoint {
            case .day1: action = "첫날 경험 고치기: 처음 연 날 가치를 못 받고 떠납니다"
            case .day7: action = "첫 주에 다시 부를 계기 만들기(알림 · 위젯 · 두 번째 가치)"
            case .day30: action = "한 달을 넘길 이유 만들기: 쓰는 습관이 굳지 않습니다"
            }
        } else {
            answer += " 모든 자리에서 흔한 앱보다 높아요."
        }

        // 곡선이 평평해지나 — 둘째 주 평균과 넷째 주 평균을 견준다.
        func average(_ curve: [Int: FeedbackStore.Retention.Rate], _ days: ClosedRange<Int>) -> Double? {
            let rates = days.compactMap { day -> FeedbackStore.Retention.Rate? in
                guard let rate = curve[day], rate.eligible >= 5 else { return nil }
                return rate
            }
            let eligible = rates.reduce(0) { $0 + $1.eligible }
            guard rates.count >= 3, eligible > 0 else { return nil }
            return Double(rates.reduce(0) { $0 + $1.returned }) / Double(eligible)
        }
        if let mid = average(retention.curve, 8...14), let late = average(retention.curve, 22...30), mid > 0 {
            if late / mid >= 0.7 {
                answer += " 곡선이 \(percent(late)) 근처에서 평평해집니다. 계속 쓰는 사람이 남아요."
            } else {
                answer += " 곡선이 한 달 내내 계속 떨어집니다. 굳은 사용자층이 아직 없어요."
                if state == .good { state = .watch }
            }
        }
        if let recent = average(retention.recentCurve, 1...7), let older = average(retention.olderCurve, 1...7), older > 0 {
            if recent > older * 1.2 { answer += " 최근 4주에 깐 사람이 첫 주에 더 자주 와요(나아지는 중)." }
            if recent < older * 0.8 { answer += " 최근 4주에 깐 사람이 첫 주에 덜 와요(나빠지는 중)." }
        }

        // 최근 주가 나아지고 있나 — 다 잰 7일 잔존으로 첫 코호트와 마지막 코호트를 견준다.
        let measured = retention.cohorts.compactMap { cohort -> Double? in
            guard let rate = cohort.rates[.day7], rate.eligible >= 5 else { return nil }
            return rate.ratio
        }
        if measured.count >= 4 {
            let half = measured.count / 2
            let older = measured.prefix(half).reduce(0, +) / Double(half)
            let newer = measured.suffix(half).reduce(0, +) / Double(measured.count - half)
            if newer > older * 1.2 { answer += " 최근 설치일수록 7일 잔존이 나아지고 있어요." }
            if newer < older * 0.8 { answer += " 최근 설치일수록 7일 잔존이 나빠지고 있어요." }
        }
        if !sendsDailyOpen {
            answer += " 이 앱은 app_open 을 안 보내 실제보다 낮게 잡혀요."
            if state == .bad { state = .watch }
        }
        return .init(topic: .retention, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 자주 오나

    static func habit(_ days: FeedbackStore.ActiveDays, stickiness: Double?) -> StatsFinding {
        let question = "얼마나 자주 오나?"
        guard !days.isEmpty, let first = days.buckets.first else {
            return .init(topic: .habit, question: question, answer: "최근 30일 이벤트가 없어 모릅니다.", state: .unknown)
        }
        let oneDay = Double(first.count) / Double(days.total)
        let heavy = days.buckets.last.map { Double($0.count) / Double(days.total) } ?? 0
        var answer = "이번 달 온 \(days.total)명 중 \(percent(oneDay))는 하루만 왔고"
        answer += heavy > 0 ? ", \(percent(heavy))는 \(days.buckets.last?.label ?? "") 왔어요." : "."
        if let stickiness {
            answer += " 한 사람이 한 달에 평균 \(String(format: "%.1f", stickiness * 30))일 씁니다."
        }
        // 이번 달에 깐 사람은 하루만 왔을 수밖에 없다 — 그만큼 빼고 본다.
        let adjusted = Double(max(first.count - days.installedWithin / 2, 0)) / Double(days.total)
        let state: StatsFinding.State
        var action: String?
        if adjusted >= 0.6 {
            state = .bad
            answer += " 한 번 써 보고 끝나는 사람이 대부분이에요."
            action = "첫 주 경험 보기: 두 번째로 여는 이유가 없습니다"
        } else if adjusted >= 0.4 {
            state = .watch
            answer += " 필요할 때만 여는 도구에 가까워요."
        } else {
            state = .good
            answer += " 여러 날 오는 사람이 중심이에요."
        }
        return .init(topic: .habit, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 어디까지 크나

    static func capacity(_ capacity: CarryingCapacity?) -> StatsFinding {
        let question = "지금 흐름이면 어디까지 크나?"
        guard let capacity, let ceiling = capacity.capacity, let fill = capacity.fill else {
            return .init(topic: .capacity, question: question,
                         answer: "이탈을 잴 기간이 모자라 상한을 못 냅니다.", state: .unknown)
        }
        let unit = capacity.period.unit
        var answer = "\(unit)마다 새로 \(Int(capacity.averageNew.rounded()))명이 오고 \(percent(capacity.churnRate))가 떠나서, 이대로면 \(capacity.period.activityName) 약 \(Int(ceiling.rounded()))명에서 멈춥니다. 지금 \(capacity.currentActive)명(\(percent(fill)))."
        let state: StatsFinding.State
        var action: String?
        if fill >= 0.9 {
            state = .watch
            answer += " 이미 상한 가까이라 유입을 늘려도 거의 안 오릅니다."
            action = "이탈률 낮추기가 유입보다 먼저"
        } else {
            state = .good
            answer += " 아직 자랄 자리가 있어요."
        }
        return .init(topic: .capacity, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 유료 사용자가 남나

    static func paid(_ split: FeedbackStore.AccessSplit?) -> StatsFinding? {
        guard let split, !split.isEmpty,
              let all = split.all.ratio, let active = split.active7.ratio,
              !split.all.isTooThin else { return nil }
        let question = "유료 기능을 쓰는 사람이 남나?"
        var answer = "전체 설치의 \(percent(all))가 유료 기능을 쓰고, 이번 주에 온 사람 중에서는 \(percent(active))예요."
        let state: StatsFinding.State
        var action: String?
        if active < all * 0.8 {
            state = .bad
            answer += " 유료 사용자가 먼저 빠지고 있어요."
            action = "유료 사용자가 왜 안 오는지 보기(피드백 · 새 버전 크래시)"
        } else if active > all * 1.2 {
            state = .good
            answer += " 남는 사람일수록 유료예요. 돈이 되는 사람이 떠받치고 있어요."
        } else {
            state = .good
            answer += " 비슷하게 남아요."
        }
        return .init(topic: .paid, question: question, answer: answer, state: state, action: action)
    }

    // MARK: - 핵심 흐름 (스펙의 퍼널 · 사다리)

    /// 스펙 카드 한 장의 질문과 답. 모양마다 묻는 것이 다르다.
    static func spec(_ insight: ProjectStatsSpec.Insight) -> StatsFinding? {
        let frame = insight.frame
        switch insight {
        case .tiles:
            return nil
        case .bars(_, let rows):
            let present = rows.filter { !$0.isMissing }
            guard let top = present.max(by: { $0.ratio < $1.ratio }) else { return nil }
            var answer = "'\(top.label)'이 가장 많습니다(\(top.value))."
            if let hot = present.first(where: { $0.tone == .hot }), hot.label != top.label {
                answer += " 지금 손댈 자리는 '\(hot.label)'(\(hot.value))."
            }
            return .init(topic: .flow, question: "\(frame.title) — 어디에 몰려 있나?",
                         answer: answer, state: .unknown, key: frame.id)
        case .funnel(_, let steps, let goal):
            guard let first = steps.first, first.count > 0, let last = steps.last(where: { !$0.isMissing }) else {
                return .init(topic: .flow, question: "\(frame.title) — 어디서 빠지나?",
                             answer: "첫 칸에 아무도 없어 아직 모릅니다.", state: .unknown, key: frame.id)
            }
            var answer = "처음 \(AppFormat.count(first.count))명 중 \(percent(last.ratio))가 '\(last.label)'까지 옵니다."
            let worst = steps.dropFirst()
                .filter { !$0.isMissing && !$0.exceedsPrevious && $0.fromPrevious != nil }
                .min { ($0.fromPrevious ?? 1) < ($1.fromPrevious ?? 1) }
            var worstLabel: String?
            if let worst, let pass = worst.fromPrevious,
               let index = steps.firstIndex(where: { $0.id == worst.id }), index > 0 {
                answer += " 가장 크게 새는 곳은 '\(steps[index - 1].label) → \(worst.label)'이고 \(percent(pass))만 넘어가요."
                worstLabel = worst.label
            }
            // 순서를 건너뛴 사람 — 깔때기에서 뺐으니 몇 명인지 밝힌다.
            if let skip = steps.first(where: { $0.skipped > 0 }),
               let index = steps.firstIndex(where: { $0.id == skip.id }), index > 0 {
                answer += " 앞 칸을 거치지 않고 '\(skip.label)'에 닿은 \(AppFormat.count(skip.skipped))명은 순서가 안 맞아 뺐어요."
            }
            let missing = steps.filter(\.isMissing).map(\.label)
            if !missing.isEmpty {
                answer += " '\(missing.joined(separator: "', '"))' 칸은 앱이 아직 안 보내요."
            }
            // 선이 없으면 한 칸에서 70% 넘게 빠지는 것만 짚는다.
            let worstPass = worst?.fromPrevious ?? 1
            var state: StatsFinding.State = worstPass < 0.3 ? .watch : .good
            if let floor = goal?.floor {
                // 선은 순서 무관 값과 견준다(앱이 선을 그렇게 정의했다). 없으면 깔때기 끝.
                let measured = goal?.reached ?? last.ratio
                state = measured < floor ? .bad : (goal?.target.map { measured < $0 } ?? false) ? .watch : .good
                if let reached = goal?.reached, let label = goal?.label {
                    answer += " 순서와 상관없이 '\(label)'에 닿은 설치는 \(percent(reached))로, 이 앱이 정한 하한 \(percent(floor))"
                    answer += reached < floor ? " 아래예요." : " 위예요."
                } else {
                    answer += " 이 앱이 정한 하한은 \(percent(floor))."
                }
            }
            return .init(topic: .flow, question: "\(frame.title) — 어디서 빠지나?", answer: answer,
                         state: state,
                         action: state == .bad || state == .watch ? worstLabel.map { "'\($0)' 칸 앞을 고치기" } : nil,
                         key: frame.id)
        }
    }

    // MARK: - 새 버전 · 피드백

    static func release(_ report: ReleaseHealth.Report?) -> StatsFinding? {
        guard let report else { return nil }
        let state: StatsFinding.State
        switch report.verdict.level {
        case .red: state = .bad
        case .yellow: state = .watch
        case .green: state = .good
        }
        return .init(topic: .release, question: "새 버전 괜찮나?", answer: report.verdict.headline,
                     state: state, action: state == .bad ? "릴리즈 탭에서 이유부터 보기" : nil)
    }

    static func feedback(pending: Int) -> StatsFinding? {
        guard pending > 0 else { return nil }
        return .init(topic: .feedback, question: "밀린 피드백이 있나?",
                     answer: "확인 안 한 피드백이 \(pending)건 있어요.",
                     state: pending >= 5 ? .bad : .watch, action: "피드백 탭에서 확인 필요 \(pending)건 처리")
    }

    // MARK: - 요약

    /// 나쁜 것부터. 모르는 것은 맨 뒤.
    static func ranked(_ findings: [StatsFinding]) -> [StatsFinding] {
        findings.enumerated().sorted {
            $0.element.state == $1.element.state ? $0.offset < $1.offset : $0.element.state < $1.element.state
        }.map(\.element)
    }

    // MARK: - 형식

    static func percent(_ ratio: Double) -> String {
        let scaled = ratio * 100
        return scaled < 10 && scaled > 0 ? String(format: "%.1f%%", scaled) : String(format: "%.0f%%", scaled.rounded())
    }

    static func signed(_ change: Double) -> String {
        if abs(change) < 0.005 { return "그대로" }
        return (change > 0 ? "▲" : "▼") + percent(abs(change))
    }
}

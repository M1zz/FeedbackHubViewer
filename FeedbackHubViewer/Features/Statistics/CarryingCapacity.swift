//
//  CarryingCapacity.swift
//  FeedbackHubViewer
//
//  성장 상한(carrying capacity) — 지금의 유입 속도와 지금의 이탈률이 계속된다면
//  활동 사용자가 결국 멈추는 자리.
//
//      다음 기간 활동 = 이번 기간 활동 × (1 − 이탈률) + 기간당 신규
//
//  이 식이 더 이상 움직이지 않는 점, 즉 활동 = 활동 × (1 − c) + n 을 풀면
//
//      상한 = 기간당 신규 ÷ 기간 이탈률
//
//  이 숫자가 중요한 이유: 다운로드가 늘어도 이탈률이 그대로면 활동 사용자는 상한 근처에서
//  멈춘다. "이번 주 신규 30명"은 좋아 보이지만 주간 이탈률이 30%라면 그 앱은 100명짜리
//  앱이다. 상한을 올리는 길은 둘뿐이고(유입을 늘리거나 이탈을 줄이거나), 둘 중 어느
//  쪽이 병목인지는 이 두 숫자를 나란히 놓아야 보인다.
//
//  무엇으로 재는가: 활동 사용자는 `UsageRollups`의 일별 installID 집합에서 온다 —
//  이벤트를 보낸 설치. 스냅샷(`UsageSnapshot`)은 설치마다 한 줄을 덮어쓰므로 "지난달에
//  활동했는가"를 되돌아볼 수 없고, 이탈은 정의상 과거와의 비교다. 그래서 유일하게
//  역사가 있는 쪽인 일 버킷 위에서 계산한다.
//
//  그래서 여기서의 "신규"는 App Store 다운로드가 아니라 **그 기간에 처음 활동한 설치**이고,
//  "이탈"은 지난 기간에 활동했는데 이번 기간에는 아무 이벤트도 보내지 않은 설치다.
//  이탈률과 신규가 같은 모집단에서 나오므로 둘의 나눗셈이 뜻을 가진다.
//

import Foundation

struct CarryingCapacity {

    // MARK: - Period

    /// 한 칸의 길이 — 그리고 그 길이가 곧 어떤 활성 사용자의 상한인지를 정한다.
    ///
    /// 칸 하나가 하루면 그 칸의 활동 사용자가 DAU이고, 한 주면 WAU, 한 달이면
    /// MAU다. 그러니 여기서 나오는 상한은 셋을 따로 잰 것이 아니라 **위 활성
    /// 사용자 카드의 그 숫자가 결국 멈추는 자리**다: 일간을 고르면 DAU 상한,
    /// 주간이면 WAU 상한, 월간이면 MAU 상한.
    ///
    /// 셋의 성격은 다르다. 일간은 "매일 오는 사람"의 평형이라 이탈률이 높게
    /// 나오고(하루 쉰 것도 이탈로 잡힌다) 잡음도 크지만, 매일 쓰이는 앱이
    /// 되려는지 알려면 이 칸이라야 한다. 월간은 잡음이 사라지는 대신 여섯 달이
    /// 쌓여야 말을 한다.
    enum Period: String, CaseIterable, Identifiable, Hashable {
        case day, week, month

        var id: String { rawValue }

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            }
        }

        var label: String {
            switch self {
            case .day: return "일간"
            case .week: return "주간"
            case .month: return "월간"
            }
        }

        /// 이 칸의 활동 사용자를 부르는 이름. 상한이 무엇의 상한인지 말할 때 쓴다.
        var activityName: String {
            switch self {
            case .day: return "DAU"
            case .week: return "WAU"
            case .month: return "MAU"
            }
        }

        /// 고르는 자리에 쓰는 이름 — 위 카드와 같은 말로 부른다.
        var pickerLabel: String { "\(label) (\(activityName))" }

        /// 숫자 뒤에 붙는 단위 — "28일", "12주", "3달".
        var unit: String {
            switch self {
            case .day: return "일"
            case .week: return "주"
            case .month: return "달"
            }
        }

        /// 받침에 따라 갈리는 주격 조사 — "14일이", "4주가", "3달이".
        var subjectParticle: String {
            switch self {
            case .day: return "이"
            case .week: return "가"
            case .month: return "이"
            }
        }

        /// 평균을 낼 때 되돌아보는 기간 수. 짧으면 한 번의 사고에 휘둘리고, 길면
        /// 반년 전의 앱을 지금의 앱이라고 말하게 된다. 하루 칸은 주말·평일이
        /// 통째로 들어오도록 4주치를 본다.
        var analysisPeriods: Int {
            switch self {
            case .day: return 28
            case .week: return 8
            case .month: return 6
            }
        }

        /// 이보다 적으면 숫자를 내놓되 "아직 참고용"이라고 말한다.
        var minimumPeriods: Int {
            switch self {
            case .day: return 14
            case .week: return 4
            case .month: return 3
            }
        }

        /// 차트가 그리는 과거 길이.
        var historyPeriods: Int {
            switch self {
            case .day: return 60
            case .week: return 26
            case .month: return 18
            }
        }

        /// 상한을 향해 가는 길을 몇 칸 앞까지 그릴지.
        var projectionPeriods: Int {
            switch self {
            case .day: return 30
            case .week: return 12
            case .month: return 9
            }
        }
    }

    // MARK: - Points

    /// 한 기간의 사용자 회계. 활동 = 유지 + 신규 + 돌아온 사용자이고, 이탈은 지난
    /// 기간에 있었으나 이번에 없는 쪽이다.
    struct Point: Identifiable {
        var id: Date { start }
        let start: Date
        /// 이 기간에 이벤트를 보낸 서로 다른 설치 수.
        let active: Int
        /// 그중 이 허브에서 **처음** 활동한 설치.
        let new: Int
        /// 지난 기간에도 활동했던 설치.
        let retained: Int
        /// 지난 기간에 활동했으나 이번 기간에는 사라진 설치.
        let churned: Int
        let previousActive: Int
        /// 아직 끝나지 않은 기간. 숫자가 덜 찼으므로 평균에도 차트 선에도 넣지 않는다.
        let isPartial: Bool
        /// 기록이 시작된 첫 기간. 그때는 모두가 "처음 활동"이라 신규가 실제 유입이
        /// 아니라 그동안 쌓인 것 전부다 — 평균에서 뺀다.
        let isBaseline: Bool

        /// 지난 기간 대비 이탈률. 비교할 지난 기간이 없으면 nil.
        var churnRate: Double? {
            previousActive > 0 ? Double(churned) / Double(previousActive) : nil
        }

        /// 신규도 유지도 아닌 쪽 — 쉬었다 돌아온 설치.
        var returning: Int { max(0, active - new - retained) }
    }

    /// 전망선의 한 점. 실제로 관측된 값이 아니라 식이 그리는 자리다.
    struct Projected: Identifiable {
        var id: Date { date }
        let date: Date
        let active: Double
    }

    // MARK: - Result

    let period: Period
    /// 차트가 그리는 과거(오래된 것부터). 마지막 칸은 진행 중일 수 있다.
    let history: [Point]
    /// 평균을 실제로 낸 기간 수.
    let sampleCount: Int
    /// 기간당 새로 활동을 시작한 설치 수의 평균.
    let averageNew: Double
    /// 기간 이탈률 — 창 전체의 이탈 합 ÷ 직전 활동 합. 기간마다의 비율을 다시 평균
    /// 내면 활동이 3명뿐이던 주가 300명이던 주와 같은 무게를 갖는다.
    let churnRate: Double
    /// 관측된 이탈률이 0이거나 비교할 과거가 없으면 nil — 상한은 계산되지 않는다.
    let capacity: Double?
    /// 마지막으로 **끝난** 기간의 활동 사용자.
    let currentActive: Int
    let projection: [Projected]
    /// 이 숫자를 믿을 때 알아야 할 것들. 비어 있으면 특별히 걸리는 게 없다는 뜻이다.
    let caveats: [String]

    /// 상한 대비 지금 자리(0~). 1에 가까우면 이미 이 앱의 평형에 도달했다는 뜻이고,
    /// 그때부터는 유입을 늘려도 이탈률이 그대로면 거의 오르지 않는다.
    var fill: Double? {
        guard let capacity, capacity > 0 else { return nil }
        return Double(currentActive) / capacity
    }

    /// 한 사용자가 활동을 이어 가는 평균 기간 수(1 ÷ 이탈률).
    var averageLifetime: Double? {
        churnRate > 0 ? 1 / churnRate : nil
    }

    /// 상한이 지금보다 위인가 — 아직 자랄 자리가 남았는가.
    var hasHeadroom: Bool? {
        guard let capacity else { return nil }
        return capacity > Double(currentActive)
    }

    // MARK: - Measuring

    /// 일 버킷에서 상한을 잰다. `days`는 `UsageRollups.days(for:excluding:)`가 준
    /// 하루→버킷 지도이고, 여기서 쓰는 것은 그 안의 installID 집합뿐이다.
    ///
    /// 활동이 한 번도 없었으면 nil — 잴 것이 없다는 것과 0이라는 것은 다른 말이다.
    static func measure(days: [String: UsageDayBucket],
                        period: Period,
                        calendar: Calendar = .current,
                        now: Date = Date()) -> CarryingCapacity? {

        // 하루씩 모아 기간 칸으로. 합집합이다 — 월·화에 모두 쓴 설치는 한 명이다.
        var installsByPeriod: [Date: Set<String>] = [:]
        for (key, bucket) in days where !bucket.installs.isEmpty {
            guard let date = UsageRollups.date(fromDayKey: key, calendar: calendar),
                  let start = calendar.dateInterval(of: period.component, for: date)?.start
            else { continue }
            installsByPeriod[start, default: []].formUnion(bucket.installs)
        }

        guard let first = installsByPeriod.keys.min(),
              let currentStart = calendar.dateInterval(of: period.component, for: now)?.start,
              first <= currentStart
        else { return nil }

        // 활동이 없던 기간도 칸을 차지해야 한다. 비워 두면 이탈이 일어난 적이 없는
        // 것처럼 보이고, 수집이 멈춘 구간이 조용히 사라진다.
        var points: [Point] = []
        var seen: Set<String> = []
        var previous: Set<String> = []
        var cursor = first
        // 추이 차트와 같은 안전 정지선.
        while cursor <= currentStart && points.count < 400 {
            let active = installsByPeriod[cursor] ?? []
            let retained = active.intersection(previous).count
            points.append(Point(start: cursor,
                                active: active.count,
                                new: active.subtracting(seen).count,
                                retained: retained,
                                churned: previous.count - retained,
                                previousActive: previous.count,
                                isPartial: cursor == currentStart,
                                isBaseline: points.isEmpty))
            seen.formUnion(active)
            previous = active
            guard let next = calendar.date(byAdding: period.component, value: 1, to: cursor) else { break }
            cursor = next
        }

        // 평균을 내는 창: 끝난 기간만, 그리고 첫 기간은 빼고. 첫 기간의 "신규"는
        // 유입이 아니라 그 앱의 그때까지의 전부다.
        let usable = points.filter { !$0.isPartial && !$0.isBaseline }
        let window = Array(usable.suffix(period.analysisPeriods))

        let churnedTotal = window.reduce(0) { $0 + $1.churned }
        let previousTotal = window.reduce(0) { $0 + $1.previousActive }
        let newTotal = window.reduce(0) { $0 + $1.new }
        let churnRate = previousTotal > 0 ? Double(churnedTotal) / Double(previousTotal) : 0
        let averageNew = window.isEmpty ? 0 : Double(newTotal) / Double(window.count)
        let capacity = churnRate > 0 ? averageNew / churnRate : nil
        let currentActive = points.last(where: { !$0.isPartial })?.active ?? 0

        return CarryingCapacity(
            period: period,
            history: Array(points.suffix(period.historyPeriods)),
            sampleCount: window.count,
            averageNew: averageNew,
            churnRate: churnRate,
            capacity: capacity,
            currentActive: currentActive,
            projection: project(from: currentActive,
                                startingAfter: points.last(where: { !$0.isPartial })?.start,
                                averageNew: averageNew,
                                churnRate: churnRate,
                                period: period,
                                calendar: calendar),
            caveats: caveats(window: window,
                             previousTotal: previousTotal,
                             churnRate: churnRate,
                             averageNew: averageNew,
                             period: period))
    }

    /// 평형으로 다가가는 길. 첫 점은 마지막으로 끝난 기간 그 자체라서 전망선이
    /// 실제 선에 이어 붙는다.
    private static func project(from active: Int,
                                startingAfter start: Date?,
                                averageNew: Double,
                                churnRate: Double,
                                period: Period,
                                calendar: Calendar) -> [Projected] {
        guard let start, churnRate > 0 else { return [] }
        var points = [Projected(date: start, active: Double(active))]
        var value = Double(active)
        var cursor = start
        for _ in 0..<period.projectionPeriods {
            guard let next = calendar.date(byAdding: period.component, value: 1, to: cursor) else { break }
            value = value * (1 - churnRate) + averageNew
            points.append(Projected(date: next, active: max(0, value)))
            cursor = next
        }
        return points
    }

    /// 숫자를 내놓되, 그 숫자가 어디서 흔들리는지도 같이 내놓는다.
    private static func caveats(window: [Point],
                                previousTotal: Int,
                                churnRate: Double,
                                averageNew: Double,
                                period: Period) -> [String] {
        var notes: [String] = []

        if window.isEmpty {
            notes.append("비교할 지난 기간이 아직 없습니다. \(period.minimumPeriods)\(period.unit)\(period.subjectParticle) 지나면 계산됩니다.")
            return notes
        }
        if window.count < period.minimumPeriods {
            notes.append("관측이 \(window.count)\(period.unit)치뿐이라 아직 참고용입니다 — \(period.minimumPeriods)\(period.unit) 이상 쌓이면 안정됩니다.")
        }
        if previousTotal == 0 {
            notes.append("직전 기간에 활동한 설치가 없어 이탈률을 잴 수 없습니다.")
        } else if churnRate <= 0 {
            notes.append("이 구간에서 이탈이 한 번도 관측되지 않았습니다. 아무도 떠나지 않으면 상한은 무한대이므로 숫자를 내지 않습니다.")
        }
        // 활동이 아예 없던 기간은 위에서 따로 말한다. 여기서 보려는 것은 "사람이
        // 몇 안 되는 앱"이고, 0을 섞으면 그 최솟값이 언제나 0이 되어 못 본다.
        if let smallest = window.map(\.previousActive).filter({ $0 > 0 }).min(), smallest < 5 {
            notes.append("활동 사용자가 한 자릿수인 기간이 있습니다. 한 사람의 이탈이 이탈률을 크게 흔듭니다.")
        }
        if window.contains(where: { $0.active == 0 }) {
            notes.append("활동이 0인 기간이 섞여 있습니다. 실제로 아무도 안 썼거나 수집이 멈춘 것이고, 어느 쪽이든 이탈률이 부풀려집니다.")
        }
        // 하루 칸에서는 이탈률이 원래 높다. 그 사실을 안 적으면 "사용자의 80%가
        // 떠난다"로 읽히는데, 실제로 일어난 일은 대부분 "오늘은 안 열었다"이다.
        if period == .day {
            notes.append("하루 단위에서는 '어제 썼는데 오늘 안 썼다'가 전부 이탈로 잡힙니다. 떠난 게 아니라 매일 쓰지는 않는 것이라, 여기 이탈률은 높게 나오는 게 정상이고 DAU 상한은 '안 떠난 사람 수'가 아니라 **매일 오는 사람 수**의 평형입니다.")
        }
        if averageNew == 0 && churnRate > 0 {
            notes.append("이 구간에 새로 활동을 시작한 설치가 없습니다. 유입이 0이면 상한도 0 — 지금 사용자가 빠져나가는 만큼 줄어듭니다.")
        }
        return notes
    }
}

//
//  FeedbackStore+Audience.swift
//  FeedbackHubViewer
//
//  같은 통계 화면을 한 무리에만 맞춰 다시 그리는 장치 — 전체 · 유료기능 · 무료기능.
//
//  왜 필요한가: 평균은 여러 무리를 섞은 값이라 어느 쪽도 설명하지 못한다. 유료
//  기능을 쓸 수 있는 사람이 얼마나 자주 오는지, 무료 범위에서 쓰는 사람이 어디까지
//  쓰다 멈추는지는 각각을 따로 놓고 봐야 나온다.
//
//  ── 이 화면이 두 번 틀렸고, 두 번 다 같은 이유였다 ──
//
//  처음엔 앱이 보낸 0/1 하나를 **결제**로 읽었다. 그런데 한 앱이 그 자리에
//  "지금 기능이 열려 있는가"(결제 ∪ 그랜드파더 ∪ 체험 ∪ 내부 빌드)를 실어
//  보냈고, 신규 설치의 99%가 유료로 기록됐다. 그래서 규약을 셋으로 나누고
//  (`flag.isPaid` · `flag.isTrial` · `flag.isComped`), 그 셋을 안 보내는 설치는
//  어느 띠에도 안 넣기로 했다. 이번엔 8,201대 중 5,726대가 **모름**이 됐다.
//
//  둘 다 같은 잘못이었다 — **가진 값에 안 맞는 질문을 물었다.** 앱이 보내는
//  0/1이 실제로 재는 것은 "지금 쓸 수 있는가"지 "돈을 냈는가"가 아니다. 그 값을
//  결제로 읽으면 거짓이 되고, 결제만 물으면 대부분이 모름이 된다. 질문을 값에
//  맞추면 둘 다 아니다:
//
//      유료기능 / 무료기능  — 지금 유료 기능을 쓸 수 있는가
//
//  이 질문에는 거의 모든 앱이 이미 답하고 있어서 모름이 52대(0.6%)로 줄었다.
//  옛 이름(`flag.isPro` 등)도 버릴 것이 아니라 제자리를 찾아 준 것이다 —
//  결제 자리에선 거짓말이지만 "쓸 수 있는가" 자리에선 참이다.
//
//  왜 결제·체험·무상까지 안 쪼개는가: 쪼개 봤는데 그 셋을 말해 주는 앱이 거의
//  없었다. 대부분의 칸이 비거나 "아는 일부만 놓고 센 값"이라는 단서가 줄줄이
//  붙었고, 그러면 고르개가 고를 수 없는 것을 고르게 한다.
//
//  실측이 그 말을 뒷받침한다: ClipKeyboard의 무료 한도는 단축어 10개인데, 한도를
//  넘긴 65대는 **전부** `flag.isPro`가 켜져 있었고(앞뒤가 맞는다), 한도 안에서
//  쓰는 5,690대 중에서도 5,654대가 켜져 있었다. 결제라면 설명이 안 되지만,
//  접근이라면 설명이 된다 — 5.0.0부터 모두에게 열어 둔 것이다.
//
//  그리고 —
//
//   · 권한을 **안 보내는 설치는 어느 쪽에도 들어가지 않는다.** "무료기능"으로 세면
//     없는 사실을 지어내는 것이다. 이 판단은 앱이 아니라 **설치 하나하나**에
//     대해서 한다 — 한 앱 안에서도 버전 세대는 섞이고, 앱을 단위로 보면 새 키를
//     보내는 36대 때문에 구버전 5,710대가 통째로 뒤집힌다(실제로 그랬다).
//
//   · **건수(events)는 무리별로 가를 수 없다.** 일 버킷은 그날의 건수와 그날
//     활동한 `installID` 집합을 따로 들고 있을 뿐, 설치별 건수를 들고 있지 않다
//     (`UsageDayBucket`). 사람 수는 집합의 교집합으로 정확히 갈리지만 건수는
//     못 나눈다. 그래서 걸러 낸 버킷의 `events`는 0이고, 화면은 무리를 고른
//     동안 건수를 **아예 보여주지 않는다** — 전체 건수를 그대로 두면 사람 수는
//     유료기능인데 건수는 전체인 한 장이 되어, 둘을 나눈 값이 전부 거짓말이 된다.
//
//  ── 두 번째 축: 돈을 낸 방식 ──
//
//  위에서 결제·체험·무상을 버린 이유는 "그 셋을 말해 주는 앱이 거의 없어서"였다.
//  그래서 그 축은 **없애지 않고 따로 세웠다** — 접근 축(유료기능 · 무료기능)은
//  거의 모든 앱에서 뜨고, 결제 축은 `flag.isPaid`를 보내는 설치에서만 뜬다. 한
//  고르개에 섞으면 대부분의 앱에서 빈 칸이 줄줄이 생기지만, 줄을 나누면 결제 줄은
//  말할 수 있는 앱에서만 나타난다.
//
//      Pro 결제 · 옛 유료 구매 · 부가 결제 · 체험 · 무상 · 안 냄
//
//  한 설치는 **하나에만** 든다. 돈에 가까운 쪽이 이긴다 — Pro를 샀으면 체험 중이어도
//  Pro 결제, 칸만 샀으면 체험 중이어도 부가 결제다. 옛 유료 구매는 앱이 유료 다운로드였던
//  시절에 산 사람이라 돈은 냈지만 지금의 인앱 결제와 무관하다 — Pro 결제에 섞이면 매출과
//  대조할 때 전환율이 부푼다(`flag.isLegacyPaid`). 무상은 돈 없이 열린 사람
//  (그랜드파더·가족 공유·내부 빌드)이고, 안 냄은 아무것도 해당하지 않는 사람이다.
//
//  기준은 `flag.isPaid` 하나다. 그 키를 안 보낸 설치는 이 축에서 **모름**이다 —
//  접근 축에서 무료기능이어도 결제 축에서 "안 냄"으로 세지 않는다. 부가 결제
//  (`flag.boughtAddOn`)와 옛 유료 구매(`flag.isLegacyPaid`)는 늦게 생긴 키라, 안 보내는
//  설치는 각각 안 냄 · Pro 결제에 들어가되 그 수를 고르개 밑에 적는다 — 거기 섞여 있을 수
//  있다는 뜻이다.
//
//  설치·사람 수 쪽은 전부 정확하다: 스냅샷은 설치 하나가 한 줄이고, 일 버킷의
//  설치 집합과 교집합을 잡으면 그 무리가 그날 몇 명 왔는지가 그대로 나온다.
//

import Foundation

extension FeedbackStore {

    // MARK: - 무리

    /// 통계를 어느 무리에 맞춰 볼 것인가.
    ///
    /// 두 축이다(머리말). 접근 축 — 전체 · 유료기능 · 무료기능 — 은 권한을 보내는
    /// 거의 모든 앱에서 뜨고, 결제 축 — Pro 결제 · 옛 유료 구매 · 부가 결제 · 체험 · 무상 · 안 냄 —
    /// 은 `flag.isPaid`를 보내는 앱에서만 뜬다.
    enum Audience: String, CaseIterable, Identifiable, Hashable {
        /// 권한을 안 보내는 설치까지 포함한, 있는 그대로의 전부.
        case all
        /// 유료 기능을 쓸 수 있는 설치.
        case paidFeatures
        /// 무료 기능만 쓰고 있는 설치.
        case freeFeatures

        /// 유료 기능을 여는 결제가 지금 유효한 설치.
        case paying
        /// 앱이 유료 다운로드였던 시절에 사서 열린 설치. 돈은 냈지만 지금 매출과 무관하다.
        case legacyPaid
        /// 기능을 열지 않는 작은 결제만 한 설치(칸 추가 · 두 대째 같은 것).
        case addOn
        /// 결제 없이 체험 기간 중인 설치.
        case trial
        /// 돈 없이 열린 설치 — 그랜드파더 · 가족 공유 · 내부 빌드.
        case comped
        /// 위 어느 것에도 해당하지 않는 설치.
        case unpaid

        enum Axis { case access, payment }

        var id: String { rawValue }

        var axis: Axis {
            switch self {
            case .all, .paidFeatures, .freeFeatures: return .access
            case .paying, .legacyPaid, .addOn, .trial, .comped, .unpaid: return .payment
            }
        }

        static let accessCases: [Audience] = [.all, .paidFeatures, .freeFeatures]
        /// 결제 축의 차례 — 돈에 가까운 쪽부터. 한 설치가 여럿에 해당하면 앞의 것이 이긴다.
        static let paymentCases: [Audience] = [.paying, .legacyPaid, .addOn, .trial, .comped, .unpaid]

        var label: String {
            switch self {
            case .all:          return "전체"
            case .paidFeatures: return "유료기능"
            case .freeFeatures: return "무료기능"
            case .paying:       return "Pro 결제"
            case .legacyPaid:   return "옛 유료 구매"
            case .addOn:        return "부가 결제"
            case .trial:        return "체험"
            case .comped:       return "무상"
            case .unpaid:       return "안 냄"
            }
        }

        /// 고르개 밑줄에서 이 무리가 무엇인지 한 마디로.
        var blurb: String {
            switch self {
            case .all:          return "있는 그대로의 전부"
            case .paidFeatures: return "유료 기능을 쓸 수 있는 설치"
            case .freeFeatures: return "무료 기능만 쓰고 있는 설치"
            case .paying:       return "유료 기능을 여는 결제가 유효한 설치"
            case .legacyPaid:   return "앱이 유료 다운로드였던 시절에 사서 열린 설치"
            case .addOn:        return "기능은 안 열리는 작은 결제만 한 설치"
            case .trial:        return "결제 없이 체험 중인 설치"
            case .comped:       return "돈 없이 열린 설치(그랜드파더·가족 공유·내부 빌드)"
            case .unpaid:       return "아무 결제도 체험도 없는 설치"
            }
        }

        /// 설치를 골라 내는가. 이게 참인 동안은 건수를 말할 수 없다(위 머리말).
        var isFiltered: Bool { self != .all }
    }

    /// 한 범위에서 갈린 설치 ID. 축마다 서로 겹치지 않는다.
    struct AudienceInstalls {
        var paidFeatures: Set<String> = []
        var freeFeatures: Set<String> = []
        /// 권한을 말해 주는 키를 하나도 안 보낸 설치.
        /// "무료기능"이 아니라 **모름**이다.
        var unknown: Set<String> = []

        /// 결제 축. 키는 `Audience.paymentCases` 중 하나.
        var payment: [Audience: Set<String>] = [:]
        /// 결제 축에서 모름 — `flag.isPaid`를 안 보낸 설치.
        var paymentUnknown: Set<String> = []
        /// 칸에 들었지만 그 칸을 가르는 늦게 생긴 키를 안 보낸 설치 — 다른 칸의 사람이 섞였을 수
        /// 있다. 안 냄에는 부가 결제가, Pro 결제에는 옛 유료 구매가 섞일 수 있다.
        var unreported: [Audience: Set<String>] = [:]

        /// 갈린 설치 수 — 이 화면이 덮고 있는 범위.
        var known: Int { paidFeatures.count + freeFeatures.count }
        /// 결제 축에서 갈린 설치 수.
        var paymentKnown: Int { payment.values.reduce(0) { $0 + $1.count } }

        /// `nil`이면 거르지 않는다(전체).
        func ids(for audience: Audience) -> Set<String>? {
            switch audience {
            case .all:          return nil
            case .paidFeatures: return paidFeatures
            case .freeFeatures: return freeFeatures
            case .paying, .legacyPaid, .addOn, .trial, .comped, .unpaid:
                return payment[audience] ?? []
            }
        }

        func count(for audience: Audience) -> Int {
            ids(for: audience)?.count ?? (known + unknown.count)
        }
    }

    /// 이 범위의 설치를 갈라 놓은 것.
    /// 전체 프로젝트에서는 앱마다 키가 다르므로 앱별로 갈라 모은다.
    func audienceInstalls(for project: String?) -> AudienceInstalls {
        memoized(\.audienceInstalls, project) {
            var result = AudienceInstalls()
            for key in project.map({ [$0] }) ?? allProjectKeys {
                // 권한을 아예 못 읽는 앱의 설치도 모름에 넣는다 — 그래야
                // `known + unknown`이 이 범위의 설치 수와 맞고, 화면이 얼마를
                // 덮고 있는지를 어림이 아니라 셈으로 말할 수 있다.
                guard let entitlement = entitlement(for: key) else {
                    for snapshot in snapshots(for: key) {
                        result.unknown.insert(snapshot.installID)
                        result.paymentUnknown.insert(snapshot.installID)
                    }
                    continue
                }
                for snapshot in snapshots(for: key) {
                    let id = snapshot.installID
                    switch entitlement.isUnlocked(snapshot) {
                    case true?:  result.paidFeatures.insert(id)
                    case false?: result.freeFeatures.insert(id)
                    case nil:    result.unknown.insert(id)
                    }
                    if let kind = entitlement.paymentKind(snapshot) {
                        result.payment[kind, default: []].insert(id)
                        if !entitlement.reportsSplit(of: kind, snapshot) {
                            result.unreported[kind, default: []].insert(id)
                        }
                    } else {
                        result.paymentUnknown.insert(id)
                    }
                }
            }
            return result
        }
    }

    /// 이 무리에 드는 설치 ID. `nil`은 "거르지 않는다"이지 "아무도 없다"가 아니다.
    func installIDs(for project: String?, audience: Audience) -> Set<String>? {
        guard audience.isFiltered else { return nil }
        return audienceInstalls(for: project).ids(for: audience)
    }

    /// 이 범위에서 결제 축으로 가를 수 있는가 — `flag.isPaid`를 보낸 설치가 하나라도 있는가.
    func canSplitByPayment(for project: String?) -> Bool {
        audienceInstalls(for: project).paymentKnown > 0
    }

    /// 이 범위에서 무리를 가를 수 있는가 — 권한을 읽을 수 있는 앱이 하나라도 있는가.
    /// 못 가르는 앱에서는 고르개 자체를 띄우지 않는다: 고를 수 없는 것을 고르게
    /// 하는 것보다, 왜 못 가르는지 카드 하나가 말해 주는 편이 낫다(`accessCard`).
    func canSplitByAudience(for project: String?) -> Bool {
        audienceInstalls(for: project).known > 0
    }

    // MARK: - 걸러 낸 입력

    /// 이 무리의 스냅샷. 지표·분포·앱별 스펙이 전부 여기서 나온다.
    func snapshots(for project: String?, audience: Audience) -> [UsageSnapshot] {
        let all = snapshots(for: project)
        guard let ids = installIDs(for: project, audience: audience) else { return all }
        return all.filter { ids.contains($0.installID) }
    }

    /// 이 무리의 일 버킷. 설치 집합은 교집합으로 정확히 갈리고, 건수는 0이 된다
    /// (머리말). 아무도 안 남는 날은 통째로 빠지므로 "그 무리가 없던 날"이 0으로
    /// 남지 않는다.
    func days(for project: String?, audience: Audience) -> [String: UsageDayBucket] {
        let days = rollups.days(for: project, excluding: hiddenProjects)
        guard let ids = installIDs(for: project, audience: audience) else { return days }
        return days.compactMapValues { bucket in
            let installs = bucket.installs.intersection(ids)
            guard !installs.isEmpty else { return nil }
            var filtered = bucket
            filtered.installs = installs
            filtered.events = 0
            filtered.byEvent = [:]
            return filtered
        }
    }

    /// 사다리 한 칸(주·달·해)을 같은 방식으로 거른 것.
    func periodBuckets(_ granularity: UsageRollups.Granularity,
                       for project: String?,
                       audience: Audience) -> [String: UsagePeriodBucket] {
        let buckets = rollups.buckets(granularity, for: project, excluding: hiddenProjects)
        guard let ids = installIDs(for: project, audience: audience) else { return buckets }
        return buckets.compactMapValues { bucket in
            let installs = bucket.installs.intersection(ids)
            guard !installs.isEmpty else { return nil }
            var filtered = bucket
            filtered.installs = installs
            filtered.events = 0
            return filtered
        }
    }

    /// 이벤트 이름별 전 기간 합계를, 이 무리의 설치만 남겨서.
    ///
    /// 한 명도 안 남는 이름도 **지우지 않는다**: 퍼널은 "이 앱이 그 이벤트를 아예
    /// 안 보낸다"와 "이 무리에서 아무도 안 했다"를 다르게 그리는데, 지워 버리면
    /// 뒤엣것이 앞엣것으로 보인다(`Insight.Step.isMissing`).
    func eventTotals(for project: String?, audience: Audience) -> [String: UsageNameTotal] {
        let totals = rollups.totals(for: project, excluding: hiddenProjects)
        guard let ids = installIDs(for: project, audience: audience) else { return totals }
        return totals.mapValues { total in
            var filtered = total
            filtered.installs = total.installs.intersection(ids)
            filtered.count = 0
            return filtered
        }
    }
}

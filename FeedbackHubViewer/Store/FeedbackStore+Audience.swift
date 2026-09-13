//
//  FeedbackStore+Audience.swift
//  FeedbackHubViewer
//
//  같은 통계 화면을 한 무리에만 맞춰 다시 그리는 장치 — 전체 · 유료 · 체험 · 무상 · 무료.
//
//  왜 필요한가: 평균은 여러 무리를 섞은 값이라 어느 쪽도 설명하지 못한다. 돈을 낸
//  사람이 얼마나 자주 오는지, 무료 사용자가 어디까지 쓰다 멈추는지는 각각을 따로
//  놓고 봐야 나온다.
//
//  한때 이 화면은 유료·무료 **둘**로만 갈랐고, 가르는 근거도 앱이 보낸 0/1 하나였다.
//  그게 조용히 틀렸다: 한 앱이 그 자리에 "지금 기능이 열려 있는가"(결제 ∪ 그랜드파더
//  ∪ 체험 ∪ 내부 빌드)를 실어 보냈고, 신규 설치의 99%가 유료로 기록됐다. 플래그
//  하나로는 **돈을 냈다**와 **열려 있다**를 구분할 수 없다 — 이름이 `isPro`여도
//  마찬가지다. 그래서 규약을 셋으로 나눈다(`FeedbackStore.EntitlementFlag`):
//
//      flag.isPaid    지금 유효한 결제가 있는가 — 이것만 매출과 이어진다
//      flag.isTrial   체험 기간 중인가 — 아직 안 냈고, 곧 결정할 사람
//      flag.isComped  돈 안 내고 열린 접근인가 — 그랜드파더·프로모션·가족 공유·테스터
//
//  띠는 서로 겹치지 않게 **유료 > 무상 > 체험 > 무료** 차례로 정한다. 무상이 체험보다
//  앞서는 이유: 무상은 영구 면제라 체험이 끝나도 그대로다. "왜 돈을 안 내고 쓰는가"에
//  답하는 쪽이 무상이므로, 둘 다 켜져 있으면 무상이 그 사람을 더 잘 설명한다.
//
//  그리고 —
//
//   · 권한을 **안 보내는 앱의 설치는 어느 띠에도 들어가지 않는다.** 무료로 세면
//     없는 사실을 지어내는 것이다. 띠의 합 < 전체가 정상이고, 화면은 얼마나
//     덮고 있는지(`AudienceInstalls.known`)를 적는다.
//
//   · **건수(events)는 무리별로 가를 수 없다.** 일 버킷은 그날의 건수와 그날
//     활동한 `installID` 집합을 따로 들고 있을 뿐, 설치별 건수를 들고 있지 않다
//     (`UsageDayBucket`). 사람 수는 집합의 교집합으로 정확히 갈리지만 건수는
//     못 나눈다. 그래서 걸러 낸 버킷의 `events`는 0이고, 화면은 무리를 고른
//     동안 건수를 **아예 보여주지 않는다** — 전체 건수를 그대로 두면 사람 수는
//     유료인데 건수는 전체인 한 장이 되어, 둘을 나눈 값이 전부 거짓말이 된다.
//
//  설치·사람 수 쪽은 전부 정확하다: 스냅샷은 설치 하나가 한 줄이고, 일 버킷의
//  설치 집합과 교집합을 잡으면 그 무리가 그날 몇 명 왔는지가 그대로 나온다.
//

import Foundation

extension FeedbackStore {

    // MARK: - 무리

    /// 통계를 어느 무리에 맞춰 볼 것인가.
    ///
    /// `allCases` 차례는 화면의 고르개 차례이자 "결제에 가까운 순서"다 —
    /// 전체 · 유료 · 체험 · 무상 · 무료.
    enum Audience: String, CaseIterable, Identifiable, Hashable {
        /// 권한을 안 보내는 앱까지 포함한, 있는 그대로의 전부.
        case all
        /// 지금 유효한 결제가 있는 설치.
        case paid
        /// 체험 기간 중인 설치 — 아직 안 냈고, 곧 결정한다.
        case trial
        /// 돈을 안 내고 접근이 열린 설치 — 그랜드파더·프로모션·가족 공유·테스터.
        case comped
        /// 권한을 보내는 앱에서, 위 어느 것도 아닌 설치.
        case free

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:    return "전체"
            case .paid:   return "유료"
            case .trial:  return "체험"
            case .comped: return "무상"
            case .free:   return "무료"
            }
        }

        /// 고르개 밑줄에서 이 띠가 무엇인지 한 마디로.
        var blurb: String {
            switch self {
            case .all:    return "있는 그대로의 전부"
            case .paid:   return "지금 유효한 결제가 있는 설치"
            case .trial:  return "체험 기간 중이라 아직 결제하지 않은 설치"
            case .comped: return "그랜드파더·프로모션·가족 공유처럼 돈을 안 내고 열린 설치"
            case .free:   return "권한이 열리지 않은 설치"
            }
        }

        /// 설치를 골라 내는가. 이게 참인 동안은 건수를 말할 수 없다(위 머리말).
        var isFiltered: Bool { self != .all }
    }

    /// 한 범위에서 띠별로 갈린 설치 ID.
    ///
    /// 네 집합은 서로 겹치지 않는다 — 한 설치는 한 띠에만 들어간다.
    struct AudienceInstalls {
        var paid: Set<String> = []
        var trial: Set<String> = []
        var comped: Set<String> = []
        var free: Set<String> = []

        /// 권한을 보내는 앱의 설치 수 — 이 화면이 덮고 있는 범위.
        var known: Int { paid.count + trial.count + comped.count + free.count }

        /// 체험·무상을 실제로 보내는 앱이 있는가. 없으면 그 띠는 고르개에서 뺀다 —
        /// 아무도 없는 칸을 눌러 보게 하면 "체험자가 0명"으로 읽힌다.
        var hasTrialBand = false
        var hasCompedBand = false

        /// `nil`이면 거르지 않는다(전체).
        func ids(for audience: Audience) -> Set<String>? {
            switch audience {
            case .all:    return nil
            case .paid:   return paid
            case .trial:  return trial
            case .comped: return comped
            case .free:   return free
            }
        }

        func count(for audience: Audience) -> Int {
            ids(for: audience)?.count ?? known
        }

        /// 이 범위에서 눌러 볼 만한 띠 — 실제로 누군가 들어 있는 칸만.
        var available: [Audience] {
            var result: [Audience] = [.all, .paid]
            if hasTrialBand { result.append(.trial) }
            if hasCompedBand { result.append(.comped) }
            result.append(.free)
            return result
        }
    }

    /// 이 범위의 설치를 띠로 갈라 놓은 것. 권한을 보내는 앱의 설치만 들어간다.
    /// 전체 프로젝트에서는 앱마다 키가 다르므로 앱별로 갈라 모은다.
    func audienceInstalls(for project: String?) -> AudienceInstalls {
        memoized(\.audienceInstalls, project) {
            var result = AudienceInstalls()
            for key in project.map({ [$0] }) ?? allProjectKeys {
                guard let entitlement = entitlement(for: key) else { continue }
                if entitlement.trial != nil { result.hasTrialBand = true }
                if entitlement.comped != nil { result.hasCompedBand = true }
                for snapshot in snapshots(for: key) {
                    switch entitlement.band(of: snapshot) {
                    case .paid:   result.paid.insert(snapshot.installID)
                    case .trial:  result.trial.insert(snapshot.installID)
                    case .comped: result.comped.insert(snapshot.installID)
                    case .free:   result.free.insert(snapshot.installID)
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

    /// 이 범위에서 띠를 가를 수 있는가 — 권한을 보내는 앱이 하나라도 있는가.
    /// 못 가르는 앱에서는 고르개 자체를 띄우지 않는다: 고를 수 없는 것을 고르게
    /// 하는 것보다, 왜 못 가르는지 카드 하나가 말해 주는 편이 낫다(`paidCard`).
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

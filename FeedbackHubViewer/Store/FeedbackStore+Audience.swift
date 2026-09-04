//
//  FeedbackStore+Audience.swift
//  FeedbackHubViewer
//
//  같은 통계 화면을 한 무리에만 맞춰 다시 그리는 장치 — 전체 · 유료 · 무료.
//
//  왜 필요한가: 평균은 두 무리를 섞은 값이라 어느 쪽도 설명하지 못한다. 돈을 낸
//  사람이 얼마나 자주 오는지, 무료 사용자가 어디까지 쓰다 멈추는지는 각각을 따로
//  놓고 봐야 나온다. `paidSplit`은 "몇 대 몇"까지만 말해 주고, 그다음 질문
//  ("유료 사용자의 DAU는?", "무료 사용자는 어느 버전에 몰려 있지?")에는 답하지
//  못했다.
//
//  가르는 근거는 하나뿐이다: 앱이 스냅샷 `metrics`에 실어 보낸 0/1 플래그
//  (`flag.isPro` 같은 것, `FeedbackStore.paidFlagKey`). 그래서 —
//
//   · 유료 여부를 **안 보내는 앱의 설치는 어느 쪽에도 들어가지 않는다.** 무료로
//     세면 없는 사실을 지어내는 것이다. 유료 + 무료 < 전체가 정상이고, 화면은
//     얼마나 덮고 있는지(`AudienceInstalls.known`)를 적는다.
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
    enum Audience: String, CaseIterable, Identifiable, Hashable {
        /// 유료 여부를 안 보내는 앱까지 포함한, 있는 그대로의 전부.
        case all
        /// 앱이 유료라고 표시해 보낸 설치.
        case paid
        /// 유료 여부를 보내는 앱에서, 유료가 아닌 설치.
        case free

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:  return "전체"
            case .paid: return "유료"
            case .free: return "무료"
            }
        }

        /// 설치를 골라 내는가. 이게 참인 동안은 건수를 말할 수 없다(위 머리말).
        var isFiltered: Bool { self != .all }
    }

    /// 한 범위에서 유료·무료로 갈린 설치 ID.
    struct AudienceInstalls {
        var paid: Set<String> = []
        var free: Set<String> = []

        /// 유료 여부를 보내는 앱의 설치 수 — 이 화면이 덮고 있는 범위.
        var known: Int { paid.count + free.count }

        /// `nil`이면 거르지 않는다(전체).
        func ids(for audience: Audience) -> Set<String>? {
            switch audience {
            case .all:  return nil
            case .paid: return paid
            case .free: return free
            }
        }
    }

    /// 이 범위의 설치를 유료·무료로 갈라 놓은 것. 유료 여부를 보내는 앱의 설치만
    /// 들어간다. 전체 프로젝트에서는 앱마다 플래그 키가 다르므로 앱별로 갈라 모은다.
    func audienceInstalls(for project: String?) -> AudienceInstalls {
        memoized(\.audienceInstalls, project) {
            var result = AudienceInstalls()
            for key in project.map({ [$0] }) ?? allProjectKeys {
                guard let flag = paidFlagKey(for: key) else { continue }
                for snapshot in snapshots(for: key) {
                    // 0/1 플래그라 "1 이상이면 유료" — `paidSplit`과 같은 규칙이어야
                    // 두 화면이 다른 말을 하지 않는다.
                    if (snapshot.metrics[flag.key] ?? 0) >= 1 {
                        result.paid.insert(snapshot.installID)
                    } else {
                        result.free.insert(snapshot.installID)
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

    /// 이 범위에서 유료·무료를 가를 수 있는가 — 플래그를 보내는 앱이 하나라도 있는가.
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

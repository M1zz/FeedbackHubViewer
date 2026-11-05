//
//  FeedbackStore+Stabilization.swift
//  FeedbackHubViewer
//
//  안정화 지표의 재료를 모은다. 판정은 `Stabilization.measure` (순수 함수)가 한다.
//
//   - 버전별 설치 · 불안정 설치: 일 버킷과 함께 쌓는 `UsageRollups.versionTallies`.
//     원본 이벤트는 허브 전체에서 5,000건뿐이라 지난 버전까지 못 덮는다.
//   - 버전별 잔존: 그 버전이 나가 있던 동안 깐 설치(스냅샷의 설치일)가 이후에 왔는가(일 버킷).
//     잴 수 있는 범위는 코호트 잔존 카드와 같다.
//   - 릴리즈 · 성능 · 리뷰: `AppStoreConnectStore` 가 받아 둔 것을 화면이 넘긴다.
//

import Foundation

extension FeedbackStore {

    /// 받아 둔 재료가 같으면 다시 재지 않는다. 사용 레코드가 바뀌면 `Derived` 째로 버려진다.
    struct StabilizationKey: Hashable {
        let project: String
        let fetchedAt: Date
        let reviewsFetchedAt: Date?
        let hypotheses: Int
    }

    /// 한 앱의 안정화 지표. 릴리즈 기록을 아직 못 받았으면 nil.
    func stabilization(for project: String, source: Stabilization.Source?,
                       reviewFeed: ReviewFeed?) -> Stabilization.Report? {
        guard let source else { return nil }
        let own = releaseHypotheses.filter { $0.key.hasPrefix(project + "|") }
        let key = StabilizationKey(project: project, fetchedAt: source.fetchedAt,
                                   reviewsFetchedAt: reviewFeed?.fetchedAt, hypotheses: own.hashValue)
        return memoized(\.stabilization, key) {
            let everSeen = Set(eventTallies(for: project).keys.map {
                String($0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
            })
            let spec = ProjectStatsSpecCatalog.spec(for: project)?.release ?? .fallback
            let stabilityKnown = spec.stabilityEventsDeclared
                || !everSeen.isDisjoint(with: spec.stabilityEvents)
            let tallies = (rollups.versionTallies[project] ?? [:]).mapValues {
                Stabilization.Tally(installs: $0.installs.count, unstable: $0.unstable.count)
            }
            var hypotheses: [String: Stabilization.Hypothesis] = [:]
            for release in source.releases {
                let key = Stabilization.Hypothesis.key(project: project, version: release.version)
                hypotheses[release.version] = own[key]
            }
            return Stabilization.measure(source: source,
                                         tallies: tallies,
                                         stabilityKnown: stabilityKnown,
                                         cohorts: releaseCohorts(for: project, releases: source.releases),
                                         crashes: crashes(for: project),
                                         reviews: reviewFeed.flatMap { $0.fetchedAt == nil ? nil : $0.reviews },
                                         feedback: feedback(for: project),
                                         hypotheses: hypotheses)
        }
    }

    /// 버전마다, 그 버전을 제출한 뒤 다음 버전 제출 전까지 깐 설치의 잔존.
    private func releaseCohorts(for project: String, releases: [Stabilization.Release],
                                calendar: Calendar = .current) -> [String: Stabilization.Cohort] {
        let span = UsageRollups.idRetentionDays
        var daysAgo: [String: Int] = [:]
        for (index, entry) in UsageRollups.recentDayKeys(span, calendar: calendar).enumerated() {
            daysAgo[entry.key] = span - 1 - index
        }
        var seen: [String: Set<Int>] = [:]
        var firstEventAgo = -1
        for (key, bucket) in days(for: project, audience: .all) {
            guard let ago = daysAgo[key], !bucket.installs.isEmpty else { continue }
            firstEventAgo = max(firstEventAgo, ago)
            for install in bucket.installs { seen[install, default: []].insert(ago) }
        }

        let ordered = releases.sorted { $0.submittedAt < $1.submittedAt }
        var cohorts: [String: Stabilization.Cohort] = [:]
        for snapshot in snapshots(for: project, audience: .all) {
            guard let installed = snapshot.installDate,
                  let installAgo = daysAgo[UsageRollups.dayKey(installed, calendar: calendar)],
                  installAgo <= firstEventAgo,   // 이벤트를 보내기 전에 깐 설치는 못 본 것이다
                  let release = ordered.last(where: { $0.submittedAt <= installed }) else { continue }
            let active = seen[snapshot.installID] ?? []
            func tally(_ rate: inout Stabilization.Rate, _ checkpoint: Retention.Checkpoint) {
                let lastAgo = installAgo - checkpoint.days.upperBound
                guard lastAgo >= 1 else { return }   // 재는 창이 아직 안 끝났다
                rate.eligible += 1
                let firstAgo = installAgo - checkpoint.days.lowerBound
                if active.contains(where: { $0 >= lastAgo && $0 <= firstAgo }) { rate.returned += 1 }
            }
            var cohort = cohorts[release.version] ?? Stabilization.Cohort()
            tally(&cohort.d1, .day1)
            tally(&cohort.d7, .day7)
            tally(&cohort.d30, .day30)
            cohorts[release.version] = cohort
        }
        return cohorts
    }
}

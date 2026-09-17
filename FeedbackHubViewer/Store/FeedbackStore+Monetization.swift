//
//  FeedbackStore+Monetization.swift
//  FeedbackHubViewer
//
//  수익 설계를 **관측**하는 계산. 가격표가 맞는지는 여기서 말할 수 없고,
//  가격표가 서 있을 땅이 있는지를 말한다.
//
//  왜 이 셋인가. 값을 정하기 전에 답해야 하는 질문은 순서가 있다:
//
//    1. 쐐기에 닿은 사람이 몇인가(`Activation`)
//       가치를 못 받은 사람에게는 어떤 값도 비싸다. 이 숫자가 낮으면 가격표를
//       아무리 잘 짜도 소용이 없다 — 팔 물건이 아직 증명되지 않았다.
//
//    2. 값을 낼 이유가 생긴 사람이 몇인가(`Prospects`)
//       결제가 필요해지는 자리는 기능이 아니라 **한도**다. 그래서 잠재 고객은
//       "이 기능을 안 쓰는 사람"이 아니라 "한도에 닿았는데 아직 안 열린 사람"
//       이다. 이미 열려 있는 설치는 값을 낼 이유가 없으므로 모수에서 빠진다 —
//       그 수가 크면 가격표가 아니라 권한 부여를 봐야 한다.
//
//    3. 그 순간에 화면이 실제로 떴는가(`Moment`)
//       설계한 벽이 코드에서 실제로 서 있는지는 이벤트가 도착해야만 안다.
//       한 건도 없는 벽은 "아무도 안 왔다"가 아니라 "아직 안 섰다"이고,
//       둘은 고칠 곳이 다르다(가격 대 코드). 화면이 반드시 갈라 말해야 한다.
//
//  셋 다 **설치 단위**다. 스냅샷은 설치 하나가 한 줄이고, 이벤트 롤업은 이름마다
//  `installID` 집합을 들고 있어 사람 수로 셀 수 있다. 건수로 세면 페이월을 열 번
//  본 한 사람이 열 명이 된다.
//

import Foundation

extension FeedbackStore {

    /// 한 앱의 수익 관측판. 스펙에 `monetization` 절이 없으면 nil.
    struct Monetization {

        /// 설치에서 가치를 받은 상태까지의 사다리 한 칸.
        struct Step: Identifiable {
            let label: String
            let installs: Int
            /// 첫 칸(설치 전부) 대비 0~1.
            let ratio: Double
            /// 바로 앞 칸 대비. 첫 칸은 nil — 여기가 제일 크게 새는 자리를 찾는 값이다.
            let fromPrevious: Double?
            /// 이 칸을 재는 지표를 **한 설치도 안 보낸다.** 0명과는 다른 말이다.
            let isMissing: Bool
            var hint: String?
            var id: String { label }
        }

        struct Activation {
            let title: String
            let note: String?
            let steps: [Step]
            /// 앱이 스스로 정한 목표·하한(0~1). 뷰어는 판단하지 않고 선만 긋는다.
            let target: Double?
            let floor: Double?

            /// 마지막 칸의 도달률 — 이 사다리가 실제로 끝까지 데려간 비율.
            var reached: Double? { steps.last?.ratio }
            /// 앱이 정해 둔 하한 밑인가. 그러면 가격이 아니라 제품 문제다.
            var isBelowFloor: Bool {
                guard let floor, let reached else { return false }
                return reached < floor
            }
            /// 가장 크게 새는 칸 — 앞 칸 대비 남은 비율이 제일 낮은 자리.
            var worstDrop: Step? {
                steps.filter { !$0.isMissing && $0.fromPrevious != nil }
                    .min { ($0.fromPrevious ?? 1) < ($1.fromPrevious ?? 1) }
            }
        }

        /// 한도까지의 거리로 나눈 설치. 다섯은 서로 겹치지 않는다.
        struct Prospects {
            let title: String
            let note: String?
            /// 한도의 이름과 값 — "단축어 10개".
            let label: String
            let limit: Int

            /// 한도를 다 썼는데 아직 안 열렸다 — **지금 값을 낼 이유가 있는 사람.**
            let blocked: Int
            /// 한 칸 남았다 — 곧 그렇게 된다.
            let nearing: Int
            /// 쓰고는 있는데 아직 한도가 멀다.
            let roomLeft: Int
            /// 하나도 안 만들었다. 값을 낼 이유가 아직 없다.
            let notStarted: Int
            /// 이미 유료 기능이 열려 있다 — 값을 낼 이유가 없다(팔 대상이 아니다).
            let alreadyOpen: Int
            /// 권한을 못 읽는 설치.
            let unknown: Int

            /// 지금·곧 값을 낼 이유가 있는 사람.
            var prospects: Int { blocked + nearing }
            /// 언젠가 그렇게 될 수 있는 사람까지.
            var eventual: Int { prospects + roomLeft }
            var scanned: Int { blocked + nearing + roomLeft + notStarted + alreadyOpen + unknown }
            /// 팔 수 있는 모수가 전체에서 차지하는 몫.
            var prospectRatio: Double? {
                guard scanned > 0 else { return nil }
                return Double(prospects) / Double(scanned)
            }
        }

        /// 결제 화면이 뜨기로 설계된 순간 하나.
        struct Moment: Identifiable {
            let label: String
            let note: String?
            let event: String
            /// 이 순간을 만난 설치 수.
            let shown: Int
            /// 그중 버튼을 누른 · 결제한 설치. 기본형 이벤트를 안 적었으면 nil.
            let tapped: Int?
            let purchased: Int?
            /// 이 이벤트가 **한 건도 도착한 적이 없다** — 벽이 아직 안 섰다.
            var isMissing: Bool { shown == 0 }
            var id: String { label }
        }

        let activation: Activation?
        let prospects: Prospects?
        let moments: [Moment]
        /// 순간의 성과를 셀 기본형을 스펙이 안 적어 두었는가.
        let lacksOutcomeEvents: Bool
        let note: String?

        var isEmpty: Bool { activation == nil && prospects == nil && moments.isEmpty }
    }

    /// 이 프로젝트의 수익 관측판. 스펙에 `monetization` 절이 있는 앱에서만 나온다.
    ///
    /// 무리 고르개와 무관하게 **언제나 전체 설치**를 본다. "유료기능만 놓고 본
    /// 잠재 고객"은 정의상 0이고, 무리를 거른 화면에서 이 카드까지 걸러 버리면
    /// 빈 카드가 뜬다.
    func monetization(for project: String?) -> Monetization? {
        guard let project, let spec = ProjectStatsSpecCatalog.spec(for: project)?.monetization else {
            return nil
        }
        return memoized(\.monetization, project) {
            let snaps = snapshots(for: project)
            let entitlement = entitlement(for: project)
            let totals = rollups.totals(for: project, excluding: hiddenProjects)

            // MARK: 사다리
            var activation: Monetization.Activation?
            if let step = spec.activation, !step.steps.isEmpty {
                var steps: [Monetization.Step] = []
                var previous: Int?
                let first = snaps.count
                for rung in step.steps {
                    let count: Int
                    let missing: Bool
                    if let metric = rung.metric {
                        let floor = rung.atLeast ?? 1
                        count = snaps.filter { ($0.metrics[metric] ?? 0) >= floor }.count
                        // 그 지표를 **아무도 안 보내는** 것과 0명인 것은 다르다.
                        missing = !snaps.contains { $0.metrics[metric] != nil }
                    } else {
                        count = snaps.count
                        missing = false
                    }
                    steps.append(.init(
                        label: rung.label,
                        installs: count,
                        ratio: first > 0 ? Double(count) / Double(first) : 0,
                        fromPrevious: previous.map { $0 > 0 ? Double(count) / Double($0) : 0 },
                        isMissing: missing,
                        hint: rung.hint))
                    previous = count
                }
                activation = .init(title: step.title, note: step.note, steps: steps,
                                   target: step.target, floor: step.floor)
            }

            // MARK: 한도까지의 거리
            var prospects: Monetization.Prospects?
            if let wall = spec.wall {
                let near = max(1, wall.nearBy ?? 1)
                var blocked = 0, nearing = 0, roomLeft = 0, notStarted = 0
                var alreadyOpen = 0, unknown = 0
                for snapshot in snaps {
                    switch entitlement?.isUnlocked(snapshot) {
                    case true?:
                        // 이미 열린 설치는 값을 낼 이유가 없다. 한도와의 거리를
                        // 재 봐야 뜻이 없으므로 통째로 한 칸에 둔다.
                        alreadyOpen += 1
                        continue
                    case nil:
                        unknown += 1
                        continue
                    case false?:
                        break
                    }
                    let value = Int(snapshot.metrics[wall.metric] ?? 0)
                    if value >= wall.limit { blocked += 1 }
                    else if value >= wall.limit - near { nearing += 1 }
                    else if value >= 1 { roomLeft += 1 }
                    else { notStarted += 1 }
                }
                prospects = .init(title: wall.title, note: wall.note,
                                  label: wall.label, limit: wall.limit,
                                  blocked: blocked, nearing: nearing, roomLeft: roomLeft,
                                  notStarted: notStarted, alreadyOpen: alreadyOpen,
                                  unknown: unknown)
            }

            // MARK: 설계된 순간
            /// 이름이 슬라이스까지 적혀 있으면 그것만, 기본형만 적혀 있으면 그
            /// 기본형의 모든 슬라이스를 합친다(`paywall_view`는 `:memo`도 포함).
            func installs(firing name: String) -> Set<String> {
                if name.contains(":") { return totals[name]?.installs ?? [] }
                var union: Set<String> = []
                for (key, total) in totals where key == name || key.hasPrefix(name + ":") {
                    union.formUnion(total.installs)
                }
                return union
            }
            let tappedAll = spec.tappedEvent.map(installs(firing:))
            let purchasedAll = spec.purchasedEvent.map(installs(firing:))
            let moments = spec.moments.map { moment -> Monetization.Moment in
                let shown = installs(firing: moment.event)
                return .init(label: moment.label, note: moment.note, event: moment.event,
                             shown: shown.count,
                             // 이 순간을 만난 사람 중 누른·낸 사람. 교집합이라
                             // 다른 벽에서 온 결제가 이 벽의 성과로 섞이지 않는다.
                             tapped: tappedAll.map { shown.intersection($0).count },
                             purchased: purchasedAll.map { shown.intersection($0).count })
            }

            return Monetization(activation: activation,
                                prospects: prospects,
                                moments: moments,
                                lacksOutcomeEvents: spec.tappedEvent == nil && spec.purchasedEvent == nil,
                                note: spec.note)
        }
    }
}

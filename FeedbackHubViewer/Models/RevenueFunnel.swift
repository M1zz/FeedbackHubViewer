//
//  RevenueFunnel.swift
//  FeedbackHubViewer
//
//  노출에서 결제까지 한 줄로 — 스토어 깔때기와 앱 안 깔때기를 잇는다.
//
//    [스토어 · Apple 분석 리포트]  노출 → 페이지 조회 → 첫 다운로드
//    [앱 안 · 허브 이벤트]         새 설치 → 페이월 → … → 결제
//
//  두 토막은 **세는 대상이 다르다.** 앞은 Apple 이 센 기기 수와 다운로드 건수이고,
//  뒤는 허브에 보고한 설치다. 그래서 비율은 토막 안에서만 낸다. 토막 사이(첫 다운로드
//  → 새 설치)는 전환이 아니라 **보고율**이다 — 이벤트를 안 보내는 옛 버전 · 끈 사람 ·
//  아직 안 연 사람이 빠진 것이지 떠난 것이 아니다. 그걸 "여기서 N% 샜다"고 그리면
//  깔때기가 거짓말을 한다.
//
//  앱 안 토막은 **최근 N일 안에 설치한** 사람만 센다. 결제는 몇 달 전에 깐 사람에게서도
//  오는데, 그걸 이번 달 다운로드 밑에 붙이면 전환율이 100%를 넘을 수 있다. 같은 사람을
//  위에서 아래로 따라가야 깔때기다.
//
//  앱 안 단계는 Swift 가 아니라 앱별 스펙의 결제 퍼널에서 온다(README §3). 페이월
//  단계부터 끝까지를 빌려 온다 — 그 앞(유료 기능을 건드림 같은)은 앱마다 뜻이 달라서
//  다운로드 밑에 바로 붙이면 이어지지 않는다.
//

import Foundation

struct RevenueFunnel {
    struct Step: Identifiable {
        let label: String
        /// nil 이면 모름 — 리포트가 없거나 이 단계를 셀 이벤트가 없다.
        let count: Int?
        var hint: String?
        var id: String { label }
    }

    struct Segment: Identifiable {
        let title: String
        /// 무엇을 세는가 — "기기 · 건수", "설치".
        let unit: String
        let steps: [Step]
        var id: String { title }
    }

    let days: Int
    let store: Segment?
    let app: Segment?
    /// 첫 다운로드 중 허브에 보고한 새 설치의 비율. 전환이 아니다.
    let reportingRate: Double?
    /// 스펙에 결제 퍼널이 없어서 앱 안 단계를 못 그렸다.
    let missingSpecFunnel: Bool

    static func build(days: Int,
                      storeFunnel: StoreFunnel?,
                      spec: ProjectStatsSpec?,
                      snapshots: [UsageSnapshot],
                      events: [UsageEvent],
                      now: Date = Date()) -> RevenueFunnel {
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 3600)

        var store: Segment?
        if let storeFunnel, storeFunnel.instances > 0 {
            let total = storeFunnel.total
            store = Segment(title: "스토어", unit: "기기 · 건수", steps: [
                Step(label: "검색 · 둘러보기 노출", count: total.impressions,
                     hint: "노출을 본 기기 수. 다른 앱 · 웹에서 곧장 온 사람은 여기 없이 다음 칸에 들어와요."),
                Step(label: "제품 페이지 조회", count: total.pageViews),
                Step(label: "첫 다운로드", count: total.firstDownloads,
                     hint: "업데이트 · 재다운로드는 빼요.")
            ])
        }

        // 최근 N일 안에 설치한 사람. 설치일을 안 보내는 옛 기록은 셀 수 없어서 뺀다.
        let cohort = Set(snapshots.filter { ($0.installDate ?? .distantPast) >= cutoff }.map(\.installID))
        let paymentSteps = spec.flatMap(Self.paymentSteps(in:)) ?? []

        var appSteps = [Step(label: "앱을 열고 보고한 새 설치", count: cohort.count,
                             hint: "최근 \(days)일 안에 설치했고 허브에 사용 통계를 보낸 설치.")]
        if !paymentSteps.isEmpty {
            let recent = events.filter { event in
                guard event.occurredAt >= cutoff, let install = event.installID else { return false }
                return cohort.contains(install)
            }
            for step in paymentSteps {
                let names = Set(step.names)
                let installs = Set(recent.filter { names.contains($0.baseName) }.compactMap(\.installID))
                appSteps.append(Step(label: step.label, count: installs.count, hint: step.hint))
            }
        }

        let downloads = store?.steps.last?.count
        let rate = downloads.flatMap { $0 > 0 ? Double(cohort.count) / Double($0) : nil }

        return RevenueFunnel(days: days,
                             store: store,
                             app: Segment(title: "앱 안", unit: "설치", steps: appSteps),
                             reportingRate: rate,
                             missingSpecFunnel: paymentSteps.isEmpty)
    }

    /// 스펙의 퍼널 중 페이월 단계가 있는 첫 것에서, 페이월부터 끝까지.
    static func paymentSteps(in spec: ProjectStatsSpec) -> [ProjectStatsSpec.FunnelSpec.Step]? {
        for card in spec.cards {
            guard case .funnel(let funnel) = card else { continue }
            guard let start = funnel.steps.firstIndex(where: { step in
                step.names.contains { $0.hasPrefix("paywall") }
            }) else { continue }
            let steps = Array(funnel.steps[start...])
            // 페이월 한 칸뿐이면 결제까지 가는 퍼널이 아니다.
            if steps.count >= 2 { return steps }
        }
        return nil
    }
}

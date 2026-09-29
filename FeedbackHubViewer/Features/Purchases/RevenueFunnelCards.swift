//
//  RevenueFunnelCards.swift
//  FeedbackHubViewer
//
//  앱 내 구입 섹션의 깔때기 두 장.
//
//    노출에서 결제까지 — 스토어 토막과 앱 안 토막을 잇는다(`RevenueFunnel`).
//    구독 — 체험 · 할인 시작에서 유료 전환까지, 그리고 갱신 · 해지 · 환불
//      (`SubscriptionSummary`).
//
//  깔때기 모양은 **같은 대상을 세는 토막 안에서만** 좁아진다. 토막이 바뀌는 자리에서
//  막대는 다시 꽉 찬 폭으로 시작하고, 둘 사이에는 비율 대신 "세는 대상이 바뀝니다"와
//  보고율을 적는다.
//

import SwiftUI

// MARK: - 노출에서 결제까지

struct RevenueFunnelCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    private var funnel: RevenueFunnel {
        RevenueFunnel.build(days: AppStoreConnectStore.salesDays,
                            storeFunnel: storeFunnel,
                            spec: ProjectStatsSpecCatalog.spec(for: project),
                            snapshots: store.snapshots(for: project),
                            events: store.events(for: project))
    }

    private var storeFunnel: StoreFunnel? {
        if case .loaded(.ready(let funnel))? = connect.funnels[project] { return funnel }
        return nil
    }

    var body: some View {
        let funnel = self.funnel
        Card(title: "노출에서 결제까지 (최근 \(funnel.days)일)", systemImage: "line.3.horizontal.decrease") {
            if let segment = funnel.store {
                FunnelSegmentView(segment: segment)
            } else {
                storeStatus
            }

            bridge(funnel)

            if let segment = funnel.app {
                FunnelSegmentView(segment: segment)
            }
            if funnel.missingSpecFunnel {
                Label("이 앱의 스펙(usage-spec.json)에 페이월에서 결제까지 가는 퍼널이 없어 앱 안 단계는 설치 수까지만 그립니다.",
                      systemImage: "doc.badge.gearshape")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("앱 안 토막은 최근 \(funnel.days)일 안에 설치한 사람만 따라갑니다 — 몇 달 전에 깐 사람의 결제를 이번 달 다운로드 밑에 붙이면 전환율이 부풀어요. 한 사람이 페이월을 여러 번 봐도 한 번으로 셉니다. 판매 리포트의 결제 건수(위 타일)는 옛 사용자 · 갱신까지 들어간 거래 수라 이 숫자와 다릅니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: project) { await connect.loadFunnel(bundleID: project) }
    }

    @ViewBuilder
    private var storeStatus: some View {
        switch connect.funnels[project] {
        case nil, .loading?:
            ProgressView("스토어 노출 · 다운로드 리포트를 받는 중…")
                .font(.callout)
        case .failed(let message)?:
            Label("스토어 토막을 못 읽었습니다 — \(message)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(.noRequest)?:
            Label("스토어 토막은 App Store 분석 리포트가 있어야 나옵니다. 키워드 섹션의 \"리포트 요청 만들기\"를 한 번 누르면 1~2일 뒤부터 쌓여요.",
                  systemImage: "doc.text.magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(.ready)?:
            Label("분석 리포트 요청은 있지만 아직 만들어진 파일이 없습니다. 1~2일 뒤부터 나와요.",
                  systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// 두 토막 사이 — 전환이 아니라 세는 대상이 바뀌는 자리.
    private func bridge(_ funnel: RevenueFunnel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("여기서 세는 대상이 바뀝니다 — Apple 이 센 다운로드 → 허브에 보고한 설치")
                    .font(.callout.weight(.semibold))
                if let rate = funnel.reportingRate {
                    Text("첫 다운로드의 \(Int((rate * 100).rounded()))%가 허브에 보고했어요. 나머지는 떠난 게 아니라 이벤트를 안 보내는 버전 · 끈 사람 · 아직 안 연 사람이라 새는 칸으로 그리지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 구독

struct SubscriptionFunnelCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// 이 앱의 Apple ID.
    let appleID: String

    var body: some View {
        Card(title: "구독 깔때기 (최근 \(AppStoreConnectStore.salesDays)일)", systemImage: "arrow.triangle.2.circlepath") {
            if connect.credentials?.hasVendorNumber != true {
                note("판매자 번호를 넣으면 구독 이벤트 리포트로 체험 시작 → 유료 전환, 갱신 · 해지를 셉니다.")
            } else if let error = connect.subscriptionEventsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                note("구독 이벤트 리포트는 키 역할이 Admin · Finance · Sales 중 하나여야 읽힙니다.")
            } else if let window = connect.subscriptionEvents {
                content(window.summary(appleID: appleID), window: window)
            } else {
                ProgressView("구독 이벤트 리포트를 받는 중…")
                    .font(.callout)
            }
        }
        .task { await connect.loadSubscriptionEvents() }
    }

    @ViewBuilder
    private func content(_ summary: SubscriptionSummary, window: SubscriptionEventWindow) -> some View {
        if summary.isEmpty {
            note("최근 \(window.days)일에 이 앱의 구독 이벤트가 없습니다.")
        } else {
            FunnelSegmentView(segment: .init(title: "오퍼로 시작한 구독", unit: "건", steps: [
                .init(label: "체험 · 할인으로 시작", count: summary.offerStarts,
                      hint: "무료 체험 · 첫 달 할인 · 프로모션 오퍼를 시작한 수."),
                .init(label: "오퍼 뒤 유료로 넘어감", count: summary.paidFromOffer,
                      hint: "오퍼가 끝나고 정가를 내기 시작한 수.")
            ]))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                StatTile(title: "새 유료 구독", value: "\(summary.newPaid)", unit: "건",
                         systemImage: "person.badge.plus", tint: .green)
                StatTile(title: "바로 유료 구독", value: "\(summary.directSubscribes)", unit: "건",
                         systemImage: "creditcard", tint: .blue)
                StatTile(title: "갱신", value: "\(summary.renewals)", unit: "건",
                         systemImage: "arrow.clockwise", tint: .teal)
                StatTile(title: "해지", value: "\(summary.cancels)", unit: "건",
                         systemImage: "xmark.circle", tint: .orange)
                StatTile(title: "환불", value: "\(summary.refunds)", unit: "건",
                         systemImage: "arrow.uturn.backward", tint: .red)
            }

            DisclosureGroup("Apple 이 보낸 이벤트 원문") {
                VStack(spacing: 6) {
                    ForEach(summary.events.sorted { $0.value > $1.value }, id: \.key) { name, count in
                        HStack {
                            Text(name).font(.callout.monospaced()).textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text("\(AppFormat.count(count))").font(.callout.monospacedDigit())
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)

            note("같은 기간 안의 수라 한 사람을 따라간 전환율이 아닙니다 — 이번 달에 유료로 넘어간 사람은 지난달에 체험을 시작했을 수 있어요. 체험이 길수록 두 칸이 한 달씩 어긋납니다. 해지는 자동 갱신을 끈 수이고, 구독이 바로 끝난다는 뜻은 아니에요." + (window.missingDays > 0 ? " \(window.days)일 중 \(window.missingDays)일은 리포트를 못 받아 빠졌습니다." : ""))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 깔때기 한 토막

/// 가운데 맞춘 막대가 아래로 좁아진다. 폭은 토막의 첫 칸 대비, 옆 숫자는 앞 칸 대비.
struct FunnelSegmentView: View {
    let segment: RevenueFunnel.Segment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(segment.title).font(.subheadline.weight(.semibold))
                Tag(text: segment.unit, isCompact: true)
            }
            let first = segment.steps.first?.count ?? 0
            ForEach(Array(segment.steps.enumerated()), id: \.element.id) { index, step in
                let previous = index > 0 ? segment.steps[index - 1].count : nil
                row(step, first: first, previous: previous, isFirst: index == 0)
            }
        }
    }

    private func row(_ step: RevenueFunnel.Step, first: Int, previous: Int?, isFirst: Bool) -> some View {
        let ratio = step.count.map { first > 0 ? min(1, Double($0) / Double(first)) : 0 } ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step.label).font(.callout)
                Spacer(minLength: 8)
                Text(step.count.map(AppFormat.count) ?? "모름")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(step.count == nil ? .secondary : .primary)
                if !isFirst {
                    Text(stepRate(step.count, previous))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Color.accentColor.opacity(0.35 + 0.5 * ratio))
                    .frame(width: max(4, geo.size.width * ratio))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 14)
            if let hint = step.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 앞 칸 대비. 이벤트는 순서를 강제하지 않아서 뒤 칸이 클 수 있다 — 그러면
    /// 100%를 넘는 비율 대신 그렇다고 적는다.
    private func stepRate(_ count: Int?, _ previous: Int?) -> String {
        guard let count, let previous, previous > 0 else { return "" }
        if count > previous { return "앞 칸보다 많음" }
        return "↳ \(Int((Double(count) / Double(previous) * 100).rounded()))%"
    }
}

//
//  BusinessModelViews.swift
//  FeedbackHubViewer
//
//  앱 내 구입 칸의 비즈니스 모델 신호등과 페이월.
//
//  신호등은 판정이 먼저다 — 색 · 한 줄 · 다음 할 일, 근거는 그 아래 작게. 페이월은 앱 소스에서
//  읽어 app-portfolio 의 paywalls.json 에 정리해 둔 것을 그대로 보여 준다(가격 사다리 · 무료와
//  잠긴 것 · 언제 뜨나). 원본 파일 목록과 메모는 접어 둔다.
//

import SwiftUI

extension BusinessSignal {
    /// 가게들에서 한 앱의 신호등을 낸다.
    @MainActor
    static func of(_ project: String, connect: AppStoreConnectStore) -> BusinessSignal {
        let portfolio = PortfolioStore.shared
        var sales: Sales?
        if let window = connect.sales, case .loaded(let app, let products)? = connect.catalogs[project] {
            let totals = window.totals(app: app, products: products)
            sales = Sales(purchases: totals.purchases,
                          hasProceeds: totals.proceeds.values.contains { $0 > 0 },
                          firstDownloads: totals.firstDownloads)
        }
        return make(app: portfolio.app(for: project), paywall: portfolio.paywall(for: project), sales: sales)
    }
}

/// 신호등 점.
struct SignalDot: View {
    let level: BusinessSignal.Level
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: size, height: size)
            .accessibilityLabel("신호등 \(level.label)")
    }
}

struct BusinessModelCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    let project: String

    var body: some View {
        let signal = BusinessSignal.of(project, connect: connect)
        Card(title: "비즈니스 모델 신호등", systemImage: "light.beacon.max") {
            HStack(alignment: .center, spacing: 10) {
                SignalDot(level: signal.level, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(signal.level == .unknown ? Color.secondary : signal.level.color)
                    Text(signal.model)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            if let next = signal.next {
                Label(next, systemImage: "arrow.right.circle")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("근거") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(signal.reasons, id: \.self) { Text($0).font(.body) }
                    if let items = portfolio.app(for: project)?.price?.iapItems, !items.isEmpty {
                        Text("스토어 상품: " + items.map { "\($0.name) \($0.price)" }.joined(separator: " · "))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
        }
    }
}

struct PaywallCard: View {
    @ObservedObject private var portfolio = PortfolioStore.shared
    let project: String

    var body: some View {
        Card(title: "페이월", systemImage: "lock.open") {
            if let paywall = portfolio.paywall(for: project), paywall.hasPaywall {
                content(paywall)
            } else if portfolio.paywall(for: project) != nil {
                Text("이 앱에는 앱 안 결제 화면이 없어요(paywalls.json: 없음).")
                    .font(.body).foregroundStyle(.secondary)
            } else {
                Text(portfolio.isLoading ? "app-portfolio 읽는 중…"
                     : "app-portfolio 의 paywalls.json 에 이 앱이 없어요. 페이월을 아직 정리하지 않은 앱이에요.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ paywall: PaywallInfo) -> some View {
        if paywall.hidden == true {
            Label("출시 빌드에서는 꺼 둔 페이월이에요", systemImage: "eye.slash")
                .font(.body)
                .foregroundStyle(.orange)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(paywall.headline ?? "—")
                .font(.title3.weight(.bold))
            if let sub = paywall.subheadline {
                Text(sub).font(.body).foregroundStyle(.secondary)
            }
            Text(paywall.kindLabel)
                .font(.body)
                .foregroundStyle(.tint)
        }
        if let benefits = paywall.benefits, !benefits.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(benefits, id: \.self) { Label($0, systemImage: "checkmark").font(.body) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        if let tiers = paywall.tiers, !tiers.isEmpty {
            VStack(spacing: 0) {
                ForEach(tiers, id: \.self) { tier in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tier.label ?? tier.period ?? "상품").font(.body)
                            if let period = tier.period, period != tier.label {
                                Text(period).font(.body).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if tier.live == false {
                            Text("스토어 준비 중" + (tier.price.map { " · \($0)" } ?? ""))
                                .font(.body).foregroundStyle(.secondary)
                        } else {
                            Text(tier.price ?? "—").font(.body.monospacedDigit().weight(.semibold))
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        if let cta = paywall.cta {
            Text(cta)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        let fine = [paywall.trial, paywall.restore == true ? "구매 복원 있음" : paywall.restore == false ? "구매 복원 없음" : nil]
            .compactMap { $0 }
        if !fine.isEmpty {
            Text(fine.joined(separator: " · ")).font(.body).foregroundStyle(.secondary)
        }
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("무료로 주는 것").font(.headline)
                Text("돈을 내면 열리는 것").font(.headline)
            }
            GridRow {
                lines(paywall.free)
                lines(paywall.locked)
            }
        }
        if let triggers = paywall.triggers, !triggers.isEmpty {
            Text("언제 보이나").font(.headline)
            ForEach(triggers, id: \.self) { Label($0, systemImage: "clock").font(.body) }
        }
        if paywall.notes != nil || !(paywall.paywallFiles ?? []).isEmpty {
            DisclosureGroup("메모 · 소스 파일") {
                VStack(alignment: .leading, spacing: 4) {
                    if let notes = paywall.notes { Text(notes).font(.body) }
                    ForEach(paywall.paywallFiles ?? [], id: \.self) {
                        Text($0).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
        }
    }

    private func lines(_ items: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items ?? ["—"], id: \.self) {
                Text($0).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 전체 앱 — 앱마다 신호등 한 줄, 빨강이 위.
struct BusinessOverviewCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    @ObservedObject private var icons = StoreIcons.shared

    var body: some View {
        let rows = store.projectCounts.map(\.key)
            .filter { $0 != Feedback.unclassifiedProject }
            .map { (key: $0, signal: BusinessSignal.of($0, connect: connect)) }
            .sorted { ($0.signal.level, $0.key) < ($1.signal.level, $1.key) }
        let count = { (level: BusinessSignal.Level) in rows.filter { $0.signal.level == level }.count }

        Card(title: "앱마다 비즈니스 모델 신호등", systemImage: "light.beacon.max") {
            Text("빨강 \(count(.red)) · 노랑 \(count(.yellow)) · 초록 \(count(.green))" + (count(.unknown) > 0 ? " · 모름 \(count(.unknown))" : ""))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.key) { row in
                Button { store.open(project: row.key, section: .purchases) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        SignalDot(level: row.signal.level)
                            .padding(.top, 6)
                        AppIcon(url: icons.url(for: row.key, keywords: keywords), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.displayName(for: row.key)).font(.body.weight(.semibold))
                            Text("\(row.signal.model) · \(row.signal.headline)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if portfolio.paywall(for: row.key)?.hasPaywall == true {
                            Image(systemName: "lock.open").foregroundStyle(.secondary)
                                .help("페이월 있음")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
    }
}

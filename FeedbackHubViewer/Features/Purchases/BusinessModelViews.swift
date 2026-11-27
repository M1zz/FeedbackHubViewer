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
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    let project: String

    /// 신호등을 Claude 에게 넘길 글. 근거 · 상품 · 페이월까지 담아 이 화면 없이도 읽히게.
    static func claudePrompt(_ signal: BusinessSignal, appName: String, project: String,
                             portfolio: PortfolioStore) -> String {
        var lines = ["\(appName) (\(project)) 의 비즈니스 모델 신호등이 \(signal.level.label)입니다: \(signal.headline)", ""]
        lines.append("수익 모델: \(signal.model)")
        if let next = signal.next { lines.append("다음 할 일: \(next)") }
        lines.append("")
        lines.append("## 근거")
        lines += signal.reasons.map { "- \($0)" }
        if let items = portfolio.app(for: project)?.price?.iapItems, !items.isEmpty {
            lines.append("")
            lines.append("## 스토어 상품")
            lines += items.map { "- \($0.name) \($0.price)" }
        }
        if let paywall = portfolio.paywall(for: project) {
            lines.append("")
            lines.append("## 페이월")
            lines.append(paywall.hasPaywall ? "- 종류: \(paywall.kindLabel)" : "- 앱 안 결제 화면 없음")
            if paywall.hidden == true { lines.append("- 출시 빌드에서 꺼 둠") }
            for file in paywall.paywallFiles ?? [] { lines.append("- 파일: \(file)") }
        }
        lines.append("")
        lines.append("## 부탁")
        switch signal.level {
        case .green:
            lines.append("지금은 초록입니다. 결제 흐름에 놓친 위험이 있는지 코드로 점검하고, 없으면 없다고 말해 주세요.")
        case .unknown:
            lines.append("왜 판정할 수 없는지 확인해 주세요. app-portfolio 나 앱 쪽에서 채울 정보가 있으면 무엇인지 알려 주세요.")
        default:
            lines.append("앱 리포에서 결제 코드와 페이월을 읽고 위 판정의 원인을 확인한 뒤, 코드로 고칠 수 있는 것은 고쳐 주세요.")
        }
        lines.append("가격 변경과 App Store Connect 설정처럼 제가 직접 정할 일은 고치지 말고 목록으로 알려 주세요.")
        return lines.joined(separator: "\n")
    }

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
            CopyButton(text: Self.claudePrompt(signal, appName: store.displayName(for: project), project: project,
                                               portfolio: portfolio),
                       title: "Claude에게 맡길 글 복사")
                .buttonStyle(.bordered)
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

/// 앱 가격을 무료 · 유료 · 부분 유료로 가르고, 유료는 가격대로 다시 가른다.
enum PriceKind: String, CaseIterable, Identifiable {
    case all = "전체", free = "무료", paid = "유료", freemium = "부분 유료"
    var id: Self { self }

    /// pricingModel(free · paid · freemium · freemium-subscription · paid+subscription · paid+iap)에서.
    static func of(_ model: String?) -> PriceKind? {
        guard let model else { return nil }
        if model == "free" { return .free }
        if model.hasPrefix("paid") { return .paid }
        if model.hasPrefix("freemium") { return .freemium }
        return nil
    }
}

enum PriceBand: String, CaseIterable, Identifiable {
    case all = "모든 가격", low = "₩5,000 이하", mid = "₩5,000~15,000", high = "₩15,000 이상"
    var id: Self { self }
    func contains(_ krw: Int?) -> Bool {
        guard self != .all else { return true }
        guard let krw else { return false }
        switch self {
        case .low: return krw <= 5000
        case .mid: return krw > 5000 && krw <= 15000
        case .high: return krw > 15000
        case .all: return true
        }
    }
}

extension PortfolioApp.Price {
    /// 줄에 보일 가격 한 토막 — "₩4,400" · "인앱 3개" · "무료".
    var label: String {
        if let priceKRW, priceKRW > 0 { return "₩" + priceKRW.formatted(.number.grouping(.automatic)) }
        if let items = iapItems, !items.isEmpty { return "인앱 \(items.count)개" }
        return pricingModel == "free" || isFree == true ? "무료" : "가격 모름"
    }
}

/// 전체 앱 — 앱마다 신호등 한 줄, 빨강이 위. 무료 · 유료 · 부분 유료와 가격대로 거른다.
struct BusinessOverviewCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    @ObservedObject private var icons = StoreIcons.shared
    @State private var kind: PriceKind = .all
    @State private var band: PriceBand = .all

    private struct Row {
        let key: String
        let signal: BusinessSignal
        let price: PortfolioApp.Price?
        var kind: PriceKind? { PriceKind.of(price?.pricingModel ?? (price?.isFree == false ? "paid" : price == nil ? nil : "free")) }
    }

    var body: some View {
        let all = store.projectCounts.map(\.key)
            .filter { $0 != Feedback.unclassifiedProject }
            .map { Row(key: $0, signal: BusinessSignal.of($0, connect: connect), price: portfolio.app(for: $0)?.price) }
        let rows = all
            .filter { kind == .all || $0.kind == kind }
            .filter { band.contains($0.price?.priceKRW) }
            .sorted {
                // 가격대를 고르면 비싼 순, 아니면 신호등 순.
                band != .all ? ($0.price?.priceKRW ?? 0, $0.key) > ($1.price?.priceKRW ?? 0, $1.key)
                             : ($0.signal.level, $0.key) < ($1.signal.level, $1.key)
            }
        let count = { (level: BusinessSignal.Level) in rows.filter { $0.signal.level == level }.count }
        let kindCount = { (k: PriceKind) in all.filter { $0.kind == k }.count }

        Card(title: "앱마다 비즈니스 모델 신호등", systemImage: "light.beacon.max") {
            Picker("가격 종류", selection: $kind) {
                ForEach(PriceKind.allCases) { k in
                    Text(k == .all ? "전체 \(all.count)" : "\(k.rawValue) \(kindCount(k))").tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if kind == .paid || kind == .all {
                Picker("가격대", selection: $band) {
                    ForEach(PriceBand.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(.hubSubheadline)
            }
            Text("빨강 \(count(.red)) · 노랑 \(count(.yellow)) · 초록 \(count(.green))" + (count(.unknown) > 0 ? " · 모름 \(count(.unknown))" : "")
                 + (rows.isEmpty ? " — 이 조건에 맞는 앱이 없어요" : ""))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.key) { row in
                HStack(alignment: .top, spacing: 8) {
                Button { store.open(project: row.key, section: .purchases) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        SignalDot(level: row.signal.level)
                            .padding(.top, 6)
                        AppIcon(url: icons.url(for: row.key, keywords: keywords), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(store.displayName(for: row.key)).font(.body.weight(.semibold))
                                if let price = row.price {
                                    Tag(text: price.label, tint: row.kind == .paid ? .accentColor : nil, isCompact: true)
                                }
                            }
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
                ClaudeCopyIcon(text: BusinessModelCard.claudePrompt(row.signal, appName: store.displayName(for: row.key),
                                                                    project: row.key, portfolio: portfolio))
                }
            }
        }
    }
}

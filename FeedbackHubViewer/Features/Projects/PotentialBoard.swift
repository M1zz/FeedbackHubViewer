//
//  PotentialBoard.swift
//  FeedbackHubViewer
//
//  홈의 두 번째 얼굴 — "지금 무슨 일이 났나" 가 아니라 "어느 앱에 시간을 더 들일까".
//
//  위에서 아래로:
//   1. 결론 한 줄 — 고치면 오를 앱 · 방치해도 받는 앱 · 정리 후보가 몇 개인가.
//   2. 목표에서 거꾸로 — 한 달 목표와 값을 넣으면 유료 몇 명, 다운로드 몇 건이 필요한지.
//   3. 앱마다 한 장 — 판정 한 줄 · 지금 할 일 · 깔때기 세 단계를 업계 평균과 견준 막대 ·
//      이 앱의 유입으로 목표에 닿는지. 고치면 가장 많이 오를 앱부터.
//
//  판정은 `AppPotential` 이 한다(순수 함수). 여기는 재료를 모으고 그린다.
//  재료: 스토어 분석 리포트의 깔때기(`funnels`) · 판매 리포트(`sales`) · 스토어의 마지막
//  업데이트 날짜 · 허브가 본 7일 활성. 모두 최근 30일.
//

import SwiftUI

struct PotentialBoard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @ObservedObject private var icons = StoreIcons.shared

    /// 한 달 목표(만 원)와 한 사람이 내는 값(원). 기본은 월 100만 원 · 5,000원.
    @AppStorage("potential-target-man") private var targetMan = 100
    @AppStorage("potential-price") private var price = 5_000
    @State private var filter: AppPotential.Kind?

    private var apps: [String] { SectionMetrics.keywordProjects(store) }

    private var goal: RevenueGoal {
        RevenueGoal(target: Double(targetMan) * 10_000, price: Double(price))
    }

    var body: some View {
        let ranked = AppPotential.rank(apps.map(input))
        let shown = filter.map { kind in ranked.filter { $0.kind == kind } } ?? ranked
        let loading = apps.filter { connect.funnels[$0] == nil || connect.funnels[$0]?.isLoading == true }.count

        VStack(alignment: .leading, spacing: 16) {
            if !connect.isConfigured {
                notice("App Store Connect 키가 필요합니다",
                       "노출 · 페이지 조회 · 다운로드 · 결제를 App Store Connect 에서 읽습니다. 설정에서 키를 넣어 주세요.")
            }
            conclusion(ranked)
            goalCard
            filterBar(ranked)
            if loading > 0 {
                Label("리포트를 읽는 중인 앱 \(loading)개 — 다 읽으면 차례가 바뀔 수 있습니다", systemImage: "hourglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360, maximum: 560), spacing: 14)], spacing: 14) {
                ForEach(shown) { app in
                    Button {
                        store.open(project: app.input.project, section: section(for: app))
                    } label: {
                        card(app)
                    }
                    .buttonStyle(.plain)
                }
            }
            footnote
        }
        .task(id: apps) {
            await icons.resolve(apps, keywords: keywords)
            await connect.loadSales()
            // 깔때기는 디스크에 둔 리포트로 먼저 그려진다. 상품 목록은 결제 건수를 앱에 잇는 데 쓴다.
            for key in apps {
                await connect.loadFunnel(bundleID: key)
                await connect.loadCatalog(bundleID: key)
            }
        }
    }

    // MARK: - 재료

    private func input(_ project: String) -> AppPotential.Input {
        var input = AppPotential.Input(project: project, name: store.displayName(for: project))
        input.active7 = store.usage(for: project).activeInstalls7

        if case .ready(let funnel)? = connect.funnels[project]?.value, funnel.instances > 0 {
            let total = funnel.total
            input.hasFunnel = true
            input.impressions = total.impressions
            input.pageViews = total.pageViews
            input.pageDownloads = total.pageDownloads
            input.downloads = total.firstDownloads
            if total.firstDownloads > 0, let search = funnel.sources["App Store search"] {
                input.searchShare = Double(search.firstDownloads) / Double(total.firstDownloads)
            }
        }

        if let sales = connect.sales {
            // 상품 목록을 알아야 인앱 결제를 이 앱의 것으로 셀 수 있다. 모르면 결제는 "모름" 으로 둔다.
            if let app = connect.connectApp(for: project), let products = connect.products(for: project) {
                let totals = sales.totals(app: app, products: products)
                input.paid = totals.purchases
                input.proceedsKRW = totals.money(connect.rates)?.krw ?? (totals.purchases == 0 ? 0 : nil)
                if !input.hasFunnel { input.downloads = totals.firstDownloads }
            } else if !input.hasFunnel, let trackId = keywords.trackId(for: project) {
                input.downloads = sales.totals(for: String(trackId)).firstDownloads
            }
        }

        if let released = keywords.storeApp(for: project)?.releasedAt {
            input.daysSinceUpdate = max(0, Calendar.current.dateComponents([.day], from: released, to: Date()).day ?? 0)
        }
        return input
    }

    /// 판정에 맞는 칸으로 — 페이월이 새면 앱 내 구입, 나머지는 유입.
    private func section(for app: AppPotential) -> FeedbackStore.ProjectSection {
        app.leaks.first == .paywall ? .purchases : .acquisition
    }

    // MARK: - 결론

    private func conclusion(_ ranked: [AppPotential]) -> some View {
        let fixable = ranked.filter { $0.kind == .fixable }
        let sleepers = ranked.filter(\.isSleeper)
        let retire = ranked.filter { $0.kind == .retire }
        let hit = ranked.first { $0.tier == .a }
        return VStack(alignment: .leading, spacing: 8) {
            Text(summary(fixable: fixable.count, sleepers: sleepers.count, retire: retire.count))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let hit {
                Text("지금 가장 많이 버는 앱은 \(hit.input.name)입니다. 많이 버는 앱은 대개 시간을 많이 들인 앱이라, 아래 차례는 매출이 아니라 **기준만큼만 고쳤을 때 더 붙을 유료 사용자**로 세웠습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let best = fixable.first, best.upsidePayers >= 1 {
                Label("먼저 볼 앱: \(best.input.name) — \(best.leaks[0].title), 고치면 한 달에 유료 약 \(Int(best.upsidePayers.rounded()))명",
                      systemImage: "arrow.up.right.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
    }

    private func summary(fixable: Int, sleepers: Int, retire: Int) -> String {
        var parts: [String] = []
        if fixable > 0 { parts.append("고치면 오를 앱 \(fixable)개") }
        if sleepers > 0 { parts.append("손 안 대도 받는 앱 \(sleepers)개") }
        if retire > 0 { parts.append("정리 후보 \(retire)개") }
        return parts.isEmpty ? "아직 가를 만한 숫자가 모이지 않았습니다." : parts.joined(separator: " · ")
    }

    // MARK: - 목표에서 거꾸로

    private var goalCard: some View {
        let goal = goal
        let soft = goal.downloadsNeeded(at: AppPotential.Benchmark.freemiumPaid)
        let hard = goal.downloadsNeeded(at: AppPotential.Benchmark.hardPaywallPaid)
        return VStack(alignment: .leading, spacing: 10) {
            Text("목표에서 거꾸로")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { targetStepper; priceStepper }
                VStack(alignment: .leading, spacing: 8) { targetStepper; priceStepper }
            }
            Text("유료 사용자 **\(AppFormat.count(Int(goal.payersNeeded.rounded(.up))))명**이 필요합니다(수수료 15%를 뗀 1인당 \(MoneyFormat.krw(goal.price * AppPotential.Benchmark.payout))).")
                .font(.body)
            Text("받은 사람의 2.1%가 사면(무료로 쓰다 사는 앱의 평균) 다운로드 \(AppFormat.count(Int(soft.rounded(.up))))건, 10.7%가 사면(처음부터 막는 앱) \(AppFormat.count(Int(hard.rounded(.up))))건입니다. 구독이면 달마다 쌓여 이보다 빨리 닿습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
    }

    private var targetStepper: some View {
        Stepper(value: $targetMan, in: 10...10_000, step: 10) {
            Text("한 달 목표 \(MoneyFormat.shortKRW(Double(targetMan) * 10_000))")
                .font(.body.monospacedDigit())
        }
        .fixedSize()
    }

    private var priceStepper: some View {
        Stepper(value: $price, in: 500...100_000, step: 500) {
            Text("한 사람이 내는 값 \(MoneyFormat.krw(Double(price)))")
                .font(.body.monospacedDigit())
        }
        .fixedSize()
    }

    // MARK: - 거르기

    private func filterBar(_ ranked: [AppPotential]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, title: "전체", count: ranked.count)
                ForEach(AppPotential.Kind.allCases) { kind in
                    let count = ranked.filter { $0.kind == kind }.count
                    if count > 0 { chip(kind, title: kind.rawValue, count: count) }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ kind: AppPotential.Kind?, title: String, count: Int) -> some View {
        let isOn = filter == kind
        let tint = kind.map(Self.tint) ?? .accentColor
        return Button {
            filter = isOn ? nil : kind
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text(AppFormat.count(count))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
            .font(.body)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary.opacity(0.6))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), 앱 \(count)개")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static func tint(_ kind: AppPotential.Kind) -> Color {
        switch kind {
        case .fixable: return .orange
        case .sleeper: return .purple
        case .working: return .green
        case .smallDemand: return .blue
        case .retire, .unknown: return .gray
        }
    }

    // MARK: - 카드

    private func card(_ app: AppPotential) -> some View {
        let input = app.input
        let tint = Self.tint(app.kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIcon(url: icons.url(for: input.project, keywords: keywords), size: 36)
                Text(input.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if app.isSleeper && app.kind != .sleeper {
                    Tag(text: "방치해도 받음", tint: .purple, isCompact: true)
                }
                Tag(text: app.kind.rawValue, tint: tint, isCompact: true)
                Tag(text: app.tier.rawValue, tint: app.tier == .a ? .green : nil, isCompact: true)
            }

            Text(app.headline)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let action = app.action {
                Label(action, systemImage: app.leaks.first?.systemImage ?? "arrow.right.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if input.hasFunnel || input.paid != nil {
                VStack(spacing: 6) {
                    ForEach(app.steps) { step in gauge(step) }
                }
            }

            if app.upsidePayers >= 1 {
                Text("기준만큼만 올리면 한 달에 유료 약 \(Int(app.upsidePayers.rounded()))명 ≈ \(MoneyFormat.shortKRW(app.upsidePayers * goal.price * AppPotential.Benchmark.payout)) 더")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.green)
            }

            if input.downloads > 0 {
                Text(goal.reading(downloads: input.downloads))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(facts(input))
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// 깔때기 한 단계 — 이 앱의 비율을 막대로, 업계 평균을 세로 금으로.
    /// 막대의 끝은 기준의 두 배다. 기준이 한가운데에 서서 넘었는지가 한눈에 보인다.
    private func gauge(_ step: AppPotential.Step) -> some View {
        let color: Color = step.rate == nil ? .gray : (step.isBelow ? .red : .green)
        let fill = step.rate.map { min(1, $0 / (step.benchmark * 2)) } ?? 0
        return HStack(spacing: 8) {
            Text(step.name)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.opacity(0.75))
                        .frame(width: max(step.rate == nil ? 0 : 3, proxy.size.width * fill))
                    Rectangle().fill(.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * 0.5 - 1)
                }
            }
            .frame(height: 8)
            Text(step.rate == nil ? "표본 적음" : AppPotential.percent(step.rate))
                .font(.body.monospacedDigit().weight(step.isBelow ? .semibold : .regular))
                .foregroundStyle(step.rate == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
                .frame(width: 76, alignment: .trailing)
        }
        .help("\(step.name): \(AppFormat.count(step.from)) 중 \(AppFormat.count(step.to)) · 업계 평균 \(AppPotential.percent(step.benchmark))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.name) \(step.rate == nil ? "표본 적음" : AppPotential.percent(step.rate)), 평균 \(AppPotential.percent(step.benchmark))")
    }

    /// 판정의 재료를 한 줄로 — 숫자를 다시 계산하지 않아도 되게 맨 아래에 작게.
    private func facts(_ input: AppPotential.Input) -> String {
        var parts: [String] = []
        if input.hasFunnel { parts.append("노출 \(AppFormat.count(input.impressions))") }
        parts.append("다운로드 \(AppFormat.count(input.downloads))")
        if let share = input.searchShare { parts.append("검색 \(AppPotential.percent(share))") }
        if let paid = input.paid { parts.append("결제 \(AppFormat.count(paid))") }
        if let krw = input.proceedsKRW, krw > 0 { parts.append("수익 \(MoneyFormat.shortKRW(krw))") }
        if let days = input.daysSinceUpdate { parts.append("업데이트 \(days)일 전") }
        return "30일 · " + parts.joined(separator: " · ")
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("기준은 업계 평균입니다(노출 → 조회 6~12%, 조회 → 받기 25% 안팎, 받기 → 유료 2.1% · 10.7%. Adapty · RevenueCat 공개 자료). 카테고리마다 크게 달라, 빨간 막대는 판결이 아니라 먼저 볼 곳입니다. 막대의 세로 금이 평균입니다.")
            Text("\"고치면 더 붙을 유료\" 는 노출을 그대로 두고 깔때기만 평균으로 올렸을 때의 어림입니다. 방치 여부는 스토어의 마지막 업데이트 날짜로 봅니다 — 들인 시간 자체는 허브가 모릅니다.")
            if let last = connect.sales?.dayKeys.last {
                Text("판매 기록은 \(last)까지 받았습니다.")
            }
        }
        .font(.body)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func notice(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "key")
                .font(.body.weight(.semibold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.1)))
    }
}

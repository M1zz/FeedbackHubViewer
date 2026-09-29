//
//  AcquisitionView.swift
//  FeedbackHubViewer
//
//  유입 탭. 앱에 사람이 어떻게 닿고 어디서 새는지를 **결론부터** 보여 준다.
//
//  읽는 차례:
//   1. 한 줄 판정 — 지금 어느 구역이 새나
//   2. 지금 할 일 하나
//   3. 구역별 한 줄(숫자 하나 + 뜻)
//   4. 받는 사람이 주로 어디서 오나
//  지도 원본(길 목록 · 남은 할 일 전부)은 접어 둔다. 머리로 합쳐야 하는 표는 앞에 두지
//  않는다 — 합친 결과가 위의 판정이다. 계산은 `AcquisitionDiagnosis` 가 한다.
//

import SwiftUI
import Charts

struct AcquisitionView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// nil == 전체 프로젝트.
    let project: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(AcquisitionCatalog.failures) { failure in
                    Card(title: "유입 지도를 못 읽었습니다", systemImage: "exclamationmark.triangle") {
                        Text("\(failure.file): \(failure.reason)")
                            .font(.body)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let project {
                    if let map = AcquisitionCatalog.map(for: project) {
                        AcquisitionDetail(project: project, map: map)
                    } else {
                        missingMap
                    }
                } else {
                    AcquisitionOverview()
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var missingMap: some View {
        Card(title: "유입 지도가 없습니다", systemImage: "map") {
            Text("이 앱의 리포에 docs/engineering/acquisition.json 을 두고 scripts/spec-sources.sh 에 한 줄 더한 뒤 scripts/sync-stats-specs.sh 를 돌리면, 어디서 새는지 판정이 여기 나옵니다. ClipKeyboard 의 파일을 본으로 쓰면 됩니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 한 앱

private struct AcquisitionDetail: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String
    let map: AcquisitionMap

    @State private var showsMap = false

    var body: some View {
        let diagnosis = store.acquisitionDiagnosis(for: project, map: map, connect: connect, keywords: keywords)

        VStack(alignment: .leading, spacing: 14) {
            verdict(diagnosis)

            if !diagnosis.missing.isEmpty {
                MissingInputsCard(project: project, missing: diagnosis.missing)
            }

            if let aso = diagnosis.aso {
                ASOPrescriptionCard(project: project, aso: aso)
            }

            VStack(spacing: 10) {
                ForEach(diagnosis.readings) { reading in
                    ReadingRow(reading: reading, isLeak: reading.zone == diagnosis.leak)
                }
            }

            if case .ready(let funnel)? = connect.funnels[project]?.value, funnel.instances > 0 {
                StoreFlowCard(funnel: funnel, sourceMix: diagnosis.sourceMix)
            } else if let mix = diagnosis.sourceMix {
                Card(title: "받는 사람은 어디서 오나", systemImage: "arrow.triangle.branch") {
                    Text(mix)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup(isExpanded: $showsMap) {
                MapDetail(map: map)
                    .padding(.top, 8)
            } label: {
                Text("지도 원본 · 남은 할 일 전부")
                    .font(.headline)
            }
            .padding(Platform.cardPadding)
            .cardSurface()
        }
        .task(id: project) {
            await connect.loadFunnel(bundleID: project)
            await connect.loadMetadata(bundleID: project)
        }
    }

    private func verdict(_ diagnosis: AcquisitionDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StateDot(state: diagnosis.headlineState)
                Text(diagnosis.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = diagnosis.action {
                VStack(alignment: .leading, spacing: 4) {
                    Label("지금 할 일", systemImage: "hand.point.right")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text(action.title)
                        .font(.body.weight(.semibold))
                    if let detail = action.detail {
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 10, bordered: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }
}

private struct ReadingRow: View {
    let reading: AcquisitionDiagnosis.Reading
    let isLeak: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StateDot(state: reading.state)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reading.zone.title)
                        .font(.headline)
                    Text(reading.zone.question)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(reading.figure ?? "모름")
                        .font(.figure(.title3))
                        .foregroundStyle(reading.figure == nil ? .secondary : StateDot.color(reading.state))
                }
                Text(reading.meaning)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Platform.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            if isLeak {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.5), lineWidth: 1.5)
            }
        }
    }
}

struct StateDot: View {
    let state: AcquisitionDiagnosis.State

    var body: some View {
        Circle()
            .fill(Self.color(state))
            .frame(width: 12, height: 12)
            .accessibilityLabel(Self.name(state))
    }

    static func color(_ state: AcquisitionDiagnosis.State) -> Color {
        switch state {
        case .leaking: return .red
        case .watch: return .orange
        case .healthy: return .green
        case .unknown: return .gray
        }
    }

    static func name(_ state: AcquisitionDiagnosis.State) -> String {
        switch state {
        case .leaking: return "샘"
        case .watch: return "지켜봄"
        case .healthy: return "괜찮음"
        case .unknown: return "모름"
        }
    }
}

// MARK: - 스토어 흐름 · 출처

/// 노출 → 페이지 조회 → 첫 다운로드를 막대로, 첫 다운로드의 출처를 도넛으로.
private struct StoreFlowCard: View {
    let funnel: StoreFunnel
    let sourceMix: String?

    /// 출처마다 고정 색. 순위가 바뀌어도 색은 출처를 따라간다.
    private static let sourceOrder = ["App Store search", "App Store browse", "Web referrer", "App referrer", "Unavailable"]
    private static func color(_ source: String) -> Color {
        switch source {
        case "App Store search": return .blue
        case "App Store browse": return .teal
        case "Web referrer": return .orange
        case "App referrer": return .indigo
        default: return .gray
        }
    }

    private struct Stage: Identifiable {
        let label: String
        let value: Int
        var id: String { label }
    }

    var body: some View {
        let total = funnel.total
        let stages = [Stage(label: "노출", value: total.impressions),
                      Stage(label: "페이지 조회", value: total.pageViews),
                      Stage(label: "첫 다운로드", value: total.firstDownloads)]
        let sources = funnel.sources
            .map { (key: $0.key, value: $0.value.firstDownloads) }
            .filter { $0.value > 0 }
            .sorted { (Self.sourceOrder.firstIndex(of: $0.key) ?? 99) < (Self.sourceOrder.firstIndex(of: $1.key) ?? 99) }
        let downloads = sources.reduce(0) { $0 + $1.value }

        Card(title: "스토어에서 받기까지 (최근 \(funnel.days)일)", systemImage: "arrow.triangle.branch") {
            if let sourceMix {
                Text(sourceMix)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            FunnelChart(stages: stages.map { FunnelChart.Stage(label: $0.label, count: $0.value) })

            if downloads > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) { donut(sources, downloads); legend(sources, downloads) }
                    VStack(alignment: .leading, spacing: 12) { donut(sources, downloads); legend(sources, downloads) }
                }
            }
        }
    }

    private func donut(_ sources: [(key: String, value: Int)], _ downloads: Int) -> some View {
        Chart(sources, id: \.key) { source in
            SectorMark(angle: .value("첫 다운로드", source.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(Self.color(source.key))
                .cornerRadius(3)
        }
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(AppFormat.count(downloads)).font(.title3.weight(.semibold))
                Text("첫 다운로드").font(.body).foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityLabel("첫 다운로드 출처 비중")
    }

    private func legend(_ sources: [(key: String, value: Int)], _ downloads: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sources, id: \.key) { source in
                HStack(spacing: 8) {
                    Circle().fill(Self.color(source.key)).frame(width: 10, height: 10)
                    Text(StoreFunnel.label(forSource: source.key)).font(.body)
                    Text(AcquisitionDiagnosis.percent(Double(source.value) / Double(downloads)))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 넣어야 할 정보

/// 판단을 막고 있는 것. 종류마다 그 자리에서 해결하는 단추를 단다.
private struct MissingInputsCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String
    let missing: [AcquisitionDiagnosis.MissingInput]

    var body: some View {
        Card(title: "판단하려면 이것이 필요합니다", systemImage: "tray.and.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(missing) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                        Text(item.why)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.terms.isEmpty {
                            Text(item.terms.joined(separator: ", "))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        button(for: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func button(for item: AcquisitionDiagnosis.MissingInput) -> some View {
        let country = keywords.countries.first ?? "kr"
        switch item.kind {
        case .ascKey:
            OpenSettingsButton(title: "설정 열기").font(.body)
        case .analyticsRequest:
            Button("리포트 요청 만들기") {
                Task { await connect.requestAnalytics(bundleID: project) }
            }
        case .metadata:
            Button("다시 읽기") {
                Task { await connect.loadMetadata(bundleID: project, force: true) }
            }
        case .storeLink:
            Button("키워드 탭 열기") { store.open(project: project, section: .keywords) }
        case .noKeywords:
            Button(keywords.isChecking ? "찾는 중…" : "키워드 자동 찾기") {
                keywords.discover(for: project)
            }
            .disabled(keywords.isChecking)
        case .untrackedTerms:
            Button("이 단어들 추적하고 지금 재기") {
                for term in item.terms {
                    keywords.add(term: term, countries: [country], for: project)
                    keywords.checkNow(TrackedKeyword(term: term, country: country))
                }
            }
        case .staleRanks:
            Button(keywords.isChecking ? "확인 중…" : "지금 확인") {
                keywords.check(bundleIds: store.allProjectKeys)
            }
            .disabled(keywords.isChecking)
        case .analyticsPending, .ladder:
            EmptyView()
        }
    }
}

// MARK: - 검색 처방

/// 키워드 필드에서 무엇을 빼고 무엇을 넣을지. 새 필드를 채운 편집기로 바로 연다.
private struct ASOPrescriptionCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    let aso: ASOPrescription

    @State private var isEditing = false
    @State private var showsWhy = false

    var body: some View {
        Card(title: "검색 처방 (\(aso.locale))", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if aso.swaps.isEmpty && aso.dropsOnly.isEmpty {
                    Text("지금 필드에서 바꿀 단어를 찾지 못했습니다. 잰 순위와 경쟁 앱 이름으로는 이게 최선이에요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(aso.swaps) { swap in
                            swapRow(swap)
                        }
                        ForEach(aso.dropsOnly) { removal in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(removal.term).strikethrough().foregroundStyle(.red)
                                Text("빼기").foregroundStyle(.secondary)
                            }
                            .font(.body)
                        }
                    }
                }

                if let hint = aso.subtitleHint {
                    Label(hint, systemImage: "text.badge.star")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if aso.hasChange {
                    HStack {
                        Button("이 필드로 고치기") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                        CopyButton(text: aso.proposedField)
                    }
                    DisclosureGroup("왜 이렇게 바꾸나 · 새 필드 전문", isExpanded: $showsWhy) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(aso.swaps) { swap in
                                if let from = swap.from {
                                    Text("'\(from.term)' 빼기: \(from.reason)")
                                }
                                Text("'\(swap.to.term)' 넣기: \(swap.to.reason)")
                            }
                            ForEach(aso.dropsOnly) { Text("'\($0.term)' 빼기: \($0.reason)") }
                            Text("새 필드 (\(aso.proposedField.count)/\(StoreMetadata.Limit.keywords)자)")
                                .font(.body.weight(.semibold))
                                .padding(.top, 4)
                            Text(aso.proposedField)
                                .textSelection(.enabled)
                        }
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    }
                    .font(.body)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let metadata = connect.metadata[project]?.value {
                MetadataEditor(project: project, metadata: metadata, locale: aso.locale,
                               proposedKeywords: aso.proposedField) { isEditing = false }
            }
        }
    }

    private var summary: String {
        var text = "추적하는 검색어 \(aso.trackedCount)개 중 \(aso.rankedCount)개에 잡히고, 상위 10 안은 \(aso.topTen.count)개"
        text += aso.topTen.isEmpty ? "입니다." : "(\(aso.topTen.prefix(3).joined(separator: ", ")))입니다."
        return text
    }

    private func swapRow(_ swap: ASOPrescription.Swap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let from = swap.from {
                Text(from.term).strikethrough().foregroundStyle(.red)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
            } else {
                Image(systemName: "plus").foregroundStyle(.secondary)
            }
            Text(swap.to.term).foregroundStyle(.green).fontWeight(.semibold)
        }
        .font(.body)
    }
}

// MARK: - 접어 둔 원본

private struct MapDetail: View {
    let map: AcquisitionMap

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group)
                        .font(.headline)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(map.channels.filter { ($0.group ?? "기타") == group }) { channel in
                            chip(channel)
                        }
                    }
                }
            }
            legend

            let steps = map.nextSteps.filter { $0.done != true }
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("남은 할 일")
                        .font(.headline)
                    ForEach(steps) { step in
                        Text("\(step.zone.title) · \(step.title)")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let url = map.mapURL {
                Link("그림으로 된 지도 열기", destination: url)
                    .font(.body)
            }
            if let asOf = map.asOf {
                Text("지도 기준일 \(asOf)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groups: [String] {
        var seen: [String] = []
        for channel in map.channels {
            let group = channel.group ?? "기타"
            if !seen.contains(group) { seen.append(group) }
        }
        return seen
    }

    private func chip(_ channel: AcquisitionMap.Channel) -> some View {
        Text(channel.name)
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Self.color(channel.measure).opacity(channel.status == .active ? 0.18 : 0.06),
                        in: Capsule())
            .overlay {
                if channel.status != .active {
                    Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(channel.status == .active ? Color.primary : Color.secondary)
            .help(channel.note ?? "")
    }

    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            legendItem("따로 셈", .green)
            legendItem("섞여 셈", .orange)
            legendItem("못 셈", .red)
            Text("점선은 아직 안 쓰는 길")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.6)).frame(width: 10, height: 10)
            Text(title).font(.body).foregroundStyle(.secondary)
        }
    }

    static func color(_ measure: AcquisitionMap.Channel.Measure) -> Color {
        switch measure {
        case .separate: return .green
        case .mixed: return .orange
        case .none: return .red
        }
    }
}

// MARK: - 전체 프로젝트

/// 앱마다 판정 한 줄. 어느 앱의 어느 구역부터 손댈지가 이 화면의 요점이다.
private struct AcquisitionOverview: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore

    var body: some View {
        let rows = AcquisitionCatalog.all.map { map in
            (map: map, diagnosis: store.acquisitionDiagnosis(for: map.appId, map: map, connect: connect, keywords: keywords))
        }
        .sorted { $0.diagnosis.headlineState < $1.diagnosis.headlineState }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.map.appId) { row in
                Button {
                    store.open(project: row.map.appId, section: .acquisition)
                } label: {
                    overviewRow(row.map, row.diagnosis)
                }
                .buttonStyle(.plain)
            }

            let missing = store.allProjectKeys.filter {
                $0 != Feedback.unclassifiedProject && AcquisitionCatalog.map(for: $0) == nil
            }
            if !missing.isEmpty {
                Text("유입 지도가 없는 앱 \(missing.count)개: " + missing.map { store.displayName(for: $0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .task {
            for map in AcquisitionCatalog.all {
                await connect.loadFunnel(bundleID: map.appId)
                await connect.loadMetadata(bundleID: map.appId)
            }
        }
    }

    private func overviewRow(_ map: AcquisitionMap, _ diagnosis: AcquisitionDiagnosis) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StateDot(state: diagnosis.headlineState)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.displayName(for: map.appId))
                    .font(.headline)
                Text(diagnosis.headline)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = diagnosis.action {
                    Text("지금 할 일: \(action.title)")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .padding(Platform.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 입력 모으기

extension FeedbackStore {
    /// 지도 · 사용 통계 · App Store Connect · 키워드 순위를 한데 모아 판정한다.
    @MainActor
    func acquisitionDiagnosis(for project: String, map: AcquisitionMap,
                              connect: AppStoreConnectStore,
                              keywords: KeywordStore) -> AcquisitionDiagnosis {
        var missing: [AcquisitionDiagnosis.MissingInput] = []
        var storeInput: AcquisitionDiagnosis.Store?

        if !connect.isConfigured {
            missing.append(.init(kind: .ascKey, title: "App Store Connect 키 넣기",
                                 why: "노출 · 페이지 조회 · 첫 다운로드와 지금 키워드 필드를 여기서 읽어야 가게 앞과 홍보를 판정합니다."))
        } else {
            switch connect.funnels[project] {
            case .loaded(.noRequest)?:
                missing.append(.init(kind: .analyticsRequest, title: "App Store 분석 리포트 요청 만들기",
                                     why: "한 번만 하면 1~2일 뒤부터 하루치씩 쌓입니다. 이게 있어야 유입이 느는지 주는지 압니다."))
            case .loaded(.ready(let funnel))?:
                if funnel.instances == 0 {
                    missing.append(.init(kind: .analyticsPending, title: "리포트가 쌓이기를 기다리기",
                                         why: "요청은 있지만 아직 파일이 없습니다. 1~2일 걸립니다."))
                } else {
                    let total = funnel.total
                    storeInput = .init(impressions: total.impressions, pageViews: total.pageViews,
                                       firstDownloads: total.firstDownloads, days: funnel.days,
                                       downloadsBySource: funnel.sources.mapValues(\.firstDownloads),
                                       impressionsBySource: funnel.sources.mapValues(\.impressions),
                                       pageViewsBySource: funnel.sources.mapValues(\.pageViews),
                                       dailyDownloads: funnel.daily.mapValues(\.firstDownloads))
                }
            default:
                break
            }
            if case .failed(let message)? = connect.metadata[project] {
                missing.append(.init(kind: .metadata, title: "스토어 메타데이터 다시 읽기", why: message))
            }
        }

        // 검색 처방 ----------------------------------------------------------
        let country = keywords.countries.first ?? "kr"
        var aso: ASOPrescription?
        if keywords.storeApp(for: project) == nil {
            missing.append(.init(kind: .storeLink, title: "키워드 탭에서 이 앱을 App Store 와 잇기",
                                 why: "이어야 검색어마다 이 앱의 순위를 잴 수 있습니다."))
        } else {
            let standings = keywords.standings(for: project).filter { $0.keyword.country == country }
            if standings.isEmpty {
                missing.append(.init(kind: .noKeywords, title: "키워드 자동 찾기 돌리기",
                                     why: "추적하는 검색어가 없어 무엇을 빼고 넣을지 판단할 수 없습니다. 경쟁 앱 이름에서 후보를 뽑아 실제로 검색해 봅니다(30초쯤)."))
            } else {
                let latest = standings.compactMap(\.seenAt).max()
                if let latest, Date().timeIntervalSince(latest) > 7 * 86_400 {
                    let days = Int(Date().timeIntervalSince(latest) / 86_400)
                    missing.append(.init(kind: .staleRanks, title: "키워드 순위 다시 확인하기",
                                         why: "마지막으로 잰 지 \(days)일 됐습니다. 낡은 순위로 빼고 넣으면 틀립니다."))
                }
            }
            if let metadata = connect.metadata[project]?.value,
               let locale = MetadataAudit.locale(forStorefront: country, available: metadata.locales),
               let text = metadata.live.locales[locale] {
                let rankings = standings.map {
                    ASOPrescription.Ranking(term: $0.keyword.term, rank: $0.rank,
                                            unchecked: $0.rank == nil && $0.resultCount == 0)
                }
                let rivals = keywords.competitors(for: project).filter { $0.timesAbove > 0 }.map(\.app.name)
                let prescription = ASOPrescription.make(text: text, rankings: rankings, rivalNames: rivals)
                aso = prescription
                if !prescription.untracked.isEmpty {
                    missing.append(.init(kind: .untrackedTerms,
                                         title: "키워드 필드의 \(prescription.untracked.count)개 단어 순위 재기",
                                         why: "순위를 모르는 단어는 뺄지 남길지 판단하지 않았습니다.",
                                         terms: prescription.untracked))
                }
            }
        }

        if map.appZone?.activation != nil, acquisitionLadder(for: project, map: map) == nil {
            missing.append(.init(kind: .ladder, title: "앱 구역 사다리 값 받기",
                                 why: "지도가 가리키는 \"\(map.appZone?.activation ?? "")\" 칸을 보낸 설치가 아직 없습니다. 새 버전이 퍼지면 채워집니다."))
        }

        return AcquisitionDiagnosis.make(map: map,
                                         ladder: acquisitionLadder(for: project, map: map),
                                         paywall: acquisitionPaywall(for: project, map: map),
                                         store: storeInput, aso: aso, missing: missing)
    }
}

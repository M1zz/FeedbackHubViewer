//
//  KeywordRecommendationCard.swift
//  FeedbackHubViewer
//
//  추천 검색어 카드. 검색이 많이 되고 이 앱이 올라갈 수 있는 말을 점수 순으로 세우고,
//  말마다 무엇을 할지(지키기 · 올릴 만함 · 새로 노리기)를 붙인다. 계산은
//  `KeywordRecommendation`, 요청은 `KeywordStore.recommend(for:country:)` 가 한다.
//

import SwiftUI

struct KeywordRecommendationCard: View {
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    /// 새로 돌릴 가게. 키워드 추가 칸에서 고른 첫 가게를 따른다.
    var country: String = "kr"

    /// 한 번에 보여 줄 줄 수. 나머지는 "더 보기"로.
    @State private var showsAll = false
    /// App Store 키워드 칸에 넣으려고 고른 검색어.
    @State private var picked: Set<String> = []
    @State private var isEditing = false
    private static let collapsedCount = 10

    var body: some View {
        Card(title: "추천 검색어", systemImage: "star.bubble") {
            if let report = keywords.recommendations[project] {
                content(report)
            } else {
                Text("자동완성에 얼마나 빨리 뜨는지로 **많이 검색되는 말**을 고르고, 그 말에서 지금 몇 위인지로 **올라갈 수 있는 말**을 가려 순위를 매깁니다.")
                    .font(.hubCallout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            runButton
        }
        .task(id: project) {
            guard connect.isConfigured else { return }
            await connect.loadMetadata(bundleID: project)
            await connect.loadFunnel(bundleID: project)
        }
        .sheet(isPresented: $isEditing) {
            if let metadata = connect.metadata[project]?.value, let locale = locale(metadata) {
                MetadataEditor(project: project, metadata: metadata, locale: locale,
                               addingKeywords: pickedInOrder) {
                    isEditing = false
                    picked = []
                }
            }
        }
    }

    // MARK: - App Store 에 올리기

    /// 고른 차례가 아니라 추천 순위대로 붙인다. 칸이 100자라 앞의 것이 살아남아야 한다.
    private var pickedInOrder: [String] {
        (keywords.recommendations[project]?.items ?? []).map(\.term).filter(picked.contains)
    }

    private func locale(_ metadata: StoreMetadata) -> String? {
        let country = keywords.recommendations[project]?.country ?? country
        return MetadataAudit.locale(forStorefront: country, available: metadata.locales)
            ?? (metadata.locales.contains("ko") ? "ko" : metadata.locales.first)
    }

    /// 넣을 수 없으면 그 이유. nil 이면 넣을 수 있다.
    private var uploadBlocker: String? {
        guard connect.isConfigured else { return "App Store Connect 키를 설정에 넣으면 여기서 바로 키워드 칸에 넣을 수 있습니다." }
        switch connect.metadata[project] {
        case nil, .loading?: return "App Store Connect 메타데이터를 읽는 중입니다."
        case .failed(let message)?: return message
        case .loaded(let metadata)?:
            guard metadata.draft?.isVersionEditable == true else {
                return "키워드 칸은 제출 전 버전에서만 고쳐집니다. App Store Connect에서 새 버전을 만들면 넣을 수 있어요."
            }
            return nil
        }
    }

    @ViewBuilder
    private var uploadBar: some View {
        if let blocker = uploadBlocker {
            Text(blocker)
                .font(.hubCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                Button {
                    isEditing = true
                } label: {
                    Label(picked.isEmpty ? "검색어를 골라 키워드 칸에 넣기" : "키워드 칸에 넣기 (\(picked.count)개)",
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty)
                Text("바뀌는 것을 확인한 뒤 저장하면 다음 버전 심사와 함께 나갑니다.")
                    .font(.hubCaption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 결과

    @ViewBuilder
    private func content(_ report: KeywordRecommendation.Report) -> some View {
        if report.items.isEmpty {
            Text("검색이 많이 되면서 이 앱과 관련 있는 말을 찾지 못했습니다.")
                .font(.hubCallout)
                .foregroundStyle(.secondary)
        } else {
            goal(report)
            Divider()
            let shown = showsAll ? report.items : Array(report.items.prefix(Self.collapsedCount))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    row(rank: index + 1, item, country: report.country,
                        trend: KeywordRecommendation.trend(item, previous: report.previousPopularity))
                }
            }
            uploadBar
            if report.items.count > Self.collapsedCount {
                Button(showsAll ? "접기" : "\(report.items.count - Self.collapsedCount)개 더 보기") {
                    showsAll.toggle()
                }
                .font(.hubCaption)
            }
        }

        if !report.dropped.isEmpty {
            let listed = report.dropped.prefix(12).joined(separator: ", ")
            let more = report.dropped.count > 12 ? " 외 \(report.dropped.count - 12)개" : ""
            Text("많이 찾지만 이 앱을 찾는 사람의 말이 아니라서 뺀 것: " + listed + more)
                .font(.hubCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("\(Storefront.name(for: report.country)) · \(AppFormat.relative(report.measuredAt)) 기준. 인기는 검색량이 아니라 자동완성에 뜨는 빠르기로 잰 차례입니다. Apple 은 검색량을 공개하지 않습니다. 경쟁은 그 검색어 상위 5개 앱의 평점 수로 잽니다.")
            .font(.hubCaption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 목표

    /// 맨 위 성적표. 점령도 → 검색으로 온 사람 → 다음 할 일 한 줄.
    @ViewBuilder
    private func goal(_ report: KeywordRecommendation.Report) -> some View {
        let share = report.share
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("검색 점령도")
                    .font(.body.weight(.semibold))
                Text("\(share)")
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("/ 100")
                    .font(.hubCaption)
                    .foregroundStyle(.secondary)
                if let before = report.previousShare, before != share {
                    let delta = share - before
                    Text(delta > 0 ? "지난번보다 +\(delta)" : "지난번보다 −\(-delta)")
                        .font(.hubCaption.weight(.semibold))
                        .foregroundStyle(delta > 0 ? .green : .orange)
                }
            }
            MeterBar(ratio: Double(share) / 100, height: 8, tint: .green)
            Text("많이 찾는 말 가운데 우리가 10위 안에 든 몫입니다. 100이면 사람들이 찾는 말마다 첫 화면에 우리가 보입니다.")
                .font(.hubCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let inflow = searchInflow {
                Text(inflow)
                    .font(.hubCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            nextStep(report)
        }
        .accessibilityElement(children: .combine)
    }

    /// 키워드 작업의 성적표 — App Store 검색에서 실제로 온 사람.
    private var searchInflow: String? {
        guard case .loaded(.ready(let funnel))? = connect.funnels[project],
              let search = funnel.sources["App Store search"] else { return nil }
        var text = "최근 \(funnel.days)일 App Store 검색으로 온 첫 다운로드 \(AppFormat.count(search.firstDownloads))회"
        if let conversion = search.conversion { text += String(format: " · 검색 전환 %.1f%%", conversion * 100) }
        return text
    }

    @ViewBuilder
    private func nextStep(_ report: KeywordRecommendation.Report) -> some View {
        let claims = report.items.filter { $0.verdict == .claim }
        let climbs = report.items.filter { $0.verdict == .climb }
        let line: String = {
            if !claims.isEmpty {
                let names = claims.prefix(3).map { "‘\($0.term)’" }.joined(separator: ", ")
                return "선점 기회 \(claims.count)개. \(names)부터 키워드 칸에 걸어 두세요. 상위 앱이 약해서 먼저 건 쪽이 자리를 갖습니다."
            }
            if !climbs.isEmpty {
                return "올릴 만한 말 \(climbs.count)개. 이름이나 부제에 넣으면 10위 안으로 들어올 만합니다."
            }
            if report.share >= 100 {
                return "찾는 말마다 10위 안입니다. 리뷰와 평점을 쌓아 이 자리를 지키세요."
            }
            return "지금은 상위 앱이 강한 말뿐입니다. 다시 만들기로 후보를 넓혀 보세요."
        }()
        Label {
            Text(line).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
        }
        .font(.hubCallout)
        if !claims.isEmpty, uploadBlocker == nil {
            Button("선점 기회 \(claims.count)개 모두 고르기") {
                picked.formUnion(claims.map(\.term))
            }
            .font(.hubCaption)
        }
    }

    private func row(rank: Int, _ item: KeywordRecommendation.Item, country: String, trend: String?) -> some View {
        let verdict = item.verdict
        let tracked = keywords.isTracked(item.term, country: country, for: project)
        let isPicked = picked.contains(item.term)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if isPicked { picked.remove(item.term) } else { picked.insert(item.term) }
            } label: {
                Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("App Store 키워드 칸에 넣을 검색어로 고르기")
            .accessibilityLabel(isPicked ? "\(item.term) 고름" : "\(item.term) 고르기")
            Text("\(rank)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(rank <= 3 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.term)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Tag(text: verdict.label, tint: Self.tint(verdict), isCompact: true)
                }
                HStack(spacing: 16) {
                    meter("인기", item.popularity, tint: Self.tint(verdict))
                    meter("경쟁", item.competition, tint: .secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("인기 \(item.popularity), 경쟁 \(item.competition)")
                Text([KeywordRecommendation.reason(item), trend].compactMap { $0 }.joined(separator: " · "))
                    .font(.hubCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if tracked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("추적 중")
                    .accessibilityLabel("추적 중")
            } else {
                Button {
                    keywords.add(term: item.term, countries: [country], for: project)
                    keywords.checkNow(TrackedKeyword(term: item.term, country: country))
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("순위 추적에 넣기")
                .accessibilityLabel("\(item.term) 추적하기")
            }
        }
        .padding(.vertical, 8)
    }

    /// 0~100 값 하나. 이름 · 막대 · 숫자를 한 줄로.
    private func meter(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.hubCaption)
                .foregroundStyle(.secondary)
            MeterBar(ratio: Double(value) / 100, tint: tint)
            Text("\(value)")
                .font(.hubCaption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
        }
    }

    // MARK: - 돌리기

    private var runButton: some View {
        HStack(spacing: 8) {
            Button {
                keywords.recommend(for: project, country: country)
            } label: {
                Label(keywords.recommendations[project] == nil ? "추천 만들기" : "다시 만들기",
                      systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .disabled(keywords.isChecking)
            Text("후보 서른 개쯤을 하나씩 확인해 2~3분 걸립니다.")
                .font(.hubCaption2)
                .foregroundStyle(.secondary)
        }
    }

    static func tint(_ verdict: KeywordRecommendation.Verdict) -> Color {
        switch verdict {
        case .keep: return .green
        case .climb: return .orange
        case .claim: return .purple
        case .target: return .blue
        }
    }
}

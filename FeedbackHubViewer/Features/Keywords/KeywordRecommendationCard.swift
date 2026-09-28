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
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            runButton
        }
        .task(id: project) {
            if connect.isConfigured { await connect.loadMetadata(bundleID: project) }
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
                .font(.caption)
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
                    .font(.caption2)
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
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            let shown = showsAll ? report.items : Array(report.items.prefix(Self.collapsedCount))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    row(rank: index + 1, item, country: report.country)
                }
            }
            uploadBar
            if report.items.count > Self.collapsedCount {
                Button(showsAll ? "접기" : "\(report.items.count - Self.collapsedCount)개 더 보기") {
                    showsAll.toggle()
                }
                .font(.caption)
            }
        }

        if !report.dropped.isEmpty {
            let listed = report.dropped.prefix(12).joined(separator: ", ")
            let more = report.dropped.count > 12 ? " 외 \(report.dropped.count - 12)개" : ""
            Text("많이 찾지만 이 앱을 찾는 사람의 말이 아니라서 뺀 것: " + listed + more)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("\(Storefront.name(for: report.country)) · \(AppFormat.relative(report.measuredAt)) 기준. 인기는 검색량이 아니라 자동완성에 뜨는 빠르기로 잰 차례입니다. Apple 은 검색량을 공개하지 않습니다.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(rank: Int, _ item: KeywordRecommendation.Item, country: String) -> some View {
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
                        .lineLimit(1)
                    Tag(text: verdict.label, tint: Self.tint(verdict), isCompact: true)
                    Spacer(minLength: 4)
                    Text("인기 \(item.popularity)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                MeterBar(ratio: Double(item.popularity) / 100, tint: Self.tint(verdict))
                Text(KeywordRecommendation.reason(item))
                    .font(.caption)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    static func tint(_ verdict: KeywordRecommendation.Verdict) -> Color {
        switch verdict {
        case .keep: return .green
        case .climb: return .orange
        case .target: return .blue
        }
    }
}

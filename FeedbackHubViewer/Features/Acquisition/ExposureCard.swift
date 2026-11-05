//
//  ExposureCard.swift
//  FeedbackHubViewer
//
//  스토어 어디에 보였나 — 둘러보기가 튄 날 · 나라와, 지금 오른 카테고리 차트.
//  계산은 `StoreExposure`.
//

import SwiftUI

struct ExposureCard: View {
    let funnel: StoreFunnel
    let bundleID: String

    @State private var ranks: Ranks = .loading

    private enum Ranks {
        case loading
        case blocked
        case ready([StoreExposure.ChartRank], countries: Int)
    }

    var body: some View {
        let browse = funnel.sources["App Store browse"]?.impressions ?? 0
        let impressions = funnel.total.impressions
        let spikes = Array(StoreExposure.spikes(funnel.browse).prefix(6))

        Card(title: "스토어 어디에 보였나", systemImage: "sparkles.rectangle.stack") {
            if impressions > 0 {
                Text("최근 \(funnel.days)일 둘러보기 노출 \(AppFormat.count(browse))회 · 전체 노출의 \(AcquisitionDiagnosis.percent(Double(browse) / Double(impressions)))")
                    .font(.body.weight(.semibold))
            }

            section("둘러보기가 튄 날") {
                if spikes.isEmpty {
                    Text("평소와 크게 다른 날이 없어요.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(spikes) { spike in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.day(spike.date)).monospacedDigit()
                            Text(spike.territory.map(Self.country) ?? "여러 나라 함께")
                                .fontWeight(spike.territory == nil ? .regular : .semibold)
                            Spacer(minLength: 8)
                            Text("\(AppFormat.count(spike.count))회 · 평소 \(AppFormat.count(spike.usual))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("한 나라만 튄 날은 그 나라 차트 · 추천 · 에디터 모음 어딘가에 걸렸을 가능성이 커요. 여러 나라가 함께 튄 날은 업데이트가 나간 날일 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("지금 오른 차트") {
                switch ranks {
                case .loading:
                    ProgressView().controlSize(.small)
                case .blocked:
                    Text("순위 피드가 잠시 막혀 있어요. 조금 뒤에 다시 열어 보세요.")
                        .foregroundStyle(.secondary)
                case .ready(let ranks, let countries) where ranks.isEmpty:
                    Text("노출이 많은 \(countries)개 나라의 카테고리 차트 200위 안에는 없어요.")
                        .foregroundStyle(.secondary)
                case .ready(let ranks, _):
                    ForEach(ranks) { rank in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.country(rank.country))
                            Text(rank.chart).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text("\(rank.rank)위").monospacedDigit().fontWeight(.semibold)
                        }
                    }
                }
            }

            Text("투데이 탭 스토리나 비슷한 앱 추천에 걸린 자리는 Apple 이 알려 주지 않아요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: bundleID) {
            ranks = .loading
            let countries = StoreExposure.countries(funnel.browse)
            if let found = await StoreExposure.chartRanks(bundleID: bundleID, countries: countries) {
                ranks = .ready(found, countries: countries.count)
            } else {
                ranks = .blocked
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .padding(.top, 4)
    }

    private static func day(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)월 \(day)일"
    }

    private static func country(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

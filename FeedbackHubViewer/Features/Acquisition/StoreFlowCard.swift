//
//  StoreFlowCard.swift
//  FeedbackHubViewer
//
//  스토어 흐름(노출 → 조회 → 첫 다운로드)과 첫 다운로드 출처 도넛.
//

import SwiftUI
import Charts

// MARK: - 스토어 흐름 · 출처

/// 노출 → 페이지 조회 → 첫 다운로드를 막대로, 첫 다운로드의 출처를 도넛으로.
struct StoreFlowCard: View {
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

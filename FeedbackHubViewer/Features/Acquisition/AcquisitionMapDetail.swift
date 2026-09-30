//
//  AcquisitionMapDetail.swift
//  FeedbackHubViewer
//
//  접어 둔 유입 지도 원본 — 길 목록과 남은 할 일 전부.
//

import SwiftUI

// MARK: - 접어 둔 원본

struct MapDetail: View {
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

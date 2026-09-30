//
//  AcquisitionDetail.swift
//  FeedbackHubViewer
//
//  한 앱의 유입 — 판정 한 줄 · 할 일 · 구역별 한 줄 · 출처. 계산은 `AcquisitionDiagnosis`.
//

import SwiftUI

// MARK: - 한 앱

struct AcquisitionDetail: View {
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

struct ReadingRow: View {
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

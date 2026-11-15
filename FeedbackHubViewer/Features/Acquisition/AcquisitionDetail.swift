//
//  AcquisitionDetail.swift
//  FeedbackHubViewer
//
//  한 앱의 유입 — 판정 한 줄 · 할 일 · 구역별 한 줄이 위에, 나머지(채울 것 · ASO 처방 ·
//  스토어 흐름 · 노출 · 출처 · 지도 원본 · `footer`)는 "자세히 보기" 에 접는다.
//  계산은 `AcquisitionDiagnosis`.
//

import SwiftUI

// MARK: - 한 앱

struct AcquisitionDetail<Footer: View>: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String
    let map: AcquisitionMap
    /// 접힌 칸 맨 아래에 함께 넣는 카드(링크 출처).
    @ViewBuilder var footer: Footer

    @State private var showsMap = false

    var body: some View {
        let diagnosis = store.acquisitionDiagnosis(for: project, map: map, connect: connect, keywords: keywords)

        VStack(alignment: .leading, spacing: 14) {
            verdict(diagnosis)

            VStack(spacing: 10) {
                ForEach(diagnosis.readings) { reading in
                    ReadingRow(reading: reading, isLeak: reading.zone == diagnosis.leak)
                }
            }

            DetailFold(storageKey: AcquisitionFold.key, summary: foldSummary(diagnosis)) {
                VStack(alignment: .leading, spacing: 14) {
                    folded(diagnosis)
                }
            }
        }
        .task(id: project) {
            await connect.loadFunnel(bundleID: project)
            await connect.loadMetadata(bundleID: project)
        }
    }

    /// 접힌 칸에 무엇이 있는지 한 줄.
    private func foldSummary(_ diagnosis: AcquisitionDiagnosis) -> String {
        var parts: [String] = []
        if !diagnosis.missing.isEmpty { parts.append("채울 것 \(diagnosis.missing.count)개") }
        if diagnosis.aso != nil { parts.append("ASO 처방") }
        parts.append("스토어 흐름 · 노출 · 받는 사람은 어디서 오나")
        if !map.isFallback { parts.append("지도 원본") }
        parts.append("캠페인 링크 · 링크 출처")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func folded(_ diagnosis: AcquisitionDiagnosis) -> some View {
        if !diagnosis.missing.isEmpty {
            MissingInputsCard(project: project, missing: diagnosis.missing)
        }

        if let aso = diagnosis.aso {
            ASOPrescriptionCard(project: project, aso: aso)
        }

        if case .ready(let funnel)? = connect.funnels[project]?.value, funnel.instances > 0 {
            StoreFlowCard(funnel: funnel, sourceMix: diagnosis.sourceMix)
            ExposureCard(funnel: funnel, bundleID: project)
        } else if let mix = diagnosis.sourceMix {
            Card(title: "받는 사람은 어디서 오나", systemImage: "arrow.triangle.branch") {
                Text(mix)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // 기본 지도(`isFallback`)는 리포에 쓴 원본이 없으니 보일 것도 없다.
        if !map.isFallback {
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

        footer
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

/// 한 앱 유입 화면의 "자세히 보기" 를 연 상태를 담는 키.
enum AcquisitionFold {
    static let key = "fold.acquisition.project"
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

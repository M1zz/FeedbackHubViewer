//
//  AcquisitionOverview.swift
//  FeedbackHubViewer
//
//  전체 프로젝트의 유입 — 앱마다 판정 한 줄, 새는 앱이 위.
//

import SwiftUI

// MARK: - 전체 프로젝트

/// 앱마다 판정 한 줄. 어느 앱의 어느 구역부터 손댈지가 이 화면의 요점이다.
struct AcquisitionOverview: View {
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

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
                    ReferralCard(project: project)
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

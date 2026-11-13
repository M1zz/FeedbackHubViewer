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
//  리포에 손으로 쓴 지도가 없는 앱도 기본 지도로 판정한다(`AcquisitionMap(fallbackFor:)`).
//  지도 원본(길 목록 · 남은 할 일 전부)은 손으로 쓴 지도가 있을 때만 접어 둔다. 머리로 합쳐야 하는 표는 앞에 두지
//  않는다 — 합친 결과가 위의 판정이다. 계산은 `AcquisitionDiagnosis` 가 한다.
//

import SwiftUI
import Charts

struct AcquisitionView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// nil == 전체 프로젝트.
    let project: String?

    /// 링크 카드로 내려가는 단추가 겨누는 곳.
    private static let referralAnchor = "referrals"

    var body: some View {
        ScrollViewReader { proxy in
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
                        referralJump(project) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(Self.referralAnchor, anchor: .top)
                            }
                        }
                        AcquisitionDetail(project: project,
                                          map: AcquisitionCatalog.effectiveMap(for: project,
                                                                              appName: store.displayName(for: project)))
                        CampaignLinkCard(project: project)
                        ReferralCard(project: project)
                            .id(Self.referralAnchor)
                    } else {
                        AcquisitionOverview()
                    }
                }
                .padding()
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 맨 아래 "누가 내 앱을 링크했나" 카드로 바로 내려가는 단추. 판정 · 지도 아래에
    /// 있어 스크롤해야 닿던 카드다. 새로 링크한 곳이 있으면 그 수를 같이 단다.
    private func referralJump(_ project: String, action: @escaping () -> Void) -> some View {
        let alerts: Int
        if case .ready(let detection, _)? = connect.referrals[project]?.value {
            alerts = detection.alerts.count
        } else {
            alerts = 0
        }
        return Button(action: action) {
            HStack(spacing: 8) {
                Label("누가 내 앱을 링크했나 보기", systemImage: "link")
                if alerts > 0 {
                    Text("새 소식 \(alerts)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Image(systemName: "arrow.down")
            }
            .font(.body)
        }
        .buttonStyle(.bordered)
        .help("이 화면 아래의 링크 출처 카드로 바로 내려갑니다")
    }
}

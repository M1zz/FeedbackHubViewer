//
//  MissingInputsCard.swift
//  FeedbackHubViewer
//
//  "판단하려면 이것이 필요합니다" — 빠진 입력마다 바로 누르는 단추.
//

import SwiftUI

// MARK: - 넣어야 할 정보

/// 판단을 막고 있는 것. 종류마다 그 자리에서 해결하는 단추를 단다.
struct MissingInputsCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore
    let project: String
    let missing: [AcquisitionDiagnosis.MissingInput]

    var body: some View {
        Card(title: "판단하려면 이것이 필요합니다", systemImage: "tray.and.arrow.down") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(missing) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.semibold))
                        Text(item.why)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.terms.isEmpty {
                            Text(item.terms.joined(separator: ", "))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        button(for: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func button(for item: AcquisitionDiagnosis.MissingInput) -> some View {
        let country = keywords.countries.first ?? "kr"
        switch item.kind {
        case .ascKey:
            OpenSettingsButton(title: "설정 열기").font(.body)
        case .analyticsRequest:
            Button("리포트 요청 만들기") {
                Task { await connect.requestAnalytics(bundleID: project) }
            }
        case .metadata:
            Button("다시 읽기") {
                Task { await connect.loadMetadata(bundleID: project, force: true) }
            }
        case .storeLink:
            Button("키워드 탭 열기") { store.open(project: project, section: .keywords) }
        case .noKeywords:
            Button(keywords.isChecking ? "찾는 중…" : "키워드 자동 찾기") {
                keywords.discover(for: project)
            }
            .disabled(keywords.isChecking)
        case .untrackedTerms:
            Button("이 단어들 추적하고 지금 재기") {
                for term in item.terms {
                    keywords.add(term: term, countries: [country], for: project)
                    keywords.checkNow(TrackedKeyword(term: term, country: country))
                }
            }
        case .staleRanks:
            Button(keywords.isChecking ? "확인 중…" : "지금 확인") {
                keywords.check(bundleIds: store.allProjectKeys)
            }
            .disabled(keywords.isChecking)
        case .analyticsPending, .ladder:
            EmptyView()
        }
    }
}

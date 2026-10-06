//
//  AnalyticsCoverageCard.swift
//  FeedbackHubViewer
//
//  전체 프로젝트의 스토어 분석 — 계정의 앱마다 분석 리포트를 요청해 두었는가.
//
//  요청은 만든 날부터만 쌓이고 지난 기록은 생기지 않는다. 그래서 요청이 없는 앱은
//  하루하루 기록을 잃는다. 2026-10 에 67개 중 4개만 요청이 있었다.
//

import SwiftUI

struct AnalyticsCoverageCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var store: FeedbackStore

    @State private var isRequesting = false
    @State private var failures: [String] = []
    @State private var isConfirming = false

    var body: some View {
        Card(title: "분석 리포트 요청 현황", systemImage: "tray.full") {
            switch connect.analyticsCoverage {
            case nil, .loading?:
                ProgressView("앱마다 요청이 있는지 묻는 중…").font(.body)
            case .failed(let message)?:
                Text(message).font(.body).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 묻기") { Task { await connect.loadAnalyticsCoverage(force: true) } }
            case .loaded(let coverage)?:
                content(coverage)
            }
        }
        .task { await connect.loadAnalyticsCoverage() }
        .confirmationDialog("요청 없는 앱 \(connect.analyticsCoverage?.value?.missing.count ?? 0)개에 분석 리포트 요청을 만들까요?",
                            isPresented: $isConfirming) {
            Button("모두 요청") { requestAll() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("스토어에 보이는 것은 아무것도 바뀌지 않습니다. 1~2일 뒤부터 하루치씩 쌓입니다.")
        }
    }

    @ViewBuilder
    private func content(_ coverage: AnalyticsCoverage) -> some View {
        let missing = coverage.missing
        if missing.isEmpty {
            AnalyticsHeadline("앱 \(coverage.apps.count)개 모두 리포트가 쌓이고 있습니다.")
        } else {
            AnalyticsHeadline("앱 \(coverage.apps.count)개 중 \(missing.count)개는 리포트 요청이 없어 기록이 안 쌓이고 있습니다.")
            AnalyticsNote("요청은 만든 날부터만 쌓이고 지난 기록은 생기지 않습니다. 요청이 있어야 이 탭의 분석(행사와 평상시 · 삭제 · 나라별 전환 · 세션)이 나옵니다.")
            Button(isRequesting ? "요청 만드는 중…" : "요청 없는 앱 \(missing.count)개 모두 요청") { isConfirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
        }
        ForEach(failures, id: \.self) { failure in
            Text(failure).font(.body).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 6) {
            ForEach(coverage.apps.sorted { ($0.hasRequest ? 1 : 0, $0.app.name) < ($1.hasRequest ? 1 : 0, $1.app.name) }) { entry in
                row(entry)
            }
        }
        AnalyticsNote("\(AppFormat.relative(coverage.checkedAt)) 확인 · 앱을 고르면 그 앱의 분석이 나옵니다.")
        Button("다시 확인") { Task { await connect.loadAnalyticsCoverage(force: true) } }
            .buttonStyle(.borderless)
    }

    private func row(_ entry: AnalyticsCoverage.Entry) -> some View {
        Button {
            store.open(project: entry.app.bundleID, section: .storeAnalytics)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.hasRequest ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(entry.hasRequest ? .green : .secondary)
                Text(entry.app.name).font(.body)
                Spacer(minLength: 8)
                Text(entry.hasRequest ? "쌓는 중" : "요청 없음")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func requestAll() {
        isRequesting = true
        Task {
            failures = await connect.requestAnalyticsForAll()
            isRequesting = false
        }
    }
}

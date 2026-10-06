//
//  AnalyticsExplorerCard.swift
//  FeedbackHubViewer
//
//  리포트 전부 훑기 — 요청 안의 150여 종 가운데 이 앱에 데이터가 있는 것을 찾아,
//  하나씩 펼치면 그 리포트를 그대로 접어 보인다(`AnalyticsDigest`).
//
//  위 카드들이 읽는 열두 종 밖의 것(위젯 · 단축어 · 라이브 액티비티 · 사진 선택기 …)은
//  앱이 그 기능을 쓸 때만 생긴다. 열의 뜻을 미리 모르니 숫자 열은 합, 나머지는 상위 값으로만 보인다.
//

import SwiftUI

struct AnalyticsExplorerCard: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var isScanning = false

    var body: some View {
        Card(title: "리포트 전부 훑기", systemImage: "square.stack.3d.down.right") {
            let scan = connect.analyticsScans[project]?.value ?? connect.restoredScan(bundleID: project)
            if let scan {
                AnalyticsNote("리포트 \(scan.total)종 가운데 \(scan.reports.count)종에 데이터가 있습니다 · \(AppFormat.relative(scan.scannedAt)) 훑음")
                ForEach(categories(scan), id: \.self) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AnalyticsReportInfo.label(forCategory: category))
                            .font(.headline)
                        ForEach(scan.reports.filter { $0.report.category == category }) { entry in
                            AnalyticsExplorerRow(project: project, entry: entry)
                        }
                    }
                }
            } else {
                AnalyticsNote("Apple 은 앱마다 150여 종의 리포트를 만듭니다. 대부분은 그 앱이 쓰지 않는 기능의 것이라 비어 있어요. 훑으면 데이터가 있는 것만 골라 보여 줍니다. 종류마다 한 번씩 물어서 수십 초 걸립니다.")
            }
            if case .failed(let message)? = connect.analyticsScans[project] {
                Text(message).font(.body).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(isScanning ? "훑는 중…" : (connect.analyticsScans[project]?.value == nil ? "데이터 있는 리포트 찾기" : "다시 훑기")) {
                isScanning = true
                Task {
                    await connect.scanAnalytics(bundleID: project)
                    isScanning = false
                }
            }
            .disabled(isScanning)
        }
    }

    private func categories(_ scan: AnalyticsScan) -> [String] {
        let present = Set(scan.reports.map(\.report.category))
        return AnalyticsReportInfo.categoryOrder.filter(present.contains)
            + present.subtracting(AnalyticsReportInfo.categoryOrder).sorted()
    }
}

/// 리포트 한 줄 — 펼치면 그때 받는다.
private struct AnalyticsExplorerRow: View {
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String
    let entry: AnalyticsScan.Entry

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                switch connect.analyticsDigests[AppStoreConnectStore.digestKey(project, entry.report.name)] {
                case nil, .loading?:
                    ProgressView("받는 중…").font(.body)
                case .failed(let message)?:
                    Text(message).font(.body).foregroundStyle(.orange)
                case .loaded(let digest)?:
                    AnalyticsDigestView(digest: digest)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(entry.report.name).font(.body)
                Spacer(minLength: 8)
                Text(granularityLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded else { return }
            Task { await connect.loadDigest(bundleID: project, entry: entry) }
        }
    }

    private var granularityLabel: String {
        let names = ["DAILY": "일", "WEEKLY": "주", "MONTHLY": "월"]
        return ["DAILY", "WEEKLY", "MONTHLY"].compactMap { key in
            entry.instances[key].map { "\(names[key] ?? key) \($0)" }
        }.joined(separator: " · ")
    }
}

/// 뜻을 모르는 리포트를 그대로 — 숫자 열은 합(평균 열은 평균), 나머지 열은 상위 값.
struct AnalyticsDigestView: View {
    let digest: AnalyticsDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if digest.rowCount == 0 {
                AnalyticsNote("최근 창에 행이 없습니다. 주 · 월 단위로만 나오는 리포트이거나, 데이터가 오래전 것입니다.")
            } else {
                AnalyticsNote("행 \(AppFormat.count(digest.rowCount))개 · \(dayRange)")
                if !digest.measures.isEmpty {
                    FigureRow {
                        ForEach(digest.measures) { measure in
                            Figure(measure.column, measure.isAverage ? AnalyticsFormat.decimal(measure.value) : AnalyticsFormat.count(measure.value),
                                   note: measure.isAverage ? "평균" : "합")
                        }
                    }
                }
                ShareGrid {
                    ForEach(digest.dimensions) { dimension in
                        ShareList(title: dimension.column + (dimension.distinct > dimension.top.count ? " (\(dimension.distinct)가지)" : ""),
                                  shares: dimension.top, limit: 6, tint: .gray)
                    }
                }
                if let weight = digest.weight {
                    AnalyticsNote("막대는 \(weight) 기준입니다.")
                }
            }
        }
    }

    private var dayRange: String {
        guard let first = digest.days.first, let last = digest.days.last else { return "" }
        return first == last ? first : "\(first) ~ \(last)"
    }
}

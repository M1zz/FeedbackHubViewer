//
//  AcquisitionOverview.swift
//  FeedbackHubViewer
//
//  전체 프로젝트의 유입 — App Store 에 있는 모든 앱을 한 줄씩. 줄어드는 앱이 위.
//
//  예전에는 리포에 손으로 쓴 유입 지도가 있는 앱(클립키보드 하나)만 보였다. 이제 지도 없이
//  App Store Connect 분석 리포트만으로 앱마다 "얼마나 · 어디서 · 느나 주나" 를 한 줄로 말한다.
//  앱 하나의 판정(새는 구역 · 할 일)은 그 앱을 눌러 연 화면에서 한다 — 마흔 개 앱에 판정을
//  다 돌리면 그리는 동안 화면이 멈춘다.
//

import SwiftUI

/// 앱 하나의 한 줄 요약.
struct AcquisitionSummary: Identifiable {
    let project: String
    let funnel: StoreFunnel
    var id: String { project }

    var downloads: Int { funnel.total.firstDownloads }
    var inflow: AcquisitionDiagnosis.Inflow? {
        AcquisitionDiagnosis.inflow(daily: funnel.daily.mapValues(\.firstDownloads))
    }
    /// 첫 다운로드가 가장 많은 경로와 그 몫.
    var topSource: (label: String, share: Double)? {
        let bySource = funnel.sources.mapValues(\.firstDownloads)
        guard downloads > 0, let top = bySource.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return (StoreFunnel.label(forSource: top.key), Double(top.value) / Double(downloads))
    }
    /// 스토어에서 본 사람(노출) 중 받은 몫. 페이지 조회는 분모로 쓰지 않는다 — 둘러보기 · 검색
    /// 목록에서 페이지를 안 열고 바로 받는 사람이 많아 100% 를 넘는다(세끼 159%).
    var viewConversion: Double? { funnel.total.conversion }
}

struct AcquisitionOverview: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore

    /// 허브에 있는 앱 전부 — App Store 에 있는지는 리포트를 받아 보며 가린다(못 찾으면 실패로 남는다).
    private var storeApps: [String] {
        store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject }
    }

    var body: some View {
        let apps = storeApps
        let summaries = apps.compactMap { key -> AcquisitionSummary? in
            guard case .ready(let funnel)? = connect.funnels[key]?.value, funnel.instances > 0 else { return nil }
            return AcquisitionSummary(project: key, funnel: funnel)
        }
        let falling = summaries.filter { $0.inflow?.isFalling == true }.sorted { $0.downloads > $1.downloads }
        let rest = summaries.filter { $0.inflow?.isFalling != true }.sorted { $0.downloads > $1.downloads }
        let noRequest = apps.filter { if case .loaded(.noRequest)? = connect.funnels[$0] { return true } else { return false } }
        let notOnStore = apps.filter { if case .failed? = connect.funnels[$0] { return true } else { return false } }
        let loading = apps.count - summaries.count - noRequest.count - notOnStore.count

        VStack(alignment: .leading, spacing: 10) {
            if !connect.isConfigured {
                Card(title: "App Store Connect 키가 필요합니다", systemImage: "key") {
                    Text("노출 · 페이지 조회 · 첫 다운로드와 경로를 App Store Connect 분석 리포트에서 읽습니다. 설정에서 키를 넣어 주세요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            if !falling.isEmpty {
                section("지난주보다 줄어든 앱 \(falling.count)개", falling)
            }
            if !rest.isEmpty {
                section(falling.isEmpty ? "최근 30일 첫 다운로드가 많은 앱부터" : "나머지 앱", rest)
            }
            if loading > 0 {
                Label("리포트를 읽는 중인 앱 \(loading)개", systemImage: "hourglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if !noRequest.isEmpty {
                Text("분석 리포트 요청이 없는 앱 \(noRequest.count)개: " + noRequest.map { store.displayName(for: $0) }.joined(separator: ", ")
                     + ". 앱을 눌러 열면 요청을 만들 수 있고, 1~2일 뒤부터 쌓입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            if !notOnStore.isEmpty {
                Text("App Store 리포트를 못 받은 앱 \(notOnStore.count)개(아직 안 냈거나 맥 전용): " + notOnStore.map { store.displayName(for: $0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 디스크에 둔 리포트로 먼저 그리고, 새 파일만 받는다. 앱마다 차례로 — 한꺼번에 띄우지 않는다.
        .task {
            for key in storeApps { await connect.loadFunnel(bundleID: key) }
        }
    }

    private func section(_ title: String, _ rows: [AcquisitionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.top, 4)
            ForEach(rows) { row in
                Button {
                    store.open(project: row.project, section: .acquisition)
                } label: {
                    overviewRow(row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func overviewRow(_ row: AcquisitionSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StateDot(state: row.inflow?.isFalling == true ? .leaking : (row.inflow?.isStalled == true ? .watch : .healthy))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.displayName(for: row.project))
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text("30일 \(AppFormat.count(row.downloads))건")
                        .font(.figure(.body))
                }
                Text(line(row))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: "chevron.right")
                .font(.body)
                .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                .padding(.top, 4)
        }
        .padding(Platform.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    /// "주로 App Store 검색(62%) · 지난주 대비 ▼30% · 페이지 본 사람 중 31%가 받음"
    private func line(_ row: AcquisitionSummary) -> String {
        var parts: [String] = []
        if let top = row.topSource { parts.append("주로 \(top.label)(\(AcquisitionDiagnosis.percent(top.share)))") }
        if let inflow = row.inflow, let change = inflow.change {
            parts.append(change >= 0 ? "지난주 대비 ▲\(AcquisitionDiagnosis.percent(change))"
                                     : "지난주 대비 ▼\(AcquisitionDiagnosis.percent(-change))")
        } else if let inflow = row.inflow, inflow.last7 > 0 {
            parts.append("최근 7일 \(inflow.last7)건")
        }
        if let conversion = row.viewConversion {
            parts.append("스토어에서 본 사람 중 \(AcquisitionDiagnosis.percent(conversion))가 받음")
        }
        return parts.isEmpty ? "최근 30일 첫 다운로드가 없습니다." : parts.joined(separator: " · ")
    }
}

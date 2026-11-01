//
//  StabilizationCard.swift
//  FeedbackHubViewer
//
//  안정화 카드. 릴리즈 탭에서 릴리즈 건강 아래에 선다.
//
//   1. 신호 여섯: 크래시 · 리텐션 · 리뷰 · 핫픽스 · 성능 · 가설. 잴 수 없으면 회색 "모름"
//   2. 최근 버전 표: 신호를 만든 숫자들
//   3. 가설 적기: 버전을 누르면 가설 한 줄과 종료 조건
//
//  계산은 `Stabilization` 이 하고 여기는 그리기만 한다.
//

import SwiftUI

struct StabilizationCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    let project: String

    @State private var editing: Stabilization.Row?

    private var report: Stabilization.Report? {
        store.stabilization(for: project, source: connect.stabilitySources[project],
                            reviewFeed: connect.reviewFeeds[project])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("안정화", systemImage: "waveform.path.ecg")
                .font(.headline)

            if let report {
                signals(report)
                table(report)
                performance(report)
                notes
            } else {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
        .task(id: project) {
            await connect.loadStability(bundleID: project)
            await connect.loadReviews(bundleID: project)
        }
        .sheet(item: $editing) { row in
            HypothesisEditor(project: project, version: row.version)
        }
    }

    private var emptyMessage: String {
        if !connect.isConfigured { return "App Store Connect 키를 넣으면 버전 기록을 받아 잽니다." }
        if let error = connect.stabilityErrors[project] { return "버전 기록을 못 받았습니다: \(error)" }
        if connect.stabilitySources[project] != nil { return "스토어에 나간 버전이 없습니다." }
        return "버전 기록을 받는 중입니다."
    }

    // MARK: - 신호

    private func signals(_ report: Stabilization.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(report.signals) { signal in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StabilitySignalTag(signal: signal)
                    Text(signal.headline)
                        .font(.body)
                        .foregroundStyle(signal.level == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - 표

    private func table(_ report: Stabilization.Report) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(["버전", "제출", "크래시 없는 설치", "크래시", "D1", "D7", "D30",
                             "낮은 별점", "업데이트 불만", "버그", "가설"], id: \.self) { title in
                        Text(title).font(.body).foregroundStyle(.secondary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(report.rows) { row in
                    GridRow {
                        HStack(spacing: 4) {
                            Text(row.version).font(.body.monospacedDigit().weight(.semibold))
                            if row.isHotfix {
                                Tag(text: "핫픽스", systemImage: "bandage", tint: .orange)
                            }
                        }
                        Text(row.submittedAt.formatted(date: .abbreviated, time: .omitted))
                        Text(row.crashFreeRate.map(ReleaseHealth.percent) ?? "모름")
                            .foregroundStyle(crashTint(row))
                        Text("\(row.crashReports)건")
                        Text(rate(row.cohort.d1))
                        Text(rate(row.cohort.d7))
                        Text(rate(row.cohort.d30))
                        Text(row.lowReviews.map { "\($0)건" } ?? "모름")
                        Text(row.updateComplaints.map { "\($0)건" } ?? "모름")
                        Text("\(row.bugFeedback)건")
                        hypothesisButton(row)
                    }
                    .font(.body.monospacedDigit())
                }
            }
        }
    }

    private func crashTint(_ row: Stabilization.Row) -> Color {
        guard let rate = row.crashFreeRate else { return .secondary }
        return rate < Stabilization.crashFreeTarget ? .red : .primary
    }

    /// 표본이 작으면 퍼센트 대신 셈을 적는다. 세 명 중 한 명은 33% 가 아니다.
    private func rate(_ rate: Stabilization.Rate) -> String {
        guard rate.eligible > 0 else { return "모름" }
        if rate.eligible < Stabilization.minSample { return "\(rate.returned)/\(rate.eligible)" }
        return rate.ratio.map(ReleaseHealth.percent) ?? "모름"
    }

    private func hypothesisButton(_ row: Stabilization.Row) -> some View {
        Button {
            editing = row
        } label: {
            Text(row.hypothesis?.hasHypothesis == true ? row.hypothesis?.hypothesis ?? "" : "적기")
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(row.version) 가설 적기")
    }

    // MARK: - 성능

    @ViewBuilder
    private func performance(_ report: Stabilization.Report) -> some View {
        let rows = report.performance.compactMap { metric -> (Stabilization.PerformanceMetric, String)? in
            let points = report.rows.reversed().compactMap { row in
                metric.values[row.version].map { Stabilization.formatted($0) }
            }
            return points.isEmpty ? nil : (metric, points.joined(separator: " → "))
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("성능 (Organizer Metrics, 중앙값, 옛 버전 → 새 버전)")
                    .font(.headline)
                ForEach(rows, id: \.0.id) { metric, points in
                    Text("\(metric.label): \(points) \(metric.unit)")
                        .font(.body.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 각주

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            note("제출은 App Store Connect 의 버전 생성 시각이라 실제 출시보다 심사만큼 이릅니다. \(Int(Stabilization.hotfixHours))시간 안에 다시 제출하면 핫픽스로 셉니다.")
            note("크래시 없는 설치는 launch_incomplete 를 보낸 설치로 셉니다. Organizer 의 크래시율과 잣대가 다르고, 버전별 기록은 이 기능이 생긴 뒤부터 쌓입니다.")
            note("D1 · D7 · D30 은 그 버전이 나가 있는 동안 새로 깐 설치의 잔존입니다. 리뷰는 버전 제출 뒤 \(Stabilization.reviewDays)일까지 세고, 지원 메일은 허브에 없어 앱 안 버그 피드백으로 대신합니다.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 신호 하나의 이름표. 잴 수 없으면 회색이다(초록으로 칠하지 않는다).
struct StabilitySignalTag: View {
    let signal: Stabilization.Signal

    var body: some View {
        if let level = signal.level {
            Tag(text: signal.kind.rawValue, systemImage: ReleaseHealthCard.symbol(level),
                tint: ReleaseHealthCard.tint(level))
                .accessibilityValue(level.label)
        } else {
            Tag(text: signal.kind.rawValue, systemImage: "questionmark.circle", tint: .secondary)
                .accessibilityValue("모름")
        }
    }
}

/// 전체 앱에서 앱마다의 안정화 신호. 무거운 앱이 위, 못 잰 앱은 이름만 맨 아래.
struct StabilizationOverview: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @EnvironmentObject private var keywords: KeywordStore

    private var keys: [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject }
    }

    private var reports: [(key: String, report: Stabilization.Report)] {
        keys.compactMap { key in
            store.stabilization(for: key, source: connect.stabilitySources[key],
                                reviewFeed: connect.reviewFeeds[key]).map { (key, $0) }
        }
    }

    var body: some View {
        let reports = reports
        let ordered = reports.enumerated().sorted { lhs, rhs in
            let l = lhs.element.report.level?.rawValue ?? -1, r = rhs.element.report.level?.rawValue ?? -1
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
        let unknown = keys.filter { key in !reports.contains { $0.key == key } }

        VStack(alignment: .leading, spacing: 8) {
            Label("안정화", systemImage: "waveform.path.ecg")
                .font(.headline)
            if ordered.isEmpty {
                Text(connect.isConfigured ? "버전 기록을 받는 중입니다." : "App Store Connect 키를 넣으면 앱마다 잽니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(ordered.enumerated()), id: \.element.key) { index, entry in
                if index > 0 { Divider() }
                row(entry.key, entry.report)
            }
            if !unknown.isEmpty, !ordered.isEmpty {
                Text("못 잼: " + unknown.map { store.displayName(for: $0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
        .task {
            await connect.loadStability(bundleIDs: keys)
            await connect.loadReviews(bundleIDs: keys)
        }
    }

    private func row(_ key: String, _ report: Stabilization.Report) -> some View {
        Button {
            store.open(project: key, section: .release)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: keywords.storeApp(for: key)?.iconURL, size: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.displayName(for: key))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    FlowLayout(spacing: 6) {
                        ForEach(report.signals) { StabilitySignalTag(signal: $0) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 릴리즈 하나의 가설 한 줄과 종료 조건.
private struct HypothesisEditor: View {
    @EnvironmentObject private var store: FeedbackStore
    @Environment(\.dismiss) private var dismiss
    let project: String
    let version: String

    @State private var hypothesis = ""
    @State private var exitCondition = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("이 릴리즈가 검증하려는 것") {
                    TextField("예: 첫 화면을 줄이면 D1 이 오른다", text: $hypothesis, axis: .vertical)
                }
                Section("종료 조건") {
                    TextField("예: D7 이 20% 아래면 되돌린다", text: $exitCondition, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(version)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        store.setReleaseHypothesis(hypothesis, exitCondition: exitCondition,
                                                   project: project, version: version)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            let saved = store.releaseHypotheses[Stabilization.Hypothesis.key(project: project, version: version)]
            hypothesis = saved?.hypothesis ?? ""
            exitCondition = saved?.exitCondition ?? ""
        }
    }
}

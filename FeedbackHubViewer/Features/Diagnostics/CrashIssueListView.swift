//
//  CrashIssueListView.swift
//  FeedbackHubViewer
//
//  진단의 기본 시야. 한 건씩이 아니라 **같은 사고끼리 묶어** 아픈 것부터 보여 준다.
//
//  왜 이 화면이 기본인가: 149건을 한 줄씩 늘어놓으면 그 중 무엇을 먼저 고쳐야 하는지
//  알 수 없다. 다 열어 봐도 마찬가지다. "이 사고가 40번 났고, 5.0.3부터 시작했고,
//  아직도 난다"가 보여야 순서가 정해진다.
//
//  묶는 규칙과 그 한계(심볼이 없어 이름으로 묶는다)는 `CrashAnalysis.swift` 머리말에.
//

import SwiftUI
import Charts

struct CrashIssueListView: View {
    @EnvironmentObject private var store: FeedbackStore
    /// nil == 전체 프로젝트.
    let project: String?

    /// "" == 모든 원인. 세그먼트가 옵셔널 태그를 못 맞추므로 String 을 쓴다
    /// (`CrashListView` 의 종류 칩과 같은 이유).
    @State private var cause = ""
    @State private var selected: CrashIssue?

    private var issues: [CrashIssue] {
        let all = store.crashIssues(for: project)
        guard !cause.isEmpty else { return all }
        return all.filter { $0.cause.rawValue == cause }
    }

    var body: some View {
        let all = store.crashIssues(for: project)

        Group {
            if all.isEmpty {
                ContentUnavailableView {
                    Label("올라온 진단이 없습니다", systemImage: "checkmark.seal")
                } description: {
                    Text("MetricKit은 크래시를 하루 한 번꼴로 묶어서 보냅니다. 방금 난 크래시는 바로 보이지 않고, 스키마·권한이 없으면 통계 화면 위에 사유가 표시됩니다.")
                }
            } else {
                List {
                    Section {
                        headline(all)
                        DiagnosticsTrendChart(reports: all.flatMap(\.reports))
                        if project == nil {
                            DiagnosticsByAppChart(issues: all)
                        }
                    }

                    if causeChips(of: all).count > 1 {
                        Section("원인") { chips(of: all) }
                    }

                    Section {
                        ForEach(issues) { issue in
                            Button { selected = issue } label: {
                                CrashIssueRow(issue: issue,
                                              projectLabel: projectLabel(for: issue))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(issues.count)개 이슈, 많이 나는 것부터")
                            .textCase(nil)
                    }

                    if all.contains(where: \.isLegacy) {
                        Section { legacyNote(all) }
                    }
                }
                .hubListStyle()
            }
        }
        .sheet(item: $selected) { issue in
            CrashIssueDetailView(issue: issue,
                                 projectLabel: projectLabel(for: issue))
        }
    }

    // MARK: - 머리

    @ViewBuilder
    private func headline(_ all: [CrashIssue]) -> some View {
        let recent = all.filter { $0.last7Days > 0 }
        let fresh = all.filter(\.isNew)

        HStack(spacing: 16) {
            Figure("아직 나는 이슈", "\(recent.count)", note: "전체 \(all.count)개",
                   tint: recent.isEmpty ? .secondary : .red)
            Divider().frame(height: 34)
            Figure("최근 7일 건수", "\(all.reduce(0) { $0 + $1.last7Days })")
            Divider().frame(height: 34)
            Figure("새로 생긴 이슈", "\(fresh.count)",
                   tint: fresh.isEmpty ? .secondary : .orange)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 원인 거르기

    private func causeChips(of all: [CrashIssue]) -> [(cause: CrashReport.Cause, count: Int)] {
        Dictionary(grouping: all, by: \.cause)
            .map { (cause: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private func chips(of all: [CrashIssue]) -> some View {
        FilterChipRow(selection: $cause, choices:
            [(title: "전체 \(all.count)", value: "")]
            + causeChips(of: all).map {
                (title: "\($0.cause.label) \($0.count)", value: $0.cause.rawValue)
            })
    }

    // MARK: - 옛 형식 안내

    /// 콜스택이 JSON 덩어리로 잘려 올라온 시절의 레코드는 갈라 볼 수가 없다.
    /// 조용히 한 덩어리로 두면 "왜 이것만 묶이지 않지"로 읽히므로 이유를 적는다.
    @ViewBuilder
    private func legacyNote(_ all: [CrashIssue]) -> some View {
        if let legacy = all.first(where: \.isLegacy) {
            Text("옛 형식 \(legacy.count)건은 콜스택이 JSON 중간에서 잘려 올라와 묶을 수 없습니다. 보내는 쪽을 고친 뒤 새로 쌓이는 것부터 분석됩니다.")
                .font(.hubFootnote)
                .foregroundStyle(.secondary)
        }
    }

    private func projectLabel(for issue: CrashIssue) -> String? {
        guard project == nil, let key = issue.reports.first?.projectKey else { return nil }
        return store.displayName(for: key)
    }
}

// MARK: - 한 줄

struct CrashIssueRow: View {
    let issue: CrashIssue
    var projectLabel: String?
    /// 이 화면을 열 때 안 본 진단 — 뱃지가 센 것.
    @Environment(\.freshItemIDs) private var fresh

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(issue.title)
                    .font(.hubCallout.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                if issue.isNew {
                    Tag(text: "새로 생김", tint: .orange, font: .hubCaption2)
                }
                let unseen = fresh.isEmpty ? 0 : issue.reports.filter { fresh.contains($0.id) }.count
                if unseen > 0 {
                    Tag(text: "새 진단 \(unseen)건", systemImage: "circle.fill", tint: .red, font: .body)
                }
                Spacer(minLength: 4)
                Text("\(issue.count)건")
                    .font(.hubCallout.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.hubCaption2.weight(.semibold))
                    .foregroundStyle(HierarchicalShapeStyle.hubFaint)
            }

            DailyBars(counts: issue.daily())
                .frame(height: 18)
                .accessibilityLabel("최근 14일 하루 건수")

            HStack(spacing: 6) {
                if let projectLabel {
                    Tag(text: projectLabel, tint: .secondary, font: .hubCaption2)
                }
                Tag(text: issue.cause.label,
                    tint: issue.cause.isWatchdog ? .orange : .red, font: .hubCaption2)

                if issue.last7Days > 0 {
                    Text("최근 7일 \(issue.last7Days)")
                        .font(.hubCaption.monospacedDigit())
                        .foregroundStyle(.red)
                    if issue.previous7Days > 0 {
                        Text(AppFormat.signed(issue.delta))
                            .font(.hubCaption2.monospacedDigit())
                            .foregroundStyle(DeltaPolarity.lowerIsBetter.tint(for: issue.delta))
                    }
                } else {
                    Text("최근 7일 없음")
                        .font(.hubCaption)
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 4)

                if let lastSeen = issue.lastSeen {
                    Text(AppFormat.relative(lastSeen))
                        .font(.hubCaption2)
                        .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                }
            }

            if let first = issue.versions.first {
                Text(issue.versions.count == 1
                     ? "v\(first.version) 에서만"
                     : "v\(first.version) 등 \(issue.versions.count)개 버전 · 기기 \(issue.devices.count)종")
                    .font(.hubCaption2)
                    .foregroundStyle(HierarchicalShapeStyle.hubFaint)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - 그림

/// 진단의 종류를 셋으로 — 그래프 색이 셋을 넘으면 읽히지 않는다.
private enum DiagnosticKind: String, CaseIterable, Plottable {
    case crash = "크래시"
    case hang = "멈춤"
    case other = "기타"

    init(_ kind: String) {
        switch kind {
        case "crash": self = .crash
        case "hang": self = .hang
        default: self = .other
        }
    }

    var color: Color {
        switch self {
        case .crash: return .red
        case .hang: return .orange
        case .other: return .gray
        }
    }
}

/// 최근 30일, 하루에 몇 건 났나 — 크래시 · 멈춤 · 기타로 쌓아서. 늘고 있는지가 한눈에.
struct DiagnosticsTrendChart: View {
    let reports: [CrashReport]
    private let days = 30

    private struct Day: Identifiable {
        let date: Date
        let kind: DiagnosticKind
        let count: Int
        var id: String { "\(date.timeIntervalSince1970)|\(kind.rawValue)" }
    }

    private var series: [Day] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        var counts: [Date: [DiagnosticKind: Int]] = [:]
        for report in reports {
            guard let date = report.happenedAt, date >= start else { continue }
            counts[calendar.startOfDay(for: date), default: [:]][DiagnosticKind(report.kind), default: 0] += 1
        }
        return counts.flatMap { day, kinds in kinds.map { Day(date: day, kind: $0.key, count: $0.value) } }
    }

    var body: some View {
        let series = series
        VStack(alignment: .leading, spacing: 6) {
            Text("최근 \(days)일, 하루에 난 진단")
                .font(.headline)
            if series.isEmpty {
                Text("최근 \(days)일에는 없습니다.")
                    .font(.body)
                    .foregroundStyle(.green)
            } else {
                Chart(series) { day in
                    BarMark(x: .value("날", day.date, unit: .day),
                            y: .value("건수", day.count))
                        .foregroundStyle(by: .value("종류", day.kind))
                }
                .chartForegroundStyleScale(domain: DiagnosticKind.allCases,
                                           range: DiagnosticKind.allCases.map(\.color))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 최근 7일, 어느 앱에서 많이 났나 — 전체 앱으로 볼 때만.
struct DiagnosticsByAppChart: View {
    @EnvironmentObject private var store: FeedbackStore
    let issues: [CrashIssue]

    private struct AppCount: Identifiable {
        let name: String
        let kind: DiagnosticKind
        let count: Int
        var id: String { name + kind.rawValue }
    }

    var body: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        var byApp: [String: [DiagnosticKind: Int]] = [:]
        for report in issues.flatMap(\.reports) where (report.happenedAt ?? .distantPast) >= weekAgo {
            byApp[report.projectKey, default: [:]][DiagnosticKind(report.kind), default: 0] += 1
        }
        let top = byApp.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(8)
        let rows = top.flatMap { key, kinds in
            kinds.map { AppCount(name: store.displayName(for: key), kind: $0.key, count: $0.value) }
        }
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 7일, 앱마다")
                        .font(.headline)
                    Chart(rows) { row in
                        BarMark(x: .value("건수", row.count),
                                y: .value("앱", row.name))
                            .foregroundStyle(by: .value("종류", row.kind))
                    }
                    .chartForegroundStyleScale(domain: DiagnosticKind.allCases,
                                               range: DiagnosticKind.allCases.map(\.color))
                    .chartYScale(domain: top.map { store.displayName(for: $0.key) })
                    .frame(height: CGFloat(top.count) * 26 + 30)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// 이슈 한 줄의 작은 막대 — 최근 14일 하루 건수. 아직 나는지, 늘고 있는지.
struct DailyBars: View {
    let counts: [Int]

    var body: some View {
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(count == 0 ? AnyShapeStyle(Color.secondary.opacity(0.18))
                                     : AnyShapeStyle(index >= counts.count - 7 ? Color.red : Color.red.opacity(0.45)))
                    .frame(width: 6)
                    .frame(height: count == 0 ? 2 : max(4, 18 * CGFloat(count) / CGFloat(peak)))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

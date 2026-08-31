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
                    Section { headline(all) }

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
                .font(.footnote)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if issue.isNew {
                    Tag(text: "새로 생김", tint: .orange, font: .caption2)
                }
                Spacer(minLength: 4)
                Text("\(issue.count)건")
                    .font(.callout.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(issue.shape)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                if let projectLabel {
                    Tag(text: projectLabel, tint: .secondary, font: .caption2)
                }
                Tag(text: issue.cause.label,
                    tint: issue.cause.isWatchdog ? .orange : .red, font: .caption2)

                if issue.last7Days > 0 {
                    Text("최근 7일 \(issue.last7Days)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                    if issue.previous7Days > 0 {
                        Text(AppFormat.signed(issue.delta))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DeltaPolarity.lowerIsBetter.tint(for: issue.delta))
                    }
                } else {
                    Text("최근 7일 없음")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 4)

                if let lastSeen = issue.lastSeen {
                    Text(AppFormat.relative(lastSeen))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let first = issue.versions.first {
                Text(issue.versions.count == 1
                     ? "v\(first.version) 에서만"
                     : "v\(first.version) 등 \(issue.versions.count)개 버전 · 기기 \(issue.devices.count)종")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

//
//  CrashListView.swift
//  FeedbackHubViewer
//
//  The 진단 section of a project screen. 두 시야를 오간다.
//
//   · **이슈** (기본): 같은 사고끼리 묶어 아픈 것부터. `CrashIssueListView`
//   · **전체**: 한 건씩, 버전별로 묶어서. 이 파일의 `CrashReportListView`
//
//  묶어 보는 쪽이 기본인 이유는 간단하다. 한 건씩 늘어놓은 목록으로는 "무엇을 먼저
//  고칠까"를 고를 수 없다. 다만 한 건씩 훑어야 할 때가 있어 옛 시야도 남겨 둔다.
//
//  Reports arrive from MetricKit (see `CrashReport.swift`), so a report with no
//  `occurredAt` falls back to when the hub received it, not when the crash
//  happened. The title belongs to `ProjectSectionView`.
//

import SwiftUI

/// 진단 화면의 문. 어느 시야로 볼지 고르고 그쪽에 넘긴다.
///
/// 고른 시야는 기기에 남는다. 크래시를 쫓는 사람은 대개 한 가지 시야만 쓰는데,
/// 화면에 들어올 때마다 되돌아가면 매번 다시 골라야 한다.
struct CrashListView: View {
    let project: String?
    @AppStorage("crashViewMode") private var mode = Mode.issues.rawValue

    enum Mode: String, CaseIterable, Identifiable {
        case issues, reports
        var id: String { rawValue }
        var label: String { self == .issues ? "이슈" : "전체" }
    }

    var body: some View {
        Group {
            if mode == Mode.reports.rawValue {
                CrashReportListView(project: project)
            } else {
                CrashIssueListView(project: project)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("보기", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .help("이슈로 묶어 보거나, 한 건씩 봅니다")
            }
        }
    }
}

struct CrashReportListView: View {
    @EnvironmentObject private var store: FeedbackStore
    /// nil == 전체 프로젝트.
    let project: String?

    /// "" == 모든 종류. A plain String rather than `String?`: an optional tag
    /// in a segmented picker silently fails to match the selection.
    @State private var kind = ""

    var body: some View {
        let summary = store.crashSummary(for: project)
        let reports = store.crashReports(for: project, kind: kind.isEmpty ? nil : kind)

        Group {
            if summary.isEmpty {
                ContentUnavailableView {
                    Label("올라온 진단이 없습니다", systemImage: "checkmark.seal")
                } description: {
                    Text("MetricKit은 크래시를 하루 한 번꼴로 묶어서 보냅니다. 방금 난 크래시는 바로 보이지 않고, 스키마·권한이 없으면 통계 화면 위에 사유가 표시됩니다.")
                }
            } else {
                List {
                    Section {
                        headline(summary)
                    }

                    if summary.byKind.count > 1 {
                        Section("종류") {
                            kindPicker(summary)
                        }
                    }

                    if project == nil && store.crashingProjects.count > 1 {
                        Section("프로젝트별") {
                            ForEach(store.crashingProjects, id: \.key) { entry in
                                Button {
                                    store.open(project: entry.key, section: .crashes)
                                } label: {
                                    HStack {
                                        Text(entry.displayName)
                                            .font(.callout)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        if entry.last7Days > 0 {
                                            Text("7일 \(entry.last7Days)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.red)
                                        }
                                        Text("\(entry.total)건")
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Diagnostics are read by version: "이 버전에서 무엇이
                    // 깨지고 있나". A flat newest-first list mixes releases
                    // together and hides that a version stopped crashing.
                    ForEach(versionGroups(of: reports), id: \.version) { group in
                        Section {
                            ForEach(group.reports) { report in
                                CrashRow(report: report,
                                         projectLabel: projectLabel(for: report),
                                         showsVersion: false)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text("v\(group.version)")
                                    .font(.headline)
                                Spacer(minLength: 4)
                                if group.last7Days > 0 {
                                    Text("최근 7일 \(group.last7Days)건")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                                Text("\(group.reports.count)건")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .textCase(nil)
                        }
                    }

                    Section {
                        Text("버전별로 묶고, 각 묶음은 최신순입니다. 시각은 허브에 도착한 때이고, 콜스택·앱 버전·OS만 담깁니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .hubListStyle()
            }
        }
        #if os(iOS)
        // On macOS the copy button lives in the header row instead: one more
        // window-toolbar item pushes the stack's back button into the overflow.
        .toolbar {
            if !summary.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Platform.copyToPasteboard(Self.copyText(of: reports))
                    } label: {
                        Label("전체 복사", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        #endif
    }

    /// One section per app version, newest version first. Versions sort
    /// naturally ("v10" after "v9"), and reports with no version land last.
    private func versionGroups(of reports: [CrashReport]) -> [(version: String, reports: [CrashReport], last7Days: Int)] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return Dictionary(grouping: reports, by: \.appVersion)
            .map { version, items in
                (version: version,
                 reports: items.sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) },
                 last7Days: items.filter { ($0.receivedAt ?? .distantPast) >= weekAgo }.count)
            }
            .sorted { lhs, rhs in
                let unknown = "—"
                if lhs.version == unknown { return false }
                if rhs.version == unknown { return true }
                return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
            }
    }

    static func copyText(of reports: [CrashReport]) -> String {
        reports.map(\.copyText).joined(separator: "\n\n———\n\n")
    }

    private func projectLabel(for report: CrashReport) -> String? {
        // Only worth showing when the list mixes apps.
        project == nil ? store.displayName(for: report.projectKey) : nil
    }

    @ViewBuilder
    private func headline(_ summary: FeedbackStore.CrashSummary) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("최근 7일")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text("\(summary.last7Days)건")
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    let delta = summary.delta
                    if summary.previous7Days > 0 || summary.last7Days > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "minus"))
                                .font(.system(size: 10, weight: .bold))
                            Text(delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)"))
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(delta > 0 ? .red : (delta < 0 ? .green : .secondary))
                    }
                }
                Text("지난주 \(summary.previous7Days)건")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("전체")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(summary.total)건")
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                Text(summary.lastAt.map { "마지막 \(AppFormat.relative($0))" } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            #if os(macOS)
            Button {
                Platform.copyToPasteboard(Self.copyText(of: store.crashReports(for: project, kind: kind.isEmpty ? nil : kind)))
            } label: {
                Label("전체 복사", systemImage: "doc.on.doc")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("보이는 진단을 텍스트로 모두 복사")
            #endif
        }
        .padding(.vertical, 2)
    }

    /// Filter chips rather than a segmented picker: segments truncate their
    /// labels ("과도한 디스크…") and wrapping chips keep every count readable.
    private func kindPicker(_ summary: FeedbackStore.CrashSummary) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            chip(title: "전체 \(summary.total)", value: "")
            ForEach(summary.byKind, id: \.kind) { entry in
                chip(title: "\(CrashReport.label(for: entry.kind)) \(entry.count)", value: entry.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func chip(title: String, value: String) -> some View {
        let isSelected = kind == value
        return Button {
            kind = value
        } label: {
            Text(title)
                .font(.callout)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One diagnostic: what kind, where it came from, and the call stack behind a
/// disclosure — the stack is long and only wanted when you're chasing it.
struct CrashRow: View {
    let report: CrashReport
    /// Shown when the list mixes projects.
    var projectLabel: String? = nil
    /// Off when the rows are already grouped under a version header.
    var showsVersion = true
    @State private var showsStack = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(report.kindLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(report.kind == "crash" ? Color.red : Color.orange)
                if showsVersion {
                    Text("v\(report.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let receivedAt = report.receivedAt {
                    Text(AppFormat.relative(receivedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    Platform.copyToPasteboard(report.copyText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("이 진단을 텍스트로 복사")
            }

            HStack(spacing: 6) {
                if let projectLabel {
                    Text(projectLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text("\(report.deviceType) · OS \(report.osVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if report.hasDetail {
                Text(report.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !report.stack.isEmpty {
                DisclosureGroup("콜스택", isExpanded: $showsStack) {
                    ScrollView(.horizontal) {
                        Text(report.stack)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}

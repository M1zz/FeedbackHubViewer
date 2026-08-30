//
//  CrashIssueDetailView.swift
//  FeedbackHubViewer
//
//  이슈 하나를 파고드는 화면. 목록이 "무엇을 먼저 고칠까"에 답한다면 여기는
//  "그래서 어디를 보면 되나"에 답한다.
//
//  콜스택은 **내 코드 프레임을 굵게** 그린다. 크래시 스택의 대부분은 UIKit 과 SwiftUI 라,
//  전부 같은 무게로 그리면 정작 볼 세 줄이 묻힌다.
//

import SwiftUI

struct CrashIssueDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let issue: CrashIssue
    var projectLabel: String?

    var body: some View {
        content
            .frame(minWidth: 460, minHeight: 520)
        #if os(iOS)
            .presentationDetents([.large])
        #endif
    }

    private var content: some View {
        NavigationStack {
            List {
                Section { header }

                Section("언제") { timing }

                if !issue.isLegacy {
                    Section {
                        stack
                    } header: {
                        HStack {
                            Text("콜스택").textCase(nil)
                            Spacer()
                            Text("0번이 죽은 자리")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("어디서") { distributions }

                Section {
                    ForEach(issue.reports.prefix(20)) { report in
                        reportRow(report)
                    }
                    if issue.reports.count > 20 {
                        Text("그 밖에 \(issue.reports.count - 20)건")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("개별 진단 \(issue.count)건").textCase(nil)
                }
            }
            .hubListStyle()
            .navigationTitle(issue.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Platform.copyToPasteboard(copyText)
                    } label: {
                        Label("복사", systemImage: "doc.on.doc")
                    }
                    .help("이 이슈를 텍스트로 복사")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - 머리

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let projectLabel {
                    Text(projectLabel)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text(issue.cause.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((issue.cause.isWatchdog ? Color.orange : Color.red).opacity(0.14),
                                in: Capsule())
                    .foregroundStyle(issue.cause.isWatchdog ? Color.orange : Color.red)
                if issue.isNew { Text("새로 생김").font(.caption).foregroundStyle(.orange) }
                if issue.isDormant { Text("최근 7일 없음").font(.caption).foregroundStyle(.green) }
            }

            // 무엇을 보라는 안내. 크래시 화면에서 가장 아쉬운 것이 이 한 줄이다.
            Text(issue.cause.hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                figure("\(issue.count)", "건")
                figure("\(issue.last7Days)", "최근 7일")
                figure("\(issue.devices.count)", "기기 종류")
                figure("\(issue.versions.count)", "버전")
            }
            .padding(.top, 2)

            if issue.variants > 1 {
                Text("이 이슈 안에 오프셋이 다른 자리가 \(issue.variants)곳 있습니다. 심볼이 없어 이름으로 묶은 결과이니, 서로 다른 사고가 섞여 있을 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 언제

    @ViewBuilder
    private var timing: some View {
        row("처음", issue.firstSeen.map { "\(AppFormat.dateTime($0)) (\(AppFormat.relative($0)))" } ?? "-")
        row("마지막", issue.lastSeen.map { "\(AppFormat.dateTime($0)) (\(AppFormat.relative($0)))" } ?? "-")
        row("최근 7일", "\(issue.last7Days)건 (지난주 \(issue.previous7Days)건)")

        if issue.reports.contains(where: { !$0.hasExactTime }) {
            Text("일부는 발생 시각이 없어 허브 도착 시각으로 대신했습니다. MetricKit 배달이 하루까지 늦으므로 실제 발생은 그보다 앞섭니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 콜스택

    @ViewBuilder
    private var stack: some View {
        if let representative = issue.reports.first {
            let frames = representative.frames
            if frames.isEmpty {
                Text("콜스택을 가르지 못했습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(frames.prefix(40)) { frame in
                        HStack(spacing: 8) {
                            Text("\(frame.id)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)
                            Text(frame.binary)
                                // 내 코드가 굵다. 스택의 대부분은 UIKit·SwiftUI 라
                                // 다 같은 무게로 그리면 볼 줄이 묻힌다.
                                .font(frame.isSystem
                                      ? .caption.monospaced()
                                      : .caption.monospaced().weight(.bold))
                                .foregroundStyle(frame.isSystem ? .secondary : .primary)
                            Text("+\(frame.offset)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                    }
                    if frames.count > 40 {
                        Text("그 아래 \(frames.count - 40)프레임")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    if let note = representative.truncationNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)

                // 범인 줄 하나만 되돌려도 대개 충분하다. 명령을 손으로 짜는 것이
                // 성가셔서 안 하게 되므로, 눌러서 붙여넣을 수 있게 둔다.
                if let culprit = issue.culprit,
                   let command = representative.symbolicationCommand(for: culprit) {
                    Button {
                        Platform.copyToPasteboard(command)
                    } label: {
                        Label("\(culprit.binary) +\(culprit.offset) 심볼 복원 명령 복사",
                              systemImage: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("dSYM 을 찾고 atos 로 함수 이름을 얻는 두 줄입니다")
                }

                Text("오프셋은 함수 이름이 아닙니다. 이름까지 보려면 그 빌드의 dSYM 이 필요합니다(README 의 \"심볼로 되돌리기\" 절).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 어디서

    @ViewBuilder
    private var distributions: some View {
        distribution("버전", issue.versions.map { (key: $0.version, count: $0.count) })
        distribution("기기", issue.devices.map { (key: $0.device, count: $0.count) })
        distribution("OS", issue.osVersions.map { (key: $0.os, count: $0.count) })
    }

    private func distribution(_ title: String, _ entries: [(key: String, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(entries.prefix(12), id: \.key) { entry in
                    Text("\(entry.key) \(entry.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                if entries.count > 12 {
                    Text("그 밖에 \(entries.count - 12)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 개별 진단

    private func reportRow(_ report: CrashReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("v\(report.versionLabel)")
                    .font(.caption.weight(.semibold))
                Text(report.deviceType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let at = report.happenedAt {
                    Text(AppFormat.relative(at))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let signalLabel = report.signalLabel {
                Text(signalLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if report.hasDetail {
                Text(report.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 복사

    /// 버그 리포트에 붙일 만한 모양으로. 이슈 요약 + 대표 콜스택이다.
    private var copyText: String {
        var lines = [
            "[\(issue.cause.label)] \(issue.title)",
            "\(issue.count)건 · 최근 7일 \(issue.last7Days)건 (지난주 \(issue.previous7Days)건)"
        ]
        if let firstSeen = issue.firstSeen { lines.append("처음: \(AppFormat.dateTime(firstSeen))") }
        if let lastSeen = issue.lastSeen { lines.append("마지막: \(AppFormat.dateTime(lastSeen))") }
        lines.append("버전: " + issue.versions.map { "\($0.version)(\($0.count))" }.joined(separator: ", "))
        lines.append("기기: " + issue.devices.prefix(8).map { "\($0.device)(\($0.count))" }.joined(separator: ", "))
        lines.append("")
        lines.append(issue.cause.hint)
        if let representative = issue.reports.first {
            lines.append("")
            lines.append(representative.stack)
        }
        return lines.joined(separator: "\n")
    }
}

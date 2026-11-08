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
        // 최소 크기는 **맥에만**. 맥의 시트는 제 크기를 스스로 정하므로 콜스택이
        // 한 줄에 들어갈 만큼은 넓어야 하지만, 아이폰의 시트 너비는 화면이 정한다
        // — 화면보다 넓은 최소 너비를 주면 시트가 넓어지는 대신 그 안의 내용이
        // 가운데 놓인 채 **양옆이 잘린다**. 460은 아이폰 너비(390~430)보다 넓다.
        #if os(macOS)
        content
            .frame(minWidth: 460, minHeight: 520)
        #else
        content
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
                                .font(.hubCaption2)
                                .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                            .font(.hubCaption)
                            .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                    .help("앱 리포에서 연 Claude Code 에 붙여넣을 글 — 함수 이름으로 되돌리는 명령까지 담습니다")
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
                    Tag(text: projectLabel, font: .hubCaption, isCompact: true)
                }
                Tag(text: issue.cause.label,
                    tint: issue.cause.isWatchdog ? .orange : .red,
                    font: .hubCaption.weight(.semibold), isCompact: true)
                if issue.isNew { Text("새로 생김").font(.hubCaption).foregroundStyle(.orange) }
                if issue.isDormant { Text("최근 7일 없음").font(.hubCaption).foregroundStyle(.green) }
            }

            // 무엇을 보라는 안내. 크래시 화면에서 가장 아쉬운 것이 이 한 줄이다.
            Text(issue.cause.hint)
                .font(.hubCallout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                // 통계·진단 화면의 다른 숫자들과 같은 차례: 이름이 위, 값이 아래.
                Figure("건수", "\(issue.count)")
                Figure("최근 7일", "\(issue.last7Days)")
                Figure("기기 종류", "\(issue.devices.count)")
                Figure("버전", "\(issue.versions.count)")
            }
            .padding(.top, 2)

            if issue.variants > 1 {
                Text("이 이슈 안에 오프셋이 다른 자리가 \(issue.variants)곳 있습니다. 심볼이 없어 이름으로 묶은 결과이니, 서로 다른 사고가 섞여 있을 수 있습니다.")
                    .font(.hubCaption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 언제

    @ViewBuilder
    private var timing: some View {
        row("처음", issue.firstSeen.map { "\(AppFormat.dateTime($0)) (\(AppFormat.relative($0)))" } ?? "-")
        row("마지막", issue.lastSeen.map { "\(AppFormat.dateTime($0)) (\(AppFormat.relative($0)))" } ?? "-")
        row("최근 7일", "\(issue.last7Days)건 (지난주 \(issue.previous7Days)건)")

        if issue.reports.contains(where: { !$0.hasExactTime }) {
            Text("일부는 발생 시각이 없어 허브 도착 시각으로 대신했습니다. MetricKit 배달이 하루까지 늦으므로 실제 발생은 그보다 앞섭니다.")
                .font(.hubCaption2)
                .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.hubCallout)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.hubCallout)
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
                    .font(.hubCaption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(frames.prefix(40)) { frame in
                        HStack(spacing: 8) {
                            Text("\(frame.id)")
                                .font(.hubCaption2.monospacedDigit())
                                .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                                .frame(width: 24, alignment: .trailing)
                            Text(frame.binary)
                                // 내 코드가 굵다. 스택의 대부분은 UIKit·SwiftUI 라
                                // 다 같은 무게로 그리면 볼 줄이 묻힌다.
                                .font(frame.isSystem
                                      ? .hubCaption.monospaced()
                                      : .hubCaption.monospaced().weight(.bold))
                                .foregroundStyle(frame.isSystem ? .secondary : .primary)
                            Text("+\(frame.offset)")
                                .font(.hubCaption2.monospaced())
                                .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                    }
                    if frames.count > 40 {
                        Text("그 아래 \(frames.count - 40)프레임")
                            .font(.hubCaption2)
                            .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                            .padding(.top, 2)
                    }
                    if let note = representative.truncationNote {
                        Text(note)
                            .font(.hubCaption2)
                            .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                            .font(.hubCaption)
                    }
                    .buttonStyle(.borderless)
                    .help("dSYM 을 찾고 atos 로 함수 이름을 얻는 두 줄입니다")
                }

                Text("오프셋은 함수 이름이 아닙니다. 이름까지 보려면 그 빌드의 dSYM 이 필요합니다(README 의 \"심볼로 되돌리기\" 절).")
                    .font(.hubCaption2)
                    .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                .font(.hubCaption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(entries.prefix(12), id: \.key) { entry in
                    Tag(text: "\(entry.key) \(entry.count)", font: .hubCaption.monospacedDigit())
                }
                if entries.count > 12 {
                    Text("그 밖에 \(entries.count - 12)")
                        .font(.hubCaption)
                        .foregroundStyle(HierarchicalShapeStyle.hubFaint)
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
                    .font(.hubCaption.weight(.semibold))
                Text(report.deviceType)
                    .font(.hubCaption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let at = report.happenedAt {
                    Text(AppFormat.relative(at))
                        .font(.hubCaption2)
                        .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                }
            }
            if let signalLabel = report.signalLabel {
                Text(signalLabel)
                    .font(.hubCaption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if report.hasDetail {
                Text(report.detail)
                    .font(.hubCaption2)
                    .foregroundStyle(HierarchicalShapeStyle.hubFaint)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 복사

    /// 앱 리포에서 연 Claude Code 에 붙여넣을 글. 오프셋만 주면 어느 코드인지 못 찾으므로,
    /// 함수 이름으로 되돌리는 명령과 그다음 할 일을 함께 준다.
    private var copyText: String {
        var lines = [
            "\(issue.title) 를 고쳐 주세요. App Store 사용자 기기에서 MetricKit 이 보낸 진단입니다.",
            "",
            "## 무엇이",
            "- 갈래: \(issue.cause.label) — \(issue.cause.hint)",
            "- \(issue.count)건 · 최근 7일 \(issue.last7Days)건 (지난주 \(issue.previous7Days)건)"
        ]
        if let firstSeen = issue.firstSeen { lines.append("- 처음: \(AppFormat.dateTime(firstSeen))") }
        if let lastSeen = issue.lastSeen { lines.append("- 마지막: \(AppFormat.dateTime(lastSeen))") }
        lines.append("- 버전: " + issue.versions.map { "\($0.version)(\($0.count))" }.joined(separator: ", "))
        lines.append("- 기기: " + issue.devices.prefix(8).map { "\($0.device)(\($0.count))" }.joined(separator: ", "))
        guard let representative = issue.reports.first else { return lines.joined(separator: "\n") }
        if let signal = representative.signalLabel { lines.append("- \(signal)") }
        if representative.hasDetail { lines.append("- \(representative.detail)") }

        lines.append("")
        lines.append("## 할 일")
        if let script = representative.symbolicationScript {
            lines.append("1. 아래 명령을 이 Mac 에서 돌려 콜스택의 내 코드 줄을 함수 이름 · 파일:줄로 되돌린다. 그 빌드의 dSYM 은 Xcode 아카이브에 있다.")
            lines.append("2. 나온 파일:줄을 이 리포에서 열고, 위 갈래에 맞는 원인을 찾아 고친다. 지금 코드와 그 버전 코드가 다르면 그 버전 태그 · 커밋에서 본다.")
            lines.append("3. dSYM 을 못 찾거나 atos 가 주소만 돌려주면 짐작으로 고치지 말고, 무엇을 못 찾았는지 말한다.")
            lines.append("")
            lines.append("```sh")
            lines.append(script)
            lines.append("```")
        } else {
            lines.append("콜스택에 이 앱의 코드 줄이 없다(전부 시스템). 위 갈래와 신호, 시스템 프레임 이름으로 어느 API 를 부르다 났는지 짚고, 그 API 를 쓰는 곳을 이 리포에서 찾는다.")
        }
        if issue.variants > 1 {
            lines.append("")
            lines.append("이 이슈 안에 서로 다른 자리가 \(issue.variants)곳 있다. 아래는 가장 많은 것 하나다.")
        }
        lines.append("")
        lines.append("## 대표 콜스택 (0번이 죽은 자리)")
        lines.append("```")
        lines.append(representative.stack)
        lines.append("```")
        return lines.joined(separator: "\n")
    }
}

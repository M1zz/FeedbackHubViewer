//
//  ReleaseHealthCard.swift
//  FeedbackHubViewer
//
//  릴리즈 건강 카드. 프로젝트 화면의 릴리즈 탭(`ReleaseHealthView`)에 선다. 새 버전을
//  낸 뒤 제일 먼저 알아야 하는 것이 "이번 버전 괜찮은가"라 통계 속 카드 하나가 아니라
//  제 탭을 갖는다.
//
//  읽는 차례대로 놓는다.
//   1. 판정(초록 · 노랑 · 빨강)과 그 이유 한 줄
//   2. 최신 버전과 앞 버전을 나란히 (활성 설치 · 핵심 행동률 · 크래시 없는 설치 · 크래시 · 피드백)
//   3. 채택: 지금 쓰는 사람 중 몇이 새 버전인가
//   4. 처음 본 크래시, 이 앱이 지키기로 한 약속
//   5. 이 숫자가 흔들리는 이유(각주)
//
//  계산은 `ReleaseHealth` 가 하고 여기는 그리기만 한다. 전체 · 유료 · 무료 고르개를 따르지
//  않는다. 크래시와 피드백은 설치와 이어져 있지 않아 무리로 못 가르기 때문이다.
//

import SwiftUI

struct ReleaseHealthCard: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = store.releaseHealth(for: project) {
                header(report.verdict)
                comparison(report)
                adoption(report)
                if report.verdict.reasons.count > 1 { reasons(report.verdict) }
                newSignatures(report.latest)
                promises(report)
                footnotes(report)
            } else {
                header(nil)
                Text("최근 \(ReleaseHealth.windowDays)일에 버전이 적힌 사용 이벤트가 없어 버전끼리 견줄 수 없습니다. 판정이 없는 것이지 괜찮다는 뜻이 아닙니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }

    // MARK: - 판정

    @ViewBuilder
    private func header(_ verdict: ReleaseHealth.Verdict?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("릴리즈 건강", systemImage: "stethoscope")
                .font(.headline)
            Spacer(minLength: 4)
            if let verdict {
                Tag(text: verdict.level.label, systemImage: Self.symbol(verdict.level),
                    tint: Self.tint(verdict.level), font: .body.weight(.semibold))
            }
        }
        if let verdict {
            Text(verdict.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Self.tint(verdict.level))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reasons(_ verdict: ReleaseHealth.Verdict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(verdict.reasons.dropFirst().enumerated()), id: \.offset) { _, reason in
                Label(reason, systemImage: "arrow.turn.down.right")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 나란히

    private func comparison(_ report: ReleaseHealth.Report) -> some View {
        let latest = report.latest
        let previous = report.previous
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                columnTitle("최신", latest.version)
                if let previous { columnTitle("앞 버전", previous.version) }
            }
            Divider().gridCellUnsizedAxes(.horizontal)

            row("활성 설치 (\(ReleaseHealth.windowDays)일)",
                "\(AppFormat.count(latest.activeInstalls))대",
                previous.map { "\(AppFormat.count($0.activeInstalls))대" })

            if let core = report.spec.coreAction {
                row(core.label, coreText(latest), previous.map(coreText))
            } else {
                GridRow {
                    Text("핵심 행동률").font(.body)
                    Text("스펙에 핵심 행동이 없음 (할 일)")
                        .font(.body)
                        .foregroundStyle(.orange)
                        .gridCellColumns(previous == nil ? 1 : 2)
                }
            }

            if report.stabilityKnown {
                row("크래시 없는 설치", crashFreeText(latest), previous.map(crashFreeText))
            } else {
                GridRow {
                    Text("크래시 없는 설치").font(.body)
                    Text("모름 (\(report.spec.stabilityEvents.joined(separator: ", ")) 이 한 번도 안 옴)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(previous == nil ? 1 : 2)
                }
            }

            row("크래시 보고", "\(latest.crashReports)건", previous.map { "\($0.crashReports)건" })
            row("새 크래시 지문", "\(latest.newSignatures.count)종", previous.map { _ in "" })
            row("피드백", feedbackText(latest), previous.map(feedbackText))
        }
    }

    private func columnTitle(_ title: String, _ version: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.body).foregroundStyle(.secondary)
            Text(version).font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private func row(_ label: String, _ latest: String, _ previous: String?) -> some View {
        GridRow {
            Text(label)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(latest).font(.body.monospacedDigit().weight(.semibold))
            if let previous {
                Text(previous).font(.body.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func coreText(_ metrics: ReleaseHealth.VersionMetrics) -> String {
        guard let rate = metrics.coreActionRate, let installs = metrics.coreActionInstalls else { return "설치 없음" }
        return "\(ReleaseHealth.percent(rate)) (\(AppFormat.count(installs))대)"
    }

    private func crashFreeText(_ metrics: ReleaseHealth.VersionMetrics) -> String {
        guard let rate = metrics.crashFreeRate, let unstable = metrics.unstableInstalls else { return "설치 없음" }
        return "\(ReleaseHealth.percent(rate)) (불안정 \(unstable)대)"
    }

    private func feedbackText(_ metrics: ReleaseHealth.VersionMetrics) -> String {
        guard let bugs = metrics.bugFeedback else { return "\(metrics.feedback)건" }
        return "\(metrics.feedback)건 (버그 \(bugs))"
    }

    // MARK: - 채택

    @ViewBuilder
    private func adoption(_ report: ReleaseHealth.Report) -> some View {
        let adoption = report.adoption
        if let share = adoption.share {
            VStack(alignment: .leading, spacing: 4) {
                Text("채택: 최근 \(ReleaseHealth.adoptionDays)일 활성 \(AppFormat.count(adoption.active))대 중 \(AppFormat.count(adoption.onLatest))대(\(ReleaseHealth.percent(share)))가 \(report.latest.version)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: share)
                    .tint(.accentColor)
            }
        } else {
            Text("채택: 최근 \(ReleaseHealth.adoptionDays)일에 활성 설치가 없어 잴 수 없습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 새 크래시

    @ViewBuilder
    private func newSignatures(_ latest: ReleaseHealth.VersionMetrics) -> some View {
        if !latest.newSignatures.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(latest.version)에서 처음 본 진단")
                    .font(.headline)
                ForEach(latest.newSignatures.prefix(5)) { signature in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(CrashReport.label(for: signature.kind)) · \(signature.title)")
                            .font(.body.monospaced())
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("\(signature.reports)건")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(signature.isCrash && signature.reports >= 2 ? .red : .secondary)
                    }
                }
                if latest.newSignatures.count > 5 {
                    Text("외 \(latest.newSignatures.count - 5)종. 진단 화면의 이슈 목록에서 \"새로 생김\"을 봅니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 약속

    @ViewBuilder
    private func promises(_ report: ReleaseHealth.Report) -> some View {
        if !report.spec.promises.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("이 앱이 지키기로 한 약속")
                    .font(.headline)
                ForEach(report.spec.promises) { promise in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(promise.title, systemImage: "checkmark.shield")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if let guardText = promise.guardText, !guardText.isEmpty {
                            Text("지키는 것: \(guardText)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 각주

    private func footnotes(_ report: ReleaseHealth.Report) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !report.hasReleaseSpec {
                note("이 앱 스펙에 release 절이 없어 기본값으로 판정했습니다(불안정 이벤트 launch_incomplete, 문턱 99% · 20% · 20대). 앱 리포의 docs/usage-spec.json에 핵심 행동과 약속을 적으면 이 카드가 더 많은 것을 말합니다.")
            } else if report.spec.coreAction == nil {
                note("스펙에 release 절은 있지만 coreAction이 없습니다. 하위 호환(원래 쓰던 사람이 여전히 쓰는가)은 그걸 적어야 잽니다.")
            }
            note("크래시 보고는 MetricKit이 하루쯤 늦게, 일부만 보냅니다. 오늘 낸 버전의 크래시는 내일에야 보입니다. 설치 ID가 없어 크래시 없는 설치 비율에는 안 들어가고, 그 비율은 불안정 이벤트(\(report.spec.stabilityEvents.joined(separator: ", ")))를 보낸 설치로만 셉니다.")
            note("통계 고르개(전체 · 유료 · 무료)와 무관하게 언제나 전체 기준입니다.")
            if let start = report.coverageStart {
                note("이 기기에는 원본 이벤트가 \(AppFormat.dateTime(start))부터만 남아 있습니다(보관 상한 \(AppFormat.count(FeedbackStore.eventLimit))건). 그 앞의 활동은 빠진 채로 셌습니다.")
            }
            if report.eventsWithoutInstall > 0 {
                note("설치 ID가 없는 이벤트 \(AppFormat.count(report.eventsWithoutInstall))건은 설치로 셀 수 없어 뺐습니다.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 색

    static func tint(_ level: ReleaseHealth.Level) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }

    static func symbol(_ level: ReleaseHealth.Level) -> String {
        switch level {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.circle.fill"
        case .red: return "xmark.octagon.fill"
        }
    }
}

/// 프로젝트 목록 · 사이드바에 붙는 점 하나. 잴 수 없는 앱에는 아예 안 뜬다.
struct ReleaseDot: View {
    let level: ReleaseHealth.Level?

    var body: some View {
        if let level {
            Circle()
                .fill(level == .yellow ? Color.yellow : ReleaseHealthCard.tint(level))
                .frame(width: 9, height: 9)
                .help("릴리즈 건강: \(level.label)")
                .accessibilityLabel("릴리즈 건강 \(level.label)")
        }
    }
}

/// "빨강 먼저" 켜고 끄기. 목록의 차례만 바꾸고 아무것도 숨기지 않는다.
struct RedFirstToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label("빨강 먼저", systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isOn ? Color.red : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("릴리즈 건강이 빨강인 앱을 위로 올립니다. 같은 색 안에서는 어제 DAU 순입니다.")
        .accessibilityValue(isOn ? "켜짐" : "꺼짐")
    }
}

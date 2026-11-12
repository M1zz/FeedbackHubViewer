//
//  ReleaseHealthCard.swift
//  FeedbackHubViewer
//
//  릴리즈 건강 카드. 프로젝트 화면의 릴리즈 탭(`ReleaseHealthView`)에 선다. 새 버전을
//  낸 뒤 제일 먼저 알아야 하는 것이 "이번 버전 괜찮은가"라 통계 속 카드 하나가 아니라
//  제 탭을 갖는다.
//
//  읽는 차례대로 놓는다.
//   1. 판정(초록 · 노랑 · 빨강 · 판단할 수 없음)과 그 이유 한 줄, 최근 버전마다 곤란을 겪는 사용자가 몇인지 파이,
//      초록이 아니면 초록까지 할 일(고칠 것 · 기다릴 것)
//   2. 최신 버전과 앞 버전을 나란히 (활성 설치 · 핵심 행동률 · 크래시 없는 설치 · 크래시 · 피드백)
//   3. 채택: 지금 쓰는 사람 중 몇이 새 버전인가
//   4. 처음 본 크래시, 이 앱이 지키기로 한 약속
//   5. 이 숫자가 흔들리는 이유(각주)
//
//  계산은 `ReleaseHealth` 가 하고 여기는 그리기만 한다. 전체 · 유료 · 무료 고르개를 따르지
//  않는다. 크래시와 피드백은 설치와 이어져 있지 않아 무리로 못 가르기 때문이다.
//

import SwiftUI
import Charts

struct ReleaseHealthCard: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = store.releaseHealth(for: project) {
                header(report.verdict)
                PeopleByVersion(versions: report.recent.isEmpty ? [report.latest] : report.recent,
                                enough: report.spec.thresholds.minInstallsForVerdict)
                if !report.verdict.steps.isEmpty { toGreen(report.verdict.steps) }
                copyForClaude(report)
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

    /// 신호를 Claude 에게 그대로 넘길 글. 판정 · 숫자 · 새 크래시 · 스펙을 한 덩어리로
    /// 담아, 받는 쪽이 이 화면을 못 봐도 무엇을 고쳐야 하는지 알게 한다.
    private func copyForClaude(_ report: ReleaseHealth.Report) -> some View {
        HStack(spacing: 8) {
            CopyButton(text: Self.claudePrompt(report, appName: store.displayName(for: project), project: project),
                       title: "Claude에게 맡길 글 복사")
                .buttonStyle(.bordered)
            Text(report.verdict.level == .green ? "앱 리포에서 연 Claude 에 붙여넣으면 놓친 위험을 점검합니다."
                                                : "앱 리포에서 연 Claude 에 붙여넣으면 원인을 찾아 고칩니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func claudePrompt(_ report: ReleaseHealth.Report, appName: String, project: String) -> String {
        let latest = report.latest
        let previous = report.previous
        var lines: [String] = []
        let isGreen = report.verdict.level == .green
        lines.append("\(appName) (\(project)) 의 릴리즈 건강이 \(report.verdict.level.label)입니다. "
                     + (isGreen ? "숫자가 놓친 위험이 있는지 점검해 주세요." : "원인을 찾아 고쳐 주세요."))
        lines.append("")
        lines.append("## 판정")
        for reason in report.verdict.reasons { lines.append("- \(reason)") }
        if !report.verdict.steps.isEmpty {
            lines.append("")
            lines.append("## 초록이 되려면")
            for step in report.verdict.steps {
                lines.append("- [\(step.kind == .fix ? "고칠 것" : "기다릴 것")] \(step.text)")
            }
        }
        lines.append("")
        lines.append("## 버전 비교 (최근 \(ReleaseHealth.windowDays)일)")
        lines.append("| 항목 | 최신 \(latest.version) |" + (previous.map { " 앞 버전 \($0.version) |" } ?? ""))
        lines.append("|---|---|" + (previous == nil ? "" : "---|"))
        func row(_ label: String, _ value: (ReleaseHealth.VersionMetrics) -> String) {
            lines.append("| \(label) | \(value(latest)) |" + (previous.map { " \(value($0)) |" } ?? ""))
        }
        row("활성 설치") { "\($0.activeInstalls)대" }
        if let core = report.spec.coreAction {
            row("핵심 행동률 (\(core.label): \(core.events.joined(separator: ", ")))") { metrics in
                guard let rate = metrics.coreActionRate else { return "설치 없음" }
                return "\(ReleaseHealth.percent(rate)) (\(metrics.coreActionInstalls ?? 0)대)"
            }
        }
        if report.stabilityKnown {
            row("크래시 없는 설치") { metrics in
                guard let rate = metrics.crashFreeRate else { return "설치 없음" }
                return "\(ReleaseHealth.percent(rate)) (불안정 \(metrics.unstableInstalls ?? 0)대)"
            }
            row("불안정 갈래별 설치") { sliceText($0) }
        }
        row("크래시 보고") { "\($0.crashReports)건" }
        row("피드백") { metrics in
            metrics.bugFeedback.map { "\(metrics.feedback)건 (버그 \($0))" } ?? "\(metrics.feedback)건"
        }
        if let share = report.adoption.share {
            lines.append("")
            lines.append("채택: 최근 \(ReleaseHealth.adoptionDays)일 활성 \(report.adoption.active)대 중 \(report.adoption.onLatest)대(\(ReleaseHealth.percent(share)))가 \(latest.version)")
        }
        if !latest.newSignatures.isEmpty {
            lines.append("")
            lines.append("## \(latest.version)에서 처음 본 진단")
            for signature in latest.newSignatures {
                lines.append("- \(CrashReport.label(for: signature.kind)) · \(signature.title) — \(signature.reports)건 (지문 \(signature.fingerprint))")
            }
        }
        lines.append("")
        lines.append("## 판정 기준")
        let thresholds = report.spec.thresholds
        lines.append("- 불안정 이벤트: \(report.spec.stabilityEvents.joined(separator: ", ")) — 이걸 보낸 설치를 불안정으로 셉니다.")
        if let previous, report.stabilityKnown {
            let fresh = newSlices(latest: latest, previous: previous)
            if !fresh.isEmpty {
                lines.append("- 앞 버전에 없던 불안정 갈래: \(fresh.joined(separator: ", ")). 앱이 이 갈래를 새로 보내기 시작했다면 두 버전의 크래시 없는 설치는 같은 잣대가 아닙니다.")
            }
        }
        lines.append("- 크래시 없는 설치 \(ReleaseHealth.percent(thresholds.crashFreeInstallsMin)) 미만이면 빨강, 핵심 행동률이 앞 버전보다 \(ReleaseHealth.percent(thresholds.coreActionDropMax)) 넘게 떨어지고 그 차이가 우연으로 설명되지 않으면 빨강(표본이 작아 흔들림 안이면 노랑), 활성 설치 \(thresholds.minInstallsForVerdict)대 미만이면 비율로 판정하지 않습니다.")
        if !report.hasReleaseSpec {
            lines.append("- 앱 리포의 docs/usage-spec.json 에 release 절이 없어 기본값으로 판정했습니다.")
        }
        if !report.spec.promises.isEmpty {
            lines.append("")
            lines.append("## 이 앱이 지키기로 한 약속")
            for promise in report.spec.promises {
                lines.append("- \(promise.title)" + (promise.guardText.map { " (지키는 것: \($0))" } ?? ""))
            }
        }
        lines.append("")
        lines.append("## 부탁")
        lines.append("1. \(previous.map { "\($0.version) → " } ?? "")\(latest.version) 사이의 변경(git log · diff)에서 "
                     + (isGreen ? "아직 숫자에 안 잡힌 위험이 있는지 봐 주세요." : "위 신호의 원인을 찾아 주세요."))
        lines.append("2. 크래시라면 지문 · 제목으로 코드 위치를 짚고, 불안정 이벤트(\(report.spec.stabilityEvents.joined(separator: ", ")))가 늘었다면 그 이벤트를 보내는 경로를 확인해 주세요.")
        lines.append("3. 원인과 고친 방법을 설명하고, 고칠 수 있으면 고쳐 주세요. 숫자만으로 확실하지 않으면 무엇을 더 봐야 하는지 알려 주세요.")
        lines.append("")
        lines.append("참고: 크래시 보고는 MetricKit 이 하루쯤 늦게 일부만 보냅니다. 숫자는 FeedbackHub 사용 이벤트 기준입니다.")
        return lines.joined(separator: "\n")
    }

    /// 초록까지 남은 일. 고칠 것과 기다릴 것을 나눠, 지금 손댈 수 있는 것이 무엇인지 바로 보이게 한다.
    private func toGreen(_ steps: [ReleaseHealth.Step]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("초록이 되려면")
                .font(.body.weight(.semibold))
            ForEach([ReleaseHealth.Step.Kind.fix, .wait], id: \.self) { kind in
                let group = steps.filter { $0.kind == kind }
                if !group.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .fix ? "고칠 것" : "기다릴 것")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        ForEach(group) { step in
                            Label(step.text, systemImage: kind == .fix ? "wrench.and.screwdriver" : "hourglass")
                                .font(.body)
                                .foregroundStyle(kind == .fix ? Color.primary : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                if !latest.unstableBySlice.isEmpty || !(previous?.unstableBySlice.isEmpty ?? true) {
                    row("불안정 갈래", Self.sliceText(latest), previous.map(Self.sliceText))
                }
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

    /// 불안정 이벤트를 갈래마다. 많은 것부터, 기본형 이름은 떼고 갈래만 적는다.
    private static func sliceText(_ metrics: ReleaseHealth.VersionMetrics) -> String {
        guard !metrics.unstableBySlice.isEmpty else { return "없음" }
        return metrics.unstableBySlice
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\(sliceLabel($0.key)) \($0.value)대" }
            .joined(separator: " · ")
    }

    private static func sliceLabel(_ name: String) -> String {
        let parts = name.split(separator: ":", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : "(갈래 없음)"
    }

    /// 최신 버전에만 있는 불안정 갈래.
    private static func newSlices(latest: ReleaseHealth.VersionMetrics,
                           previous: ReleaseHealth.VersionMetrics) -> [String] {
        latest.unstableBySlice.keys
            .filter { previous.unstableBySlice[$0] == nil }
            .sorted()
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
                note("이 기기에는 원본 이벤트가 \(AppFormat.dateTime(start))부터만 있어, 그 앞의 활동은 빠진 채로 셌습니다. 숫자를 새로고침하면 창 시작까지 다시 받습니다.")
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
        case .unknown: return .secondary
        case .yellow: return .orange
        case .red: return .red
        }
    }

    static func symbol(_ level: ReleaseHealth.Level) -> String {
        switch level {
        case .green: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
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

// MARK: - 곤란을 겪는 사용자

/// 최근 버전을 나란히 놓고 고른 버전의 파이를 보인다. 최신 버전 설치가 적으면
/// 판정할 만큼 쓴 가장 새 버전부터 연다 — "모자라다" 한마디로 끝내지 않으려고.
private struct PeopleByVersion: View {
    let versions: [ReleaseHealth.VersionMetrics]
    /// 판정에 필요한 활성 설치 수. 이보다 적은 버전은 "표본 적음"을 붙인다.
    let enough: Int
    @State private var chosen: String?

    private var shown: [ReleaseHealth.VersionMetrics] { versions.filter { $0.people != nil } }

    private var current: ReleaseHealth.VersionMetrics? {
        let shown = shown
        if let chosen, let match = shown.first(where: { $0.version == chosen }) { return match }
        return shown.first { $0.activeInstalls >= enough } ?? shown.first
    }

    var body: some View {
        if let current, let people = current.people {
            VStack(alignment: .leading, spacing: 10) {
                if shown.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shown, id: \.version) { metrics in chip(metrics, isOn: metrics.version == current.version) }
                        }
                    }
                }
                PeoplePie(version: current.version, people: people)
                if current.activeInstalls < enough {
                    Text("\(current.version)은 아직 \(current.activeInstalls)대만 써서 비율이 크게 흔들립니다. 판정에는 \(enough)대가 필요해요.")
                        .font(.hubCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 버전 하나. 곤란 비율을 함께 적어 누르기 전에도 버전끼리 견줄 수 있게 한다.
    private func chip(_ metrics: ReleaseHealth.VersionMetrics, isOn: Bool) -> some View {
        let people = metrics.people!
        let troubled = (people.troubled ?? 0) + (people.stuck ?? 0)
        let rate = people.total > 0 ? "\(Int((100 * Double(troubled) / Double(people.total)).rounded()))%" : "—"
        let isFirst = metrics.version == versions.first?.version
        return Button {
            chosen = metrics.version
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(metrics.version + (isFirst ? " · 최신" : ""))
                    .font(.body.weight(.semibold))
                Text(metrics.activeInstalls < enough ? "\(people.total)명 · 표본 적음" : "\(people.total)명 · 곤란 \(rate)")
                    .font(.hubCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 최신 버전 사용자를 곤란 · 막힘 · 괜찮음으로 가른 도넛. 판정 글보다 먼저 "몇 명이 힘든가"를
/// 한눈에 보이려고 둔다. 조각마다 아이콘 · 이름 · 수를 범례에 적어 색만으로 읽지 않게 한다.
private struct PeoplePie: View {
    let version: String
    let people: ReleaseHealth.People
    @State private var selectedAngle: Int?

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let tint: Color
        let count: Int
    }

    private var slices: [Slice] {
        var all: [Slice] = []
        if let troubled = people.troubled {
            all.append(Slice(id: "troubled", label: "크래시 · 실행 실패를 겪음", symbol: "xmark.octagon.fill",
                             tint: .red, count: troubled))
        }
        if let stuck = people.stuck {
            all.append(Slice(id: "stuck", label: "핵심 기능까지 못 감", symbol: "exclamationmark.triangle.fill",
                             tint: .orange, count: stuck))
        }
        all.append(Slice(id: "fine", label: "문제없이 씀", symbol: "checkmark.circle.fill", tint: .green, count: people.fine))
        return all
    }

    private var troubledTotal: Int { (people.troubled ?? 0) + (people.stuck ?? 0) }

    private func percent(_ count: Int) -> String {
        people.total > 0 ? "\(Int((100 * Double(count) / Double(people.total)).rounded()))%" : "—"
    }

    /// 마우스를 올린 조각. 각도 값은 조각 수를 앞에서부터 쌓은 자리다.
    private var selected: Slice? {
        guard let selectedAngle else { return nil }
        var running = 0
        for slice in slices {
            running += slice.count
            if selectedAngle < running { return slice }
        }
        return nil
    }

    var body: some View {
        let slices = slices
        HStack(alignment: .center, spacing: 20) {
            Chart(slices) { slice in
                SectorMark(angle: .value("사용자", slice.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(slice.tint)
                    .opacity(selected == nil || selected?.id == slice.id ? 1 : 0.35)
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    if let selected {
                        Text(percent(selected.count)).font(.title2.monospacedDigit().weight(.bold))
                        Text("\(selected.count)명").font(.hubCaption).foregroundStyle(.secondary)
                    } else {
                        Text(percent(troubledTotal)).font(.title2.monospacedDigit().weight(.bold))
                        Text("곤란을 겪음").font(.hubCaption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(version) 사용자 \(people.total)명 중 곤란을 겪는 사람 \(troubledTotal)명, \(percent(troubledTotal))")

            VStack(alignment: .leading, spacing: 8) {
                Text("\(version) 사용자 \(people.total)명 중 \(troubledTotal)명이 곤란을 겪고 있어요")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        Image(systemName: slice.symbol).foregroundStyle(slice.tint)
                        Text(slice.label)
                        Spacer(minLength: 8)
                        Text("\(slice.count)명 · \(percent(slice.count))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                }
                Text("최근 \(ReleaseHealth.windowDays)일 동안 이 버전을 쓴 설치 하나를 한 사람으로 셉니다. 한 사람은 한 칸에만 들어갑니다.")
                    .font(.hubCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

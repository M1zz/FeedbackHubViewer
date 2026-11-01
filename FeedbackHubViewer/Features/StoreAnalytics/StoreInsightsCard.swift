//
//  StoreInsightsCard.swift
//  FeedbackHubViewer
//
//  스토어 분석 탭 맨 위 — 원본 행에서 읽은 판정(`StoreInsights`).
//
//  나쁜 것 → 지켜볼 것 → 좋은 것 → 읽을거리 차례. 몰린 기간이 있으면 그 기간과 평상시를
//  나란히 놓은 표를 판정 위에 둔다 — 판정이 왜 평상시 숫자로 하는지가 거기서 보인다.
//

import SwiftUI

struct StoreInsightsCard: View {
    let insights: StoreInsights
    /// 복사할 글 첫머리에 적는 이름. "전체 앱" 이면 앱이 정해지지 않은 것.
    let appName: String

    var body: some View {
        Card(title: "분석", systemImage: "text.magnifyingglass") {
            if let surge = insights.surge, let baseline = insights.baseline {
                comparison(surge, baseline)
            }
            if insights.findings.isEmpty {
                AnalyticsNote("아직 판정할 만큼 쌓이지 않았습니다. 리포트는 하루 한 파일씩 쌓이고, 표본이 작은 규칙은 말하지 않습니다.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insights.findings) { finding in
                        HStack(alignment: .top, spacing: 8) {
                            FindingRow(finding: finding)
                            ClaudeCopyIcon(text: Self.claudePrompt(finding, insights: insights, appName: appName))
                        }
                    }
                }
            }
        }
    }

    /// 판정 하나를 Claude 에게 넘길 글. 다른 판정도 함께 적어 앞뒤 사정을 알게 한다.
    static func claudePrompt(_ finding: StoreInsights.Finding, insights: StoreInsights, appName: String) -> String {
        var lines = ["\(appName) 의 App Store 분석에서 나온 판정입니다 (\(FindingRow.name(finding.level))).", ""]
        lines.append("## 판정")
        lines.append(finding.title)
        lines.append(finding.detail)
        if let action = finding.action { lines.append("제안된 할 일: \(action)") }
        let others = insights.findings.filter { $0.id != finding.id }
        if !others.isEmpty {
            lines.append("")
            lines.append("## 함께 나온 판정")
            lines += others.map { "- [\(FindingRow.name($0.level))] \($0.title): \($0.detail)" }
        }
        lines.append("")
        lines.append("## 부탁")
        lines.append(finding.level == .good || finding.level == .info
            ? "이 판정에서 이어서 할 만한 일이 있는지 앱 리포의 APPSTORE.md 와 코드를 보고 알려 주세요."
            : "앱 리포의 APPSTORE.md · 스크린샷 · 코드를 보고 원인을 찾아, 레포에서 고칠 수 있는 것은 고쳐 주세요.")
        lines.append("App Store Connect 는 직접 고치지 말고, 숫자만으로 확실하지 않으면 무엇을 더 봐야 하는지 알려 주세요.")
        return lines.joined(separator: "\n")
    }

    // MARK: 몰린 기간 · 평상시

    private func comparison(_ surge: StoreInsights.Period, _ baseline: StoreInsights.Period) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("\(surge.label) \(surge.range)").font(.headline)
                Text("\(baseline.label) \(baseline.range)").font(.headline)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            row("하루 첫 다운로드", AnalyticsFormat.decimal(surge.firstDownloadsPerDay), AnalyticsFormat.decimal(baseline.firstDownloadsPerDay))
            row("새 설치 · 삭제",
                "\(AnalyticsFormat.count(surge.newInstalls)) · \(AnalyticsFormat.count(surge.deletions))",
                "\(AnalyticsFormat.count(baseline.newInstalls)) · \(AnalyticsFormat.count(baseline.deletions))")
            row("하루 세션", surge.sessionsPerDay.map(AnalyticsFormat.count) ?? "—",
                baseline.sessionsPerDay.map(AnalyticsFormat.count) ?? "—")
            row("세션 길이", surge.averageDuration.map(AnalyticsFormat.seconds) ?? "—",
                baseline.averageDuration.map(AnalyticsFormat.seconds) ?? "—")
            row("검색 전환", surge.searchConversion.map(AnalyticsFormat.percent) ?? "—",
                baseline.searchConversion.map(AnalyticsFormat.percent) ?? "—")
        }
        .font(.body)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10, bordered: false)
    }

    private func row(_ title: String, _ surge: String, _ baseline: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(surge).monospacedDigit()
            Text(baseline).monospacedDigit().fontWeight(.semibold)
        }
    }
}

/// 판정 한 줄 — 점 · 제목 · 근거 · 할 일.
fileprivate struct FindingRow: View {
    let finding: StoreInsights.Finding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Self.color(finding.level))
                .frame(width: 10, height: 10)
                .accessibilityLabel(Self.name(finding.level))
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = finding.action {
                    Label(action, systemImage: "arrow.turn.down.right")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func color(_ level: StoreInsights.Level) -> Color {
        switch level {
        case .bad: return .red
        case .watch: return .orange
        case .good: return .green
        case .info: return .gray
        }
    }

    static func name(_ level: StoreInsights.Level) -> String {
        switch level {
        case .bad: return "문제"
        case .watch: return "지켜볼 것"
        case .good: return "좋음"
        case .info: return "참고"
        }
    }
}

//
//  AppBriefing.swift
//  FeedbackHubViewer
//
//  앱 하나의 브리핑 — 맥의 오른쪽 칸(`AppDashboardPanel`). 위에서 아래로 읽으면 끝난다:
//
//   1. 지금 어떤가 — 한 줄 판정(급한 것 N · 볼 것 N · 문제 없음).
//   2. 무엇이 문제인가 — 표시마다 한 줄씩, **그 안의 것 자체**와 함께. "진단 1" 이 아니라 어느
//      버전에서 무슨 크래시가 났는지, "피드백 2" 가 아니라 그 글. 급한 것부터, 누르면 그 칸.
//   3. 어디로 가고 있나 — 사용 · 다운로드 30일 선(홈 카드와 같은 숫자).
//   4. 그 밖의 상태 — 릴리즈 판정 · 버전 · 설치 · 차트 한 줄씩.
//
//  예전에는 칸 열네 개를 카드로 다 세웠다. 대부분이 "없음" · "0건" 이라 문제가 그 사이에
//  묻혔고, 같은 목록이 왼쪽 사이드바에 이미 있었다. 이제 문제가 없는 칸은 여기 서지 않는다.
//

import SwiftUI

struct AppBriefing: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var icons = StoreIcons.shared
    @ObservedObject private var changes = SectionChanges.shared

    let project: String
    var onClose: (() -> Void)? = nil

    private typealias Signal = AppGridHome.Signal

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases,
                                     design: design, charts: charts, news: news)
        let row = AppGridHome.row(project, store: store, metrics: metrics, keywords: keywords, purchases: purchases)
        let problems = row.signals.filter { $0.kind.tier != .chore && $0.kind.tier != .good }
        let chores = row.signals.filter { $0.kind.tier == .chore }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(row)

                if problems.isEmpty {
                    Label("지금 문제 없음", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.green.opacity(0.1)))
                } else {
                    group("문제") {
                        ForEach(problems) { signal in
                            problem(signal, row: row, metrics: metrics)
                        }
                    }
                }

                if !row.good.isEmpty {
                    group("좋은 소식") {
                        ForEach(row.good) { signal in
                            line(systemImage: signal.kind.systemImage, tint: .green,
                                 title: signal.kind.label,
                                 value: AppGridHome.chipText(signal, named: false),
                                 section: signal.kind.section)
                        }
                    }
                }

                if row.activity != nil || row.downloads != nil {
                    group("추이 · 30일") {
                        if let activity = row.activity { trend(activity, tint: AppGridHome.activityTint, section: .stats) }
                        if let downloads = row.downloads { trend(downloads, tint: AppGridHome.downloadTint, section: .acquisition) }
                    }
                }

                if !chores.isEmpty {
                    group("알아 둘 것") {
                        ForEach(chores) { signal in
                            line(systemImage: signal.kind.systemImage, tint: .secondary,
                                 title: signal.kind.label, value: AppFormat.count(signal.count),
                                 section: signal.kind.section)
                        }
                    }
                }

                group("상태") {
                    ForEach(facts(metrics), id: \.title) { fact in
                        line(systemImage: fact.section.systemImage, tint: fact.isBad ? .red : .secondary,
                             title: fact.title, value: fact.value, section: fact.section, isBad: fact.isBad)
                    }
                }
            }
            .padding(14)
        }
        .background(.background)
        .task(id: project) {
            await icons.resolve([project], keywords: keywords)
            await purchases.loadSales()
        }
    }

    // MARK: - Header

    private func header(_ row: AppGridHome.Row) -> some View {
        let critical = row.signals.filter { $0.kind.tier == .critical }.count
        let voice = row.signals.filter { $0.kind.tier == .voice }.count
        return HStack(spacing: 10) {
            AppIcon(url: icons.url(for: project, keywords: keywords), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                    .lineLimit(1)
                Group {
                    if critical > 0 {
                        Text("급한 것 \(critical)" + (voice > 0 ? " · 볼 것 \(voice)" : ""))
                            .foregroundStyle(.red)
                    } else if voice > 0 {
                        Text("볼 것 \(voice)").foregroundStyle(.orange)
                    } else {
                        Text(store.platformTag(for: project) ?? "조용함").foregroundStyle(.secondary)
                    }
                }
                .font(.body.weight(critical + voice > 0 ? .semibold : .regular))
            }
            Spacer(minLength: 4)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("브리핑 닫기 (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Problems

    /// 문제 하나 — 무엇이 몇 건인지와, 그 안의 것 한두 줄.
    private func problem(_ signal: Signal, row: AppGridHome.Row, metrics: SectionMetrics) -> some View {
        let kind = signal.kind
        let isCritical = kind.tier == .critical
        let lines = SignalEvidence.lines(signal, row: row, store: store, purchases: purchases)
        return Button {
            store.open(project: project, section: kind.section)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(kind.label)
                            .font(.body.weight(.semibold))
                        Text(kind == .usageDrop ? "▼\(signal.count)%" : "\(AppFormat.count(signal.count))건")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(kind.tint)
                    }
                    // 같은 글이 두 번 올 수 있다(같은 피드백 문구) — 글이 아니라 차례로 가른다.
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(kind.tint.opacity(isCritical ? 0.12 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isCritical ? AnyShapeStyle(Color.red.opacity(0.45)) : AnyShapeStyle(.clear), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Trend

    private func trend(_ metric: AppGridHome.Metric, tint: Color, section: FeedbackStore.ProjectSection) -> some View {
        Button {
            store.open(project: project, section: section)
        } label: {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(AppFormat.count(metric.current))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        HomeDelta(current: metric.current, previous: metric.previous)
                            .font(.body.monospacedDigit())
                    }
                }
                .fixedSize()
                Sparkline(points: metric.points, tint: tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Facts

    private struct Fact {
        let title: String
        let value: String
        let section: FeedbackStore.ProjectSection
        var isBad = false
    }

    /// 문제는 아니지만 늘 알고 싶은 것 — 값이 있는 것만.
    private func facts(_ metrics: SectionMetrics) -> [Fact] {
        var result: [Fact] = []
        if let level = store.releaseLevel(for: project) {
            result.append(Fact(title: "릴리즈", value: level.label, section: .release, isBad: level == .red))
        }
        if let version = purchases.versions[project] {
            result.append(Fact(title: "버전", value: "v\(version.version) · \(version.stateLabel)", section: .release))
        }
        for section in [FeedbackStore.ProjectSection.stats, .acquisition, .charts, .keywords, .reviews] {
            let value = metrics.label(section, project: project)
            // "없음" 류는 세우지 않는다 — 빈 줄이 문제를 가린다.
            guard !Self.emptyWords.contains(where: value.contains) else { continue }
            result.append(Fact(title: section.rawValue, value: value, section: section))
        }
        return result
    }

    private static let emptyWords = ["없음", "아직", "안 함", "확인 전", "연결 안 됨", "밖"]

    private func line(systemImage: String, tint: Color, title: String, value: String,
                      section: FeedbackStore.ProjectSection, isBad: Bool = false) -> some View {
        Button {
            store.open(project: project, section: section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(isBad ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// 표시 하나의 근거 — 홈의 "지금 급한 것" 과 앱 브리핑이 같은 말을 쓴다.
@MainActor
enum SignalEvidence {
    /// 그 표시 안의 것 — 가장 최근 한두 건을 말로.
    static func lines(_ signal: AppGridHome.Signal, row: AppGridHome.Row,
                      store: FeedbackStore, purchases: AppStoreConnectStore) -> [String] {
        let project = row.project
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        switch signal.kind {
        case .crash, .hang:
            let wantsCrash = signal.kind == .crash
            let reports = store.crashes(for: project)
                .filter { ($0.receivedAt ?? .distantPast) >= weekAgo && ($0.kind == "crash") == wantsCrash }
                .sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
            // 어느 버전에 몰렸나가 먼저 — 고칠 곳을 가른다.
            let versions = Dictionary(grouping: reports, by: \.appVersion).mapValues(\.count)
                .sorted { $0.value > $1.value }.prefix(2)
                .map { "\($0.key.isEmpty ? "버전 모름" : $0.key) \($0.value)건" }
            var lines = ["최근 7일 · " + versions.joined(separator: " · ")]
            if let latest = reports.first {
                let when = latest.receivedAt.map { AppFormat.relative($0) + " · " } ?? ""
                let detail = latest.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(when + (detail.isEmpty ? latest.kindLabel : detail))
            }
            return lines
        case .release:
            return Array(store.releaseHealth(for: project)?.verdict.reasons.prefix(2) ?? [])
        case .usageDrop:
            guard let activity = row.activity else { return [] }
            return ["7일 활성 \(AppFormat.count(activity.previous)) → \(AppFormat.count(activity.current))명"]
        case .feedback:
            return store.feedback(for: project).filter(store.isUnread)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                .prefix(2).map(\.snippet)
        case .newReview, .unansweredReview:
            let fresh = purchases.newReviewIDs(for: project)
            let reviews = (purchases.reviewFeeds[project]?.reviews ?? [])
                .filter { signal.kind == .newReview ? fresh.contains($0.id) : $0.response == nil }
                .sorted { ($0.rating, $1.createdDate) < ($1.rating, $0.createdDate) }   // 낮은 별 · 최근 것부터
            return reviews.prefix(2).map { review in
                let stars = String(repeating: "★", count: max(0, min(5, review.rating)))
                let text = [review.title, review.body].compactMap { $0 }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
                return "\(stars) \(text)"
            }
        case .storeIssue:
            guard case .ready(let analytics)? = purchases.storeAnalytics[project]?.value else { return [] }
            return analytics.insights?.findings.filter { $0.level == .bad }.prefix(2).map(\.title) ?? []
        case .usageUp:
            guard let trend = row.activity ?? row.downloads else { return [] }
            return ["\(trend.title) \(AppFormat.count(trend.previous)) → \(AppFormat.count(trend.current))"]
        case .purchase:
            return ["최근 7일 구매 완료 \(AppFormat.count(signal.count))건"]
        case .fiveStar:
            let since = Date().addingTimeInterval(-14 * 86_400)
            return (purchases.reviewFeeds[project]?.reviews ?? [])
                .filter { $0.rating == 5 && $0.createdDate >= since }
                .sorted { $0.createdDate > $1.createdDate }
                .prefix(2).map { review in
                    let text = [review.title, review.body].compactMap { $0 }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
                    return "\(review.territory) · \(text)"
                }
        case .news, .changed, .keyword:
            return []
        }
    }
}

//
//  PhoneOverviewView.swift
//  FeedbackHubViewer
//
//  아이폰의 첫 탭 "현황" — 열자마자 지금 어떤지가 한 장에 보이는 화면.
//
//  맥은 넓은 창에 기능 사이드바 · 앱 목록 · 화면을 나란히 펴 두고 고르며 읽는다. 아이폰은
//  주머니에서 꺼내 몇 초 보는 기기라, 고르기 전에 답부터 보여야 한다. 그래서 위에서부터:
//
//   1. 한 줄 판정 — 손볼 것이 있나, 없나.
//   2. 지금 볼 것 — 뱃지가 선 기능마다 그 안의 것 자체. "피드백 4" 가 아니라 그 피드백 글,
//      새 리뷰의 별과 본문, 빨강인 까닭, 바뀐 숫자. 열어 보지 않아도 무슨 일인지 읽힌다.
//   3. 숫자 타일 — 설치 · 활성 · 릴리즈 · 진단 · 피드백 · 리뷰 · 차트 · 키워드. 두 칸씩.
//   4. 앱별 — 앱마다 카드 하나에 이름 · 주 지표 · 신호등, 그리고 할 말이 있는 것만 칩으로.
//
//  숫자와 말은 모두 `SectionMetrics` 에서 읽는다(기능 목록 · 앱 목록과 같은 셈). 글자는
//  자르지 않는다 — 넘치면 줄을 넘기고, 칩은 다음 줄로 흐른다.
//

#if os(iOS)
import SwiftUI

struct PhoneOverviewView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var changes = SectionChanges.shared
    @ObservedObject private var marketing = MarketingStore.shared
    @ObservedObject private var leadStore = LeadStore.shared
    @ObservedObject private var icons = StoreIcons.shared

    /// 앱 카드를 처음엔 이만큼만 — 나머지는 "모두 보기".
    @State private var showsAllApps = false
    private static let initialApps = 6

    /// 숫자 타일에 올릴 기능, 이 차례로.
    private static let tileSections: [FeedbackStore.ProjectSection] = [
        .stats, .release, .crashes, .feedback, .reviews, .charts, .keywords, .news,
    ]

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases,
                                     design: design, charts: charts, news: news)
        let attention = attentionItems(metrics)
        let apps = appEntries(metrics)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headline(attention)
                if !attention.isEmpty { attentionSection(metrics) }
                tilesSection(metrics)
                appsSection(apps, metrics: metrics)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("현황")
        .refreshable { await HubRefresh.now(store, purchases) }
        .task(id: apps.count) { await icons.resolve(apps.map(\.key), keywords: keywords) }
    }

    // MARK: - 1. 한 줄 판정

    private func headline(_ attention: [Attention]) -> some View {
        let total = attention.reduce(0) { $0 + $1.badge.count }
        return VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(total > 0 ? "볼 곳 \(attention.count)군데" : "모두 조용합니다")
                    .font(.title2.weight(.bold))
            } icon: {
                Image(systemName: total > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(total > 0 ? Color.orange : Color.green)
                    .font(.title2)
            }
            Text(total > 0
                 ? attention.prefix(3).map { "\($0.section.rawValue) \($0.badge.count)" }.joined(separator: " · ")
                 : "새 피드백 · 진단 · 리뷰 · 바뀐 숫자가 없습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 2. 지금 볼 것

    private struct Attention: Identifiable {
        let section: FeedbackStore.ProjectSection
        let badge: SectionMetrics.Badge
        let detail: String
        var id: String { section.rawValue }
    }

    private func attentionItems(_ metrics: SectionMetrics) -> [Attention] {
        // 할 일은 안 읽은 피드백 · 답 안 한 리뷰를 다시 센 것이라 따로 세지 않는다 — 그 글들은
        // 피드백 · 리뷰 카드에 그대로 나온다.
        FeedbackStore.PhoneTab.allCases.flatMap(\.sections)
            .filter { $0 != .inbox }
            .compactMap { section in
                metrics.badge(section, project: nil).map {
                    Attention(section: section, badge: $0, detail: metrics.label(section, project: nil))
                }
            }
            .sorted { $0.badge.count > $1.badge.count }
    }

    private func attentionSection(_ metrics: SectionMetrics) -> some View {
        let findings = findings(metrics)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("지금 볼 것")
            ForEach(findings) { finding in
                FindingCard(finding: finding)
            }
        }
    }

    /// 뱃지가 선 칸마다 그 안의 것 자체 — "안 읽은 피드백 4" 가 아니라 그 피드백 글, 새 리뷰의
    /// 별과 본문, 빨강인 까닭, 바뀐 숫자. 칸을 열지 않아도 무슨 일인지 읽힌다. 무거운 것부터.
    private func findings(_ metrics: SectionMetrics) -> [Finding] {
        var result: [Finding] = []
        let name = store.displayName(for:)

        // 릴리즈 — 바뀌었거나 아직 안 본 빨강인 앱의 판정 까닭.
        if let badge = metrics.badge(.release, project: nil) {
            let alerts = SectionChanges.shared.releaseAlerts(metrics: metrics)
            let changed = Dictionary(SectionChanges.shared.pendingLines(.release, metrics: metrics)
                .map { ($0.project, $0.lines) }, uniquingKeysWith: { a, _ in a })
            let apps = alerts.filter { $0.value > 0 }.map(\.key)
                .sorted { (store.releaseLevel(for: $0)?.rawValue ?? -1) > (store.releaseLevel(for: $1)?.rawValue ?? -1) }
            let items = apps.map { project -> Finding.Item in
                let report = store.releaseHealth(for: project)
                var lines = changed[project] ?? []
                lines += report?.verdict.reasons.prefix(3) ?? []
                var meta = [String]()
                if let level = store.releaseLevel(for: project) { meta.append(level.label) }
                if let version = report?.latest.version { meta.append(version) }
                return Finding.Item(id: "release|\(project)", title: name(project),
                                    meta: meta.joined(separator: " · "), lines: lines,
                                    route: .project(project, .release))
            }
            result.append(Finding(section: .release, badge: badge, items: items))
        }

        // 진단 — 아직 안 본 것, 최근 것부터.
        if let badge = metrics.badge(.crashes, project: nil) {
            let fresh = store.newCrashIDs(for: nil)
            let reports = store.crashes(for: nil).filter { fresh.contains($0.id) }
                .sorted { ($0.occurredAt ?? $0.receivedAt ?? .distantPast) > ($1.occurredAt ?? $1.receivedAt ?? .distantPast) }
            let items = reports.map { report -> Finding.Item in
                var meta = [report.kindLabel, report.appVersion]
                if let date = report.occurredAt ?? report.receivedAt { meta.append(AppFormat.relative(date)) }
                return Finding.Item(id: "crash|\(report.id)", title: name(report.projectKey),
                                    meta: meta.filter { !$0.isEmpty }.joined(separator: " · "),
                                    lines: [report.detail].filter { !$0.isEmpty },
                                    route: .project(report.projectKey, .crashes))
            }
            result.append(Finding(section: .crashes, badge: badge, items: items))
        }

        // 리뷰 — 새 리뷰가 있으면 그것, 없으면 답 안 한 리뷰.
        if let badge = metrics.badge(.reviews, project: nil) {
            let fresh: Set<String> = store.showsBadge(.review) ? purchases.newReviewIDs(for: nil) : []
            var reviews: [(project: String, review: CustomerReview)] = []
            for (project, feed) in purchases.reviewFeeds where !store.hiddenProjects.contains(project) {
                for review in feed.reviews {
                    let wanted = fresh.isEmpty ? review.response == nil : fresh.contains(review.id)
                    if wanted { reviews.append((project, review)) }
                }
            }
            reviews.sort { $0.review.createdDate > $1.review.createdDate }
            let items = reviews.map { entry -> Finding.Item in
                let review = entry.review
                let stars = String(repeating: "★", count: max(0, min(5, review.rating)))
                    + String(repeating: "☆", count: max(0, 5 - review.rating))
                let text = [review.title, review.body].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
                return Finding.Item(id: "review|\(review.id)", title: name(entry.project),
                                    meta: "\(stars) · \(review.territoryName) · \(AppFormat.relative(review.createdDate))",
                                    lines: text, emphasizesFirstLine: review.title?.isEmpty == false,
                                    translatesLines: true,
                                    route: .project(entry.project, .reviews))
            }
            result.append(Finding(section: .reviews, badge: badge, items: items))
        }

        // 피드백 — 안 읽은 것, 최근 것부터. 누르면 그 피드백이 바로 열린다.
        if let badge = metrics.badge(.feedback, project: nil) {
            let unread = store.feedback(for: nil).filter(store.isUnread)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            let items = unread.map { feedback -> Finding.Item in
                var meta: [String] = []
                if let type = feedback.feedbackType?.trimmed, !type.isEmpty { meta.append(type) }
                if let rating = feedback.rating { meta.append("별 \(rating)") }
                if let version = feedback.appVersion, !version.isEmpty { meta.append(version) }
                if feedback.createdAt != nil { meta.append(feedback.createdAtRelative) }
                return Finding.Item(id: "feedback|\(feedback.id)", title: name(feedback.projectKey),
                                    meta: meta.joined(separator: " · "), lines: [feedback.text.trimmed],
                                    translatesLines: true,
                                    route: .feedback(feedback))
            }
            result.append(Finding(section: .feedback, badge: badge, items: items))
        }

        // 레딧 질문 — 아직 안 본 새 질문.
        if let badge = metrics.badge(.leads, project: nil) {
            let ids = leadStore.unseenIDs(for: nil)
            let leads = leadStore.open(for: nil).filter { ids.contains($0.id) }
            let items = leads.map { lead -> Finding.Item in
                var meta = ["r/\(lead.subreddit)"]
                if let date = lead.date { meta.append(AppFormat.relative(date)) }
                return Finding.Item(id: "lead|\(lead.id)", title: name(lead.project),
                                    meta: meta.joined(separator: " · "),
                                    lines: [lead.title, lead.snippet].map(\.trimmed).filter { !$0.isEmpty },
                                    emphasizesFirstLine: true,
                                    route: .project(lead.project, .leads))
            }
            result.append(Finding(section: .leads, badge: badge, items: items))
        }

        // 소식 — 안 읽은 것.
        if let badge = metrics.badge(.news, project: nil) {
            let fresh = news.items.filter { $0.foundAt > news.lastReadAt }
                .sorted { $0.date > $1.date }
            let items = fresh.map { item -> Finding.Item in
                Finding.Item(id: "news|\(item.id)", title: name(item.project),
                             meta: AppFormat.relative(item.date),
                             lines: [item.title, item.body].map(\.trimmed).filter { !$0.isEmpty },
                             emphasizesFirstLine: true,
                             route: .project(nil, .news))
            }
            result.append(Finding(section: .news, badge: badge, items: items))
        }

        // 본 뒤 바뀐 숫자 — 통계 · 키워드 · 차트 · 분석 … 칸마다, 앱마다 무엇이 어떻게.
        for section in SectionChanges.tracked where section != .release {
            guard let badge = metrics.badge(section, project: nil) else { continue }
            let items = SectionChanges.shared.pendingLines(section, metrics: metrics).map { entry in
                Finding.Item(id: "\(section.rawValue)|\(entry.project)", title: name(entry.project),
                             meta: nil, lines: entry.lines, route: .project(entry.project, section))
            }
            guard !items.isEmpty else { continue }
            result.append(Finding(section: section, badge: badge, items: items))
        }

        return result
    }

    // MARK: - 3. 숫자 타일

    private func tilesSection(_ metrics: SectionMetrics) -> some View {
        let tiles = Self.tileSections.map { tile($0, metrics: metrics) }
        let rows = stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("한눈에")
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index]) { tile in
                            SectionLink(section: tile.section) {
                                TileView(tile: tile)
                            }
                            .buttonStyle(.plain)
                        }
                        if rows[index].count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    }
                }
            }
        }
    }

    fileprivate struct Tile: Identifiable {
        let section: FeedbackStore.ProjectSection
        let value: String
        let caption: String?
        let tint: Color
        let badge: Int
        var id: String { section.rawValue }
    }

    private func tile(_ section: FeedbackStore.ProjectSection, metrics: SectionMetrics) -> Tile {
        let badge = metrics.badge(section, project: nil)?.count ?? 0
        switch section {
        case .stats:
            let traffic = store.overallTraffic
            guard traffic.hasUsageData else {
                return Tile(section: section, value: "–", caption: "사용 통계 없음", tint: .blue, badge: badge)
            }
            return Tile(section: section, value: "MAU \(AppFormat.count(traffic.mau))",
                        caption: "설치 \(AppFormat.count(traffic.installs))대 · 7일 \(AppFormat.count(traffic.activeInstalls7))명",
                        tint: .blue, badge: badge)
        case .release:
            let levels = store.projectCounts.compactMap { store.releaseLevel(for: $0.key) }
            let red = levels.filter { $0 == .red }.count
            let yellow = levels.filter { $0 == .yellow }.count
            let green = levels.filter { $0 == .green }.count
            let unknown = levels.filter { $0 == .unknown }.count
            return Tile(section: section,
                        value: levels.isEmpty ? "–" : (red > 0 ? "빨강 \(red)" : "빨강 없음"),
                        caption: levels.isEmpty ? "판정 없음"
                            : "노랑 \(yellow) · 초록 \(green)" + (unknown > 0 ? " · 판단할 수 없음 \(unknown)" : ""),
                        tint: red > 0 ? .red : (yellow > 0 ? .orange : (green > 0 ? .green : .secondary)), badge: badge)
        case .crashes:
            let summary = store.crashSummary(for: nil)
            return Tile(section: section, value: "7일 \(AppFormat.count(summary.last7Days))건",
                        caption: "전체 \(AppFormat.count(summary.total))건",
                        tint: summary.last7Days > 0 ? .red : .green, badge: badge)
        case .feedback:
            let unread = store.unreadCount(for: nil)
            return Tile(section: section, value: unread > 0 ? "안 읽음 \(unread)" : metrics.label(section, project: nil),
                        caption: unread > 0 ? "전체 \(metrics.label(section, project: nil))" : "모두 읽음",
                        tint: unread > 0 ? .red : .teal, badge: badge)
        case .charts:
            return Tile(section: section, value: metrics.label(section, project: nil), caption: "인기 차트",
                        tint: .indigo, badge: badge)
        case .keywords:
            return Tile(section: section, value: metrics.label(section, project: nil), caption: "검색 순위",
                        tint: .mint, badge: badge)
        default:
            return Tile(section: section, value: metrics.label(section, project: nil), caption: nil,
                        tint: .purple, badge: badge)
        }
    }

    // MARK: - 4. 앱별

    private func appEntries(_ metrics: SectionMetrics) -> [(key: String, count: Int)] {
        let base = store.projectCounts.filter { $0.key != Feedback.unclassifiedProject }
        let traffic = store.trafficByProject
        func weight(_ key: String) -> Int {
            AppCard.watched.reduce(0) { $0 + (metrics.badge($1, project: key)?.count ?? 0) }
        }
        return base.sorted { lhs, rhs in
            let l = weight(lhs.key), r = weight(rhs.key)
            if (l > 0) != (r > 0) { return l > 0 }
            let lr = store.releaseLevel(for: lhs.key)?.rawValue ?? -1
            let rr = store.releaseLevel(for: rhs.key)?.rawValue ?? -1
            if lr != rr { return lr > rr }
            return (traffic[lhs.key]?.mau ?? 0) > (traffic[rhs.key]?.mau ?? 0)
        }
    }

    private func appsSection(_ apps: [(key: String, count: Int)], metrics: SectionMetrics) -> some View {
        let shown = showsAllApps ? apps : Array(apps.prefix(Self.initialApps))
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("앱별 · \(apps.count)개")
            ForEach(shown, id: \.key) { entry in
                let section = AppCard.watched.first { metrics.badge($0, project: entry.key) != nil } ?? .stats
                NavigationLink(value: FeedbackStore.ProjectRoute(project: entry.key, section: section)) {
                    AppCard(project: entry.key,
                            name: store.displayName(for: entry.key),
                            iconURL: icons.url(for: entry.key, keywords: keywords),
                            traffic: store.trafficByProject[entry.key],
                            release: store.releaseLevel(for: entry.key),
                            metrics: metrics)
                }
                .buttonStyle(.plain)
            }
            if apps.count > Self.initialApps {
                Button {
                    withAnimation { showsAllApps.toggle() }
                } label: {
                    Text(showsAllApps ? "접기" : "앱 \(apps.count - Self.initialApps)개 더 보기")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - 조각

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
    }

}

/// 기능 하나로 가는 링크 — 앱 목록을 거치는 기능은 앱 목록으로, 할 일 · 소식은 그 화면으로.
private struct SectionLink<Label: View>: View {
    let section: FeedbackStore.ProjectSection
    @ViewBuilder let label: Label

    var body: some View {
        if section.usesAppList {
            NavigationLink(value: FeedbackStore.SectionRoute(section: section)) { label }
        } else {
            NavigationLink(value: FeedbackStore.ProjectRoute(project: nil, section: section)) { label }
        }
    }
}

/// 숫자 타일 하나 — 기능 이름, 큰 값, 작은 설명. 두 칸이 한 줄이고 같은 줄은 높이가 같다.
private struct TileView: View {
    let tile: PhoneOverviewView.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: tile.section.systemImage)
                    .foregroundStyle(tile.tint)
                Text(tile.section.rawValue)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if tile.badge > 0 {
                    Text(tile.badge > 99 ? "99+" : "\(tile.badge)")
                        .font(.body.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .background(Color.red, in: Capsule())
                }
            }
            .font(.body.weight(.semibold))
            Text(tile.value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption = tile.caption {
                Text(caption)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// 앱 하나 — 이름 · 주 지표 · 신호등, 그리고 할 말이 있는 칸만 칩으로.
private struct AppCard: View {
    let project: String
    let name: String
    let iconURL: URL?
    let traffic: FeedbackStore.Traffic?
    let release: ReleaseHealth.Level?
    let metrics: SectionMetrics

    /// 앱 카드가 뱃지를 보는 칸 — 카드를 누르면 뱃지가 선 첫 칸으로 연다.
    static let watched: [FeedbackStore.ProjectSection] = [
        .feedback, .crashes, .reviews, .release, .stats, .charts, .keywords,
    ]

    private struct Chip: Identifiable {
        let text: String
        let systemImage: String
        let tint: Color
        var id: String { text }
    }

    private var chips: [Chip] {
        var chips: [Chip] = []
        for section in Self.watched {
            if let badge = metrics.badge(section, project: project) {
                chips.append(Chip(text: "\(badge.name) \(badge.count)", systemImage: badge.systemImage, tint: badge.tint))
            }
        }
        let crashes = metrics.store.crashSummary(for: project)
        if crashes.last7Days > 0, metrics.badge(.crashes, project: project) == nil {
            chips.append(Chip(text: "진단 7일 \(crashes.last7Days)건", systemImage: "exclamationmark.triangle", tint: .red))
        }
        let chart = metrics.label(.charts, project: project)
        if metrics.count(.charts, project: project) > 0 {
            chips.append(Chip(text: chart, systemImage: "list.number", tint: .indigo))
        }
        if metrics.keywords.standings(for: project).contains(where: \.isRanked) {
            chips.append(Chip(text: "키워드 \(metrics.label(.keywords, project: project))", systemImage: "magnifyingglass", tint: .mint))
        }
        return chips
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                AppIcon(url: iconURL, symbol: "app.dashed", tint: .accentColor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(usageLine)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let release {
                    ReleasePill(level: release)
                }
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            let chips = chips
            if !chips.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(chips) { chip in
                        Label(chip.text, systemImage: chip.systemImage)
                            .font(.body)
                            .foregroundStyle(chip.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(chip.tint.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var usageLine: String {
        guard let traffic, traffic.hasUsageData else { return "사용 통계 없음" }
        return "MAU \(AppFormat.count(traffic.mau)) · 설치 \(AppFormat.count(traffic.installs))대"
    }
}

/// 릴리즈 신호등 — 색 점과 말.
private struct ReleasePill: View {
    let level: ReleaseHealth.Level

    var body: some View {
        let tint: Color = level == .red ? .red : (level == .yellow ? .orange : .green)
        HStack(spacing: 5) {
            Circle().fill(level == .yellow ? Color.yellow : tint).frame(width: 10, height: 10)
            Text(level.label)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize()
        .accessibilityLabel("릴리즈 \(level.label)")
    }
}

/// "지금 볼 것" 의 칸 하나 — 그 칸이 지금 하는 말들.
fileprivate struct Finding: Identifiable {
    let section: FeedbackStore.ProjectSection
    let badge: SectionMetrics.Badge
    let items: [Item]
    var id: String { section.rawValue }

    struct Item: Identifiable {
        let id: String
        /// 앱 이름.
        let title: String
        /// 언제 · 어떤 종류 · 버전처럼 글 위에 작게 붙는 것.
        let meta: String?
        /// 그 일의 본문 — 피드백 글, 리뷰 제목과 본문, 판정 까닭, 바뀐 숫자.
        let lines: [String]
        var emphasizesFirstLine = false
        /// 남이 쓴 글(리뷰 · 피드백)이라 한국어로 옮겨 보여 줄 것.
        var translatesLines = false
        let route: Route
    }

    enum Route {
        case feedback(Feedback)
        case project(String?, FeedbackStore.ProjectSection)
    }
}

/// 칸 하나의 카드 — 머리(칸 이름 · 무엇 · 몇) 아래 그 안의 것 몇 개를 글 그대로. 나머지는
/// "더 보기" 로 칸을 연다. 글은 자르지 않는다.
private struct FindingCard: View {
    let finding: Finding
    private static let shown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: finding.section.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(finding.badge.tint, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 0) {
                    Text(finding.section.rawValue)
                        .font(.body.weight(.semibold))
                    Text(finding.badge.name)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(finding.badge.count > 99 ? "99+" : "\(finding.badge.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(finding.badge.tint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ForEach(finding.items.prefix(Self.shown)) { item in
                Divider().padding(.leading, 14)
                ItemLink(route: item.route) {
                    ItemRow(item: item)
                }
                .buttonStyle(.plain)
            }

            let rest = finding.items.count - Self.shown
            Divider().padding(.leading, 14)
            SectionLink(section: finding.section) {
                HStack {
                    Text(rest > 0 ? "\(rest)개 더 · \(finding.section.rawValue) 열기" : "\(finding.section.rawValue) 열기")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 한 건 — 앱 이름과 곁말, 그리고 본문 그대로.
private struct ItemRow: View {
    let item: Finding.Item

    @ViewBuilder
    private func lineText(_ line: String) -> some View {
        if item.translatesLines {
            KoreanText(line)
        } else {
            Text(line)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = item.meta, !meta.isEmpty {
                    Text(meta)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(item.lines.enumerated()), id: \.offset) { index, line in
                    lineText(line)
                        .font(index == 0 && item.emphasizesFirstLine ? .body.weight(.semibold) : .body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 한 건이 가는 곳 — 피드백은 그 글로, 나머지는 그 앱의 그 칸으로.
private struct ItemLink<Label: View>: View {
    let route: Finding.Route
    @ViewBuilder let label: Label

    var body: some View {
        switch route {
        case .feedback(let feedback):
            NavigationLink(value: feedback) { label }
        case .project(let project, let section):
            NavigationLink(value: FeedbackStore.ProjectRoute(project: project, section: section)) { label }
        }
    }
}
#endif

//
//  AppGridHome.swift
//  FeedbackHubViewer
//
//  맥 · 아이패드의 첫 화면 — 모든 앱을 카드 한 장씩으로. 앱이 마흔 개면 "기능 → 앱 목록"
//  으로는 무엇이 움직였는지 알려면 칸마다 목록을 훑어야 한다. 여기서는 사이드바를 걷고
//  앱마다 지난주와 견준 숫자 둘과 그 30일 선 · 손볼 것을 한 장에 적어, 훑는 것만으로
//  "어느 앱이 올랐고 내렸고 불렀는지" 가 보인다.
//
//  선은 둘이다(`Metric`).
//   · 사용 — 허브가 받은 하루 활성 사용자. 사용 통계를 안 보내는 앱은 App Store 분석
//     리포트의 하루 사용 기기(이미 받아 둔 것이 있을 때만 — 여기서 새로 받지 않는다).
//   · 다운로드 — App Store 판매 리포트의 날짜별 첫 다운로드. 리포트 하나에 모든 앱이
//     들어 있어 앱이 마흔 개여도 요청이 늘지 않는다. 연결이 없으면 허브가 본 신규 설치. 카드를 누르면 그 앱 하나로
//  보기로 들어가고(사이드바가 그 앱의 기능으로 선다), 홈 단추(⇧⌘H)로 돌아온다.
//
//  차례가 곧 읽는 순서다 — 임팩트가 큰 앱부터(`Row.impact`). 임팩트는 "무슨 일이 났나"
//  에 "몇 명이 쓰나" 를 곱한 것이다: 크래시 · 릴리즈 빨강 같은 급한 일이 가장 무겁고, 사용이
//  꺼지는 것, 답을 기다리는 목소리(피드백 · 리뷰)가 그다음이며, 같은 일이면 쓰는 사람이 많은
//  앱이 앞선다. 아무 일이 없으면 큰 앱부터.
//
//  뱃지는 종류로 나눈다(`Signal`). 예전에는 칸마다의 뱃지를 한 숫자로 더했는데, "키워드 다시
//  짤 때" · "본 뒤 바뀐 것" 처럼 급하지 않은 것이 앱마다 하나씩은 있어 모든 카드에 1이 섰고,
//  어느 앱부터 볼지 가르지 못했다. 이제 카드에는 종류마다 따로 서고(급한 것은 빨강, 목소리는
//  주황, 나머지는 회색), 위의 거르기도 종류별이다 — "크래시 난 앱만", "새 리뷰 온 앱만".
//

import SwiftUI

struct AppGridHome: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    @ObservedObject private var icons = StoreIcons.shared
    /// 뱃지가 바뀌면 다시 그린다.
    @ObservedObject private var changes = SectionChanges.shared

    @AppStorage("home-grid-sort") private var sortRaw = Sort.impact.rawValue
    @State private var filter: Filter = .all
    @State private var query = ""
    /// "지금 급한 것" 을 끝까지 펼쳤나.
    @State private var showsAllUrgent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 누른 카드의 자리(화면 안 비율) — 그 카드로 빨려 들어가듯 넘어가게(`SplitRootView`).
    @Binding var zoomAnchor: UnitPoint

    private static let space = "app-grid-home"

    enum Sort: String, CaseIterable, Identifiable {
        case impact = "임팩트 큰 순"
        case change = "많이 변한 순"
        case users = "사용자 많은 순"
        case name = "이름순"
        var id: String { rawValue }
    }

    enum Filter: Hashable {
        case all
        case kind(Signal.Kind)
        case up
        case down
    }

    /// 앱에 선 표시 하나 — 종류와 수.
    struct Signal: Identifiable, Hashable {
        let kind: Kind
        let count: Int
        var id: Kind { kind }

        /// 무거운 것부터.
        enum Kind: Int, CaseIterable, Identifiable {
            case crash, release, usageDrop, hang, feedback, newReview, storeIssue, unansweredReview
            case news, changed, keyword
            var id: Int { rawValue }

            /// 급한 것 · 사람이 기다리는 것 · 알아만 둘 것.
            enum Tier { case critical, voice, chore }

            var tier: Tier {
                switch self {
                case .crash, .release, .usageDrop: return .critical
                case .hang, .feedback, .newReview, .storeIssue, .unansweredReview: return .voice
                case .news, .changed, .keyword: return .chore
                }
            }

            var label: String {
                switch self {
                case .crash: return "크래시"
                case .release: return "릴리즈 빨강"
                case .usageDrop: return "사용 급감"
                case .hang: return "멈춤 · 디스크"
                case .feedback: return "안 읽은 피드백"
                case .newReview: return "새 리뷰"
                case .storeIssue: return "스토어 문제"
                case .unansweredReview: return "답 안 한 리뷰"
                case .news: return "새 소식"
                case .changed: return "본 뒤 바뀐 것"
                case .keyword: return "키워드 다시 짤 때"
                }
            }

            var systemImage: String {
                switch self {
                case .crash: return "bolt.trianglebadge.exclamationmark.fill"
                case .release: return "stethoscope"
                case .usageDrop: return "chart.line.downtrend.xyaxis"
                case .hang: return "hourglass"
                case .feedback: return "envelope.badge.fill"
                case .newReview: return "star.bubble.fill"
                case .storeIssue: return "bag.badge.questionmark"
                case .unansweredReview: return "bubble.left.fill"
                case .news: return "newspaper.fill"
                case .changed: return "sparkles"
                case .keyword: return "arrow.triangle.2.circlepath"
                }
            }

            var tint: Color {
                switch tier {
                case .critical: return .red
                case .voice: return .orange
                case .chore: return .secondary
                }
            }

            /// 누르면 갈 칸.
            var section: FeedbackStore.ProjectSection {
                switch self {
                case .crash, .hang: return .crashes
                case .release: return .release
                case .usageDrop: return .stats
                case .feedback: return .feedback
                case .newReview, .unansweredReview: return .reviews
                case .storeIssue: return .storeAnalytics
                case .news: return .news
                case .changed: return .stats
                case .keyword: return .keywords
                }
            }

            /// 한 건의 무게와 이 종류가 낼 수 있는 가장 큰 무게(`Row.impact`). 건수는 로그로
            /// 눌러 더한다 — 크래시 100건이 1건의 100배로 급하지는 않다.
            var weight: (base: Double, cap: Double) {
                switch self {
                case .crash: return (60, 100)
                case .release: return (80, 80)
                case .usageDrop: return (0, 60)     // 줄어든 비율로 따로 센다
                case .hang: return (12, 30)
                case .feedback: return (15, 45)
                case .newReview: return (12, 36)
                case .storeIssue: return (10, 30)
                case .unansweredReview: return (4, 12)
                case .news, .changed, .keyword: return (0.5, 1)
                }
            }
        }
    }

    /// 숫자 하나와 그 선 — "7일 활성 1,204 ▲12%" 와 30일 추이.
    struct Metric {
        let title: String
        /// 최근 7일과 그 앞 7일.
        let current: Int
        let previous: Int
        /// 날마다의 값, 오래된 것부터.
        let points: [FeedbackStore.DayCount]
        var delta: Int { current - previous }
        /// 지난주 대비 비율의 크기. 작은 앱의 1 → 2 가 "두 배" 로 맨 위에 서지 않게 분모를
        /// 5 아래로 내리지 않는다.
        var movement: Double { abs(Double(delta)) / Double(max(previous, 5)) }
    }

    /// 앱 한 장에 적을 것.
    struct Row: Identifiable {
        let project: String
        let name: String
        let usage: FeedbackStore.ProjectUsage
        /// 사용 추이. 허브에도 스토어에도 없으면 nil.
        let activity: Metric?
        /// 다운로드(없으면 신규 설치) 추이.
        let downloads: Metric?
        /// 이 앱에 선 표시들, 무거운 것부터.
        let signals: [Signal]
        var id: String { project }

        /// 급한 것(크래시 · 릴리즈 빨강 · 사용 급감)이 있나.
        var isCritical: Bool { signals.contains { $0.kind.tier == .critical } }
        func has(_ kind: Signal.Kind) -> Bool { signals.contains { $0.kind == kind } }

        /// 쓰는 사람 수 — 7일 활성, 없으면 7일 다운로드.
        var reach: Int { max(activity?.current ?? 0, downloads?.current ?? 0) }

        /// 어느 앱부터 볼까. **무슨 일이 났나 × 몇 명이 쓰나.**
        ///
        ///  · 일의 무게는 종류마다(`Signal.Kind.weight`) — 크래시 · 릴리즈 빨강이 가장 무겁고,
        ///    사용이 꺼지는 것은 줄어든 비율만큼, 피드백 · 리뷰가 그다음. 소식 · 바뀐 것 · 키워드는
        ///    거의 0 이라 차례를 바꾸지 못한다.
        ///  · 사람 수는 로그로 곱한다(10명 2배 · 1천 명 4배 · 10만 명 6배) — 큰 앱의 같은 일이
        ///    앞서되, 작은 앱의 크래시가 큰 앱의 새 소식 뒤로 밀리지는 않는다.
        ///  · 아무 일이 없으면 사람 수만 남아 큰 앱부터 선다.
        var impact: Double {
            var severity = 0.0
            for signal in signals {
                let weight = signal.kind.weight
                if signal.kind == .usageDrop {
                    severity += min(weight.cap, weight.cap * dropRatio * 2)
                } else {
                    severity += min(weight.cap, weight.base * (1 + log2(Double(max(signal.count, 1)))))
                }
            }
            let scale = 1 + log10(1 + Double(reach))
            return severity * scale + scale
        }

        /// 사용이 지난주보다 줄어든 비율(0~1). 늘었으면 0.
        var dropRatio: Double {
            guard let activity, activity.previous > 0, activity.delta < 0 else { return 0 }
            return Double(-activity.delta) / Double(activity.previous)
        }

        /// 올랐나 내렸나 — 사용이 먼저, 사용 숫자가 없는 앱은 다운로드로.
        var direction: Int { (activity ?? downloads)?.delta ?? 0 }
        /// 얼마나 움직였나 — 두 숫자 중 더 크게 움직인 쪽.
        var movement: Double { max(activity?.movement ?? 0, downloads?.movement ?? 0) }
        var users: Int { activity?.current ?? 0 }
    }

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases,
                                     design: design, charts: charts, news: news)
        let all = Self.rows(store: store, metrics: metrics, keywords: keywords, purchases: purchases)
        let shown = sorted(filtered(all))

        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary(all)
                urgent(all)
                controls(all)
                if shown.isEmpty {
                    Text(all.isEmpty ? "아직 앱이 없습니다. 새로고침하면 앱이 보낸 기록으로 채워집니다." : "여기에 맞는 앱이 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)], spacing: 12) {
                        ForEach(shown) { row in
                            tile(row)
                                .modifier(HoverLift(isOff: reduceMotion))
                                // 단추가 아니라 누른 자리를 받는 손짓 — 그 자리로 화면이 커지며 넘어간다.
                                .onTapGesture(coordinateSpace: .named(Self.space)) { location in
                                    open(row.project, at: location, in: viewport.size)
                                }
                                .accessibilityAction { store.open(project: row.project, section: nil) }
                            .contextMenu {
                                ForEach(row.signals) { signal in
                                    Button("\(signal.kind.label) \(AppFormat.count(signal.count)) 보기") {
                                        store.open(project: row.project, section: signal.kind.section)
                                    }
                                }
                                if !row.signals.isEmpty { Divider() }
                                Button("통계 열기") { store.open(project: row.project, section: .stats) }
                                Button("피드백 열기") { store.open(project: row.project, section: .feedback) }
                                Button("리뷰 열기") { store.open(project: row.project, section: .reviews) }
                            }
                        }
                    }
                    // 거르기 · 차례를 바꾸면 카드가 제자리를 찾아 미끄러진다.
                    .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: shown.map(\.id))
                }
            }
            .padding(20)
        }
        }
        .coordinateSpace(.named(Self.space))
        .background(.background)
        .navigationTitle("모든 앱")
        .task(id: all.map(\.project)) {
            await icons.resolve(all.map(\.project), keywords: keywords)
        }
        // 다운로드 선의 재료. 연결이 없으면 아무 일도 하지 않고, 받아 둔 날은 다시 받지 않는다.
        .task { await purchases.loadSales() }
    }

    /// 누른 자리를 적고 연다 — 앱 화면이 그 자리에서 다가온다(`SplitRootView`).
    private func open(_ project: String, at location: CGPoint, in size: CGSize) {
        if size.width > 0, size.height > 0 {
            zoomAnchor = UnitPoint(x: min(max(location.x / size.width, 0), 1),
                                   y: min(max(location.y / size.height, 0), 1))
        }
        store.open(project: project, section: nil)
    }

    // MARK: - Rows

    /// 선에 그리는 날 수.
    static let trendDays = 30

    static func rows(store: FeedbackStore, metrics: SectionMetrics,
                     keywords: KeywordStore, purchases: AppStoreConnectStore) -> [Row] {
        let sections = AppScopedSections.groups().flatMap(\.sections).flatMap(\.members)
        return SectionMetrics.keywordProjects(store).map { project in
            row(project, store: store, metrics: metrics, keywords: keywords, purchases: purchases, sections: sections)
        }
    }

    /// 앱 하나의 카드 — 홈의 카드와 앱 화면 오른쪽 브리핑(`AppBriefing`)이 같은 것을 본다.
    static func row(_ project: String, store: FeedbackStore, metrics: SectionMetrics,
                    keywords: KeywordStore, purchases: AppStoreConnectStore,
                    sections: [FeedbackStore.ProjectSection]? = nil) -> Row {
        let sections = sections ?? AppScopedSections.groups().flatMap(\.sections).flatMap(\.members)
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        do {
            let activity = activity(project, store: store, purchases: purchases)
            var counts: [Signal.Kind: Int] = [:]

            // 급한 것은 "안 읽음" 이 아니라 **지금 상태**로 센다 — 읽었다고 크래시가 멎지는 않는다.
            for report in store.crashes(for: project) where (report.receivedAt ?? .distantPast) >= weekAgo {
                counts[report.kind == "crash" ? .crash : .hang, default: 0] += 1
            }
            if store.releaseLevel(for: project) == .red { counts[.release] = 1 }
            // 지난주에 스무 명은 넘게 쓰던 앱이 3할 넘게 줄었으면 급한 일이다.
            if let activity, activity.previous >= 20, activity.delta < 0,
               Double(-activity.delta) / Double(activity.previous) >= 0.3 {
                counts[.usageDrop] = Int((Double(-activity.delta) / Double(activity.previous) * 100).rounded())
            }

            // 나머지는 칸의 뱃지 그대로 — 읽으면 지워진다.
            if let badge = metrics.itemBadge(.feedback, project: project) { counts[.feedback] = badge.count }
            if let badge = metrics.itemBadge(.reviews, project: project) {
                counts[badge.name == "새 리뷰" ? .newReview : .unansweredReview] = badge.count
            }
            if metrics.isAlarming(.storeAnalytics, project: project) {
                counts[.storeIssue] = metrics.count(.storeAnalytics, project: project)
            }
            if let badge = metrics.itemBadge(.news, project: project) { counts[.news] = badge.count }
            if let badge = metrics.itemBadge(.keywords, project: project),
               badge.action == SectionMetrics.keywordDueAction { counts[.keyword] = badge.count }
            // 본 뒤 바뀐 것 — 한 건씩 세는 뱃지가 없는 칸에 선 것만.
            let changed = sections.reduce(0) { sum, section in
                guard metrics.itemBadge(section, project: project) == nil,
                      let badge = metrics.badge(section, project: project) else { return sum }
                return sum + badge.count
            }
            if changed > 0 { counts[.changed] = changed }

            return Row(project: project,
                       name: store.displayName(for: project),
                       usage: store.usage(for: project),
                       activity: activity,
                       downloads: downloads(project, store: store, keywords: keywords, purchases: purchases),
                       signals: Signal.Kind.allCases.compactMap { kind in
                           counts[kind].map { Signal(kind: kind, count: $0) }
                       })
        }
    }

    /// 사용 — 허브의 하루 활성 사용자. 일 버킷이 그날의 설치 집합을 들고 있어 세기만 하면 된다.
    /// 숫자는 7일 창의 서로 다른 사람(`ProjectUsage`)이라 선의 합과는 다르다.
    static func activity(_ project: String?, store: FeedbackStore, purchases: AppStoreConnectStore) -> Metric? {
        let usage = store.usage(for: project)
        if usage.hasUsageData || project == nil {
            let days = store.days(for: project, audience: .all)
            let points = UsageRollups.recentDayKeys(trendDays).map {
                FeedbackStore.DayCount(date: $0.date, count: days[$0.key]?.installs.count ?? 0)
            }
            return Metric(title: "7일 활성", current: usage.activeInstalls7,
                          previous: usage.previousActiveInstalls7, points: points)
        }
        // 사용 통계를 안 보내는 앱 — 스토어 분석 리포트를 이미 받아 뒀으면 그 하루 사용 기기로.
        guard let project, case .ready(let analytics)? = purchases.storeAnalytics[project]?.value,
              let daily = analytics.sessions?.daily, !daily.isEmpty else { return nil }
        let points = daily.sorted { $0.day < $1.day }.compactMap { point in
            UsageRollups.date(fromDayKey: point.day).map { FeedbackStore.DayCount(date: $0, count: point.second.isFinite ? Int(point.second.rounded()) : 0) }
        }
        guard !points.isEmpty else { return nil }
        let (current, previous) = weeks(points.map(\.count))
        return Metric(title: "하루 사용 기기", current: current / 7, previous: previous / 7, points: points)
    }

    /// 다운로드 — 판매 리포트의 첫 다운로드. 리포트가 없거나 이 앱이 스토어와 안 이어졌으면
    /// 허브가 본 신규 설치.
    static func downloads(_ project: String, store: FeedbackStore, keywords: KeywordStore,
                          purchases: AppStoreConnectStore) -> Metric? {
        if let sales = purchases.sales, let trackId = keywords.trackId(for: project) {
            let series = sales.firstDownloadSeries(appleID: String(trackId))
            let points = zip(sales.dayKeys, series).compactMap { key, count in
                UsageRollups.date(fromDayKey: key).map { FeedbackStore.DayCount(date: $0, count: count) }
            }
            if !points.isEmpty {
                let (current, previous) = weeks(points.map(\.count))
                return Metric(title: "7일 다운로드", current: current, previous: previous, points: points)
            }
        }
        let usage = store.usage(for: project)
        guard usage.hasUsageData else { return nil }
        return Metric(title: "7일 신규", current: usage.new7, previous: usage.previousNew7,
                      points: store.dailyInstalls(for: project).suffix(trendDays)
                          .map { FeedbackStore.DayCount(date: $0.date, count: $0.count) })
    }

    /// 끝의 7일 합과 그 앞 7일 합.
    private static func weeks(_ counts: [Int]) -> (Int, Int) {
        (counts.suffix(7).reduce(0, +), counts.dropLast(7).suffix(7).reduce(0, +))
    }

    /// 모든 앱의 다운로드를 날마다 더한 것. 스토어 숫자가 하나라도 있으면 스토어 것만 더한다 —
    /// 허브가 본 설치와 섞으면 같은 사람을 두 번 센다.
    private func totalDownloads(_ rows: [Row]) -> Metric? {
        let fromStore = rows.compactMap(\.downloads).filter { $0.title == "7일 다운로드" }
        guard !fromStore.isEmpty else {
            let total = store.usage(for: nil)
            return Metric(title: "7일 신규 설치", current: total.new7, previous: total.previousNew7,
                          points: store.dailyInstalls(for: nil).suffix(Self.trendDays)
                              .map { FeedbackStore.DayCount(date: $0.date, count: $0.count) })
        }
        var byDay: [Date: Int] = [:]
        for metric in fromStore { for point in metric.points { byDay[point.date, default: 0] += point.count } }
        return Metric(title: "7일 다운로드", current: fromStore.reduce(0) { $0 + $1.current },
                      previous: fromStore.reduce(0) { $0 + $1.previous },
                      points: byDay.sorted { $0.key < $1.key }.map { FeedbackStore.DayCount(date: $0.key, count: $0.value) })
    }

    private func filtered(_ rows: [Row]) -> [Row] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            switch filter {
            case .all: break
            case .kind(let kind): if !row.has(kind) { return false }
            case .up: if row.direction <= 0 { return false }
            case .down: if row.direction >= 0 { return false }
            }
            return needle.isEmpty || row.name.localizedCaseInsensitiveContains(needle)
                || row.project.localizedCaseInsensitiveContains(needle)
        }
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        let byUsers: (Row, Row) -> Bool = {
            ($0.users, $0.downloads?.current ?? 0, $1.name) > ($1.users, $1.downloads?.current ?? 0, $0.name)
        }
        switch Sort(rawValue: sortRaw) ?? .impact {
        case .impact:
            return rows.sorted { $0.impact != $1.impact ? $0.impact > $1.impact : byUsers($0, $1) }
        case .change:
            return rows.sorted { $0.movement != $1.movement ? $0.movement > $1.movement : byUsers($0, $1) }
        case .users:
            return rows.sorted(by: byUsers)
        case .name:
            return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - Summary

    /// 맨 위 한 줄 — 모든 앱을 합친 숫자와, 오르고 내린 앱의 수.
    private func summary(_ rows: [Row]) -> some View {
        let up = rows.filter { $0.direction > 0 }.count
        let down = rows.filter { $0.direction < 0 }.count
        let critical = rows.filter(\.isCritical)
        let criticalKinds = Signal.Kind.allCases.filter { $0.tier == .critical }.compactMap { kind -> String? in
            let apps = rows.filter { $0.has(kind) }.count
            return apps > 0 ? "\(kind.label) \(apps)" : nil
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            figure("앱", value: "\(rows.count)개") {
                Text("오른 앱 \(up) · 내린 앱 \(down)")
                    .foregroundStyle(.secondary)
            }
            if let activity = Self.activity(nil, store: store, purchases: purchases) {
                figure(activity, tint: Self.activityTint)
            }
            if let downloads = totalDownloads(rows) {
                figure(downloads, tint: Self.downloadTint)
            }
            figure("급한 앱", value: critical.isEmpty ? "없음" : "\(critical.count)개") {
                Text(critical.isEmpty ? "크래시 · 릴리즈 빨강 · 사용 급감 없음" : criticalKinds.joined(separator: " · "))
                    .foregroundStyle(critical.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
            }
        }
    }

    static let activityTint = Color.accentColor
    static let downloadTint = Color.orange

    /// 숫자 · 증감과 그 옆의 30일 선.
    private func figure(_ metric: Metric, tint: Color) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(AppFormat.count(metric.current))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                HomeDelta(current: metric.current, previous: metric.previous)
                    .font(.body.monospacedDigit())
            }
            Sparkline(points: metric.points, tint: tint)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: metric.current)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, value: String, @ViewBuilder note: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            note()
                .font(.body.monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Urgent

    /// 지금 급한 것 — 모든 앱의 크래시 · 릴리즈 빨강 · 사용 급감을 한 줄씩, 임팩트가 큰 앱부터.
    /// 카드를 훑어 빨간 것을 찾지 않아도 되게, 무슨 일인지(어느 버전 · 최근 사고 · 판정 까닭)를
    /// 그 줄에 적는다. 누르면 그 앱의 그 칸이 바로 열린다. 급한 것이 없으면 자리를 차지하지 않는다.
    @ViewBuilder
    private func urgent(_ rows: [Row]) -> some View {
        let items = rows.sorted { $0.impact > $1.impact }.flatMap { row in
            row.signals.filter { $0.kind.tier == .critical }.map { (row: row, signal: $0) }
        }
        if !items.isEmpty {
            let limit = 5
            let shown = showsAllUrgent ? items : Array(items.prefix(limit))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("지금 급한 것 \(items.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    if items.count > limit {
                        Button(showsAllUrgent ? "접기" : "\(items.count - limit)건 더 보기") { showsAllUrgent.toggle() }
                            .buttonStyle(.borderless)
                            .font(.body)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().padding(.leading, 50) }
                        urgentRow(item.row, item.signal)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.35), lineWidth: 1))
            }
        }
    }

    private func urgentRow(_ row: Row, _ signal: Signal) -> some View {
        let kind = signal.kind
        let lines = SignalEvidence.lines(signal, row: row, store: store, purchases: purchases)
        return Button {
            store.open(project: row.project, section: kind.section)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Label(kind == .usageDrop ? "\(kind.label) ▼\(signal.count)%"
                                                 : "\(kind.label) \(AppFormat.count(signal.count))건",
                              systemImage: kind.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        if row.reach > 0 {
                            Text("쓰는 사람 \(AppFormat.count(row.reach))")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !lines.isEmpty {
                        Text(lines.joined(separator: "  ·  "))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private func controls(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                searchField
                Spacer(minLength: 8)
                sortPicker
            }
            filterBar(rows)
        }
    }

    /// 종류별 거르기 — 그 표시가 선 앱의 수와 함께. 앱이 하나도 없는 종류는 세우지 않는다.
    private func filterBar(_ rows: [Row]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.all, title: "전체", count: rows.count, systemImage: nil, tint: .accentColor)
                ForEach(Signal.Kind.allCases) { kind in
                    let apps = rows.filter { $0.has(kind) }.count
                    if apps > 0 {
                        filterChip(.kind(kind), title: kind.label, count: apps,
                                   systemImage: kind.systemImage, tint: kind.tint)
                    }
                }
                filterChip(.up, title: "오른 앱", count: rows.filter { $0.direction > 0 }.count,
                           systemImage: "arrow.up.right", tint: .green)
                filterChip(.down, title: "내린 앱", count: rows.filter { $0.direction < 0 }.count,
                           systemImage: "arrow.down.right", tint: .red)
            }
            .padding(.vertical, 1)
        }
    }

    private func filterChip(_ value: Filter, title: String, count: Int, systemImage: String?, tint: Color) -> some View {
        let isOn = filter == value
        return Button {
            filter = isOn ? .all : value
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                }
                Text(title)
                Text(AppFormat.count(count))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
            .font(.body)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? AnyShapeStyle(tint == .secondary ? Color.gray : tint)
                                            : AnyShapeStyle(.quaternary.opacity(0.6))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), 앱 \(count)개")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var sortPicker: some View {
        Picker("차례", selection: $sortRaw) {
            ForEach(Sort.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("앱 찾기", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 220)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.45)))
    }

    // MARK: - Tile

    private func tile(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 36)
                Text(row.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            if row.activity != nil || row.downloads != nil {
                HStack(alignment: .top, spacing: 12) {
                    number(row.activity, placeholder: "사용 기록 없음", tint: Self.activityTint)
                    number(row.downloads, placeholder: "다운로드 기록 없음", tint: Self.downloadTint)
                }
            } else {
                Text("사용 · 다운로드 기록 없음")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            }

            signalRow(row)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(row.isCritical ? AnyShapeStyle(.red.opacity(0.5)) : AnyShapeStyle(.clear), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// 카드 맨 아래 — 종류마다 따로 선 표시. 급한 것 · 목소리는 이름까지, 알아만 둘 것은 기호와
    /// 수만. 자리가 모자라면 전부 기호와 수로 줄인다. 누르면 그 칸으로 바로 간다.
    @ViewBuilder
    private func signalRow(_ row: Row) -> some View {
        if row.signals.isEmpty {
            Text("볼 것 없음")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(height: 26, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                signalChips(row, compact: false)
                signalChips(row, compact: true)
                signalChips(row, compact: true, limit: 5)
            }
            .frame(height: 26, alignment: .leading)
        }
    }

    private func signalChips(_ row: Row, compact: Bool, limit: Int? = nil) -> some View {
        let shown = limit.map { Array(row.signals.prefix($0)) } ?? row.signals
        return HStack(spacing: 6) {
            ForEach(shown) { signal in
                let kind = signal.kind
                let named = !compact && kind.tier != .chore
                Button {
                    store.open(project: row.project, section: kind.section)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: kind.systemImage)
                        if named { Text(kind.label) }
                        Text(kind == .usageDrop ? "▼\(signal.count)%" : AppFormat.count(signal.count))
                            .monospacedDigit()
                    }
                    .font(.body.weight(kind.tier == .critical ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(kind.tier == .critical ? AnyShapeStyle(.white) : AnyShapeStyle(kind.tint))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(kind.tier == .critical ? AnyShapeStyle(Color.red)
                                               : AnyShapeStyle(kind.tint.opacity(0.14))))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(kind.label) \(kind == .usageDrop ? "\(signal.count)%" : AppFormat.count(signal.count)) — 눌러서 보기")
                .accessibilityLabel("\(kind.label) \(signal.count)")
            }
            if let limit, row.signals.count > limit {
                Text("+\(row.signals.count - limit)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 숫자 · 증감, 그 아래 30일 선.
    @ViewBuilder
    private func number(_ metric: Metric?, placeholder: String, tint: Color) -> some View {
        if let metric {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AppFormat.count(metric.current))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    HomeDelta(current: metric.current, previous: metric.previous)
                        .font(.body.monospacedDigit())
                }
                .lineLimit(1)
                Sparkline(points: metric.points, tint: tint)
                    .frame(height: 30)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(placeholder)
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 마우스를 올린 카드가 살짝 뜬다. 올린 상태를 카드마다 따로 쥔다 — 홈이 쥐면 마우스가
/// 카드를 지날 때마다 마흔 장의 숫자와 선을 전부 다시 셈한다.
private struct HoverLift: ViewModifier {
    let isOff: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(isHovered ? 0.05 : 0)).allowsHitTesting(false))
            .scaleEffect(isHovered && !isOff ? 1.02 : 1)
            .animation(isOff ? nil : .snappy(duration: 0.18), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// 지난주와 견준 증감 — "▲12%". 지난주가 열 미만이면 비율이 숫자를 부풀리므로("1 → 2 = 100%")
/// 몇 늘고 줄었는지 그대로 적는다.
struct HomeDelta: View {
    let current: Int
    let previous: Int

    var body: some View {
        let delta = current - previous
        Text(text(delta))
            .foregroundStyle(DeltaPolarity.higherIsBetter.tint(for: delta))
            .accessibilityLabel("지난주 대비 \(text(delta))")
    }

    private func text(_ delta: Int) -> String {
        guard delta != 0 else { return "–" }
        let arrow = delta > 0 ? "▲" : "▼"
        guard previous >= 10 else { return "\(arrow)\(AppFormat.count(abs(delta)))" }
        let percent = (Double(abs(delta)) / Double(previous) * 100).rounded()
        return percent >= 1000 ? "\(arrow)\(Int(percent / 100))배" : "\(arrow)\(Int(percent))%"
    }
}

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
    /// 홈의 두 얼굴 — 지금 무슨 일이 났나(`now`) · 어느 앱에 시간을 더 들일까(`potential`).
    @AppStorage("home-mode") private var modeRaw = HomeMode.now.rawValue
    @State private var filter: Filter = .all
    @State private var query = ""
    /// "지금 급한 것" 을 끝까지 펼쳤나.
    @State private var showsAllUrgent = false
    @State private var showsAllVoices = false
    /// 첫 화면에서 연 리뷰 · 피드백 — 한 번 본 것은 다시 펴지 않는다. 줄마다 하나, 최근 500개만 둔다.
    @AppStorage("home-voices-seen") private var seenVoicesRaw = ""
    /// 가린 급한 것 · 좋은 소식 — "앱|종류|가릴 때의 수|가린 때" 를 줄마다. 언제 다시 서는지는 `isDismissed`.
    @AppStorage("home-dismissed-signals") private var dismissedRaw = ""
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
            case news, changed, keyword, oldCrash
            /// 좋은 소식 — 손볼 일이 아니라 자라는 것. 차례(임팩트)에는 무게가 없다.
            case usageUp, purchase
            var id: Int { rawValue }

            /// 급한 것 · 사람이 기다리는 것 · 알아만 둘 것 · 좋은 소식.
            enum Tier { case critical, voice, chore, good }

            var tier: Tier {
                switch self {
                case .crash, .release, .usageDrop: return .critical
                case .hang, .feedback, .newReview, .storeIssue, .unansweredReview: return .voice
                case .news, .changed, .keyword, .oldCrash: return .chore
                case .usageUp, .purchase: return .good
                }
            }

            var label: String {
                switch self {
                case .crash: return "크래시"
                case .release: return "릴리즈 빨강"
                case .usageDrop: return "사용 급감"
                case .hang: return "멈춤 · 디스크"
                case .feedback: return "볼 피드백"
                case .newReview: return "볼 리뷰"
                case .storeIssue: return "스토어 문제"
                case .unansweredReview: return "답할 리뷰"
                case .news: return "새 소식"
                case .changed: return "본 뒤 바뀐 것"
                case .keyword: return "키워드 다시 짤 때"
                case .oldCrash: return "옛 버전 크래시"
                case .usageUp: return "사용 늘어남"
                case .purchase: return "이번 주 구매"
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
                case .oldCrash: return "clock.arrow.circlepath"
                case .usageUp: return "chart.line.uptrend.xyaxis"
                case .purchase: return "cart.fill"
                }
            }

            var tint: Color {
                switch tier {
                case .critical: return .red
                case .voice: return .orange
                case .chore: return .secondary
                case .good: return .green
                }
            }

            /// 누르면 갈 칸.
            var section: FeedbackStore.ProjectSection {
                switch self {
                case .crash, .hang, .oldCrash: return .crashes
                case .release: return .release
                case .usageDrop: return .stats
                case .feedback: return .feedback
                case .newReview, .unansweredReview: return .reviews
                case .storeIssue: return .storeAnalytics
                case .news: return .news
                case .changed: return .stats
                case .keyword: return .keywords
                case .usageUp, .purchase: return .stats
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
                case .news, .changed, .keyword, .oldCrash: return (0.5, 1)
                case .usageUp, .purchase: return (0, 0)
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
        /// 종류마다 가장 최근 일이 난 때. 사용 추이처럼 기간으로 보는 것 · 모르는 것은 없다.
        var latest: [Signal.Kind: Date] = [:]
        var id: String { project }

        /// 급한 것(크래시 · 릴리즈 빨강 · 사용 급감)이 있나.
        var isCritical: Bool { signals.contains { $0.kind.tier == .critical } }
        func has(_ kind: Signal.Kind) -> Bool { signals.contains { $0.kind == kind } }
        /// 좋은 소식과 손볼 것을 따로 — 카드에 다른 줄로 선다.
        var good: [Signal] { signals.filter { $0.kind.tier == .good } }
        var issues: [Signal] { signals.filter { $0.kind.tier != .good } }

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
                Picker("보기", selection: $modeRaw) {
                    ForEach(HomeMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)

                if modeRaw == HomeMode.potential.rawValue {
                    PotentialBoard()
                } else {
                summary(all)
                urgent(all)
                growing(all)
                dismissedNotice(all)
                voices(all)
                controls(all)
                if shown.isEmpty {
                    Text(all.isEmpty ? "아직 앱이 없습니다. 새로고침하면 앱이 보낸 기록으로 채워집니다." : "여기에 맞는 앱이 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 440), spacing: 14)], spacing: 14) {
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
            }
            // 급한 것 · 좋은 소식 칸이 통째로 생기거나 사라질 때도 부드럽게.
            .animation(listAnimation, value: Self.signalFingerprint(all))
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
            // 다만 **지금 버전에서 난 것만** 급하다. 보고는 하루 넘게 늦게 오고, 그사이 업데이트한
            // 기기의 옛 크래시가 새 버전 이름표를 달고 온다(`RecentDiagnostics`). 이미 고친 옛 버전의
            // 크래시를 급한 것으로 세면 앱마다 빨강이 서서 정말 급한 것을 가린다.
            let recent = RecentDiagnostics(project: project, store: store, since: weekAgo)
            if !recent.crashes.isEmpty { counts[.crash] = recent.crashes.count }
            if !recent.hangs.isEmpty { counts[.hang] = recent.hangs.count }
            if !recent.old.isEmpty { counts[.oldCrash] = recent.old.count }
            if store.releaseLevel(for: project) == .red { counts[.release] = 1 }
            // 지난주에 스무 명은 넘게 쓰던 앱이 3할 넘게 줄었으면 급한 일이다.
            if let activity, activity.previous >= 20, activity.delta < 0,
               Double(-activity.delta) / Double(activity.previous) >= 0.3 {
                counts[.usageDrop] = Int((Double(-activity.delta) / Double(activity.previous) * 100).rounded())
            }

            // 좋은 소식 — 줄어든 것만 보이면 무엇이 잘되는지 놓친다.
            let downloads = downloads(project, store: store, keywords: keywords, purchases: purchases)
            if let trend = activity ?? downloads, trend.previous >= 5, trend.delta >= 3,
               Double(trend.delta) / Double(trend.previous) >= 0.2 {
                counts[.usageUp] = Int((Double(trend.delta) / Double(trend.previous) * 100).rounded())
            }
            let days = store.days(for: project, audience: .all)
            let bought = UsageRollups.recentDayKeys(7).reduce(0) { sum, day in
                sum + (days[day.key]?.byEvent ?? [:]).reduce(0) { inner, event in
                    inner + (event.key.split(separator: ":").first == "purchase_completed" ? event.value : 0)
                }
            }
            if bought > 0 { counts[.purchase] = bought }
            var latest: [Signal.Kind: Date] = [:]
            latest[.crash] = recent.crashes.compactMap(\.happenedAt).max()
            latest[.hang] = recent.hangs.compactMap(\.happenedAt).max()
            latest[.oldCrash] = recent.old.compactMap(\.happenedAt).max()
            // 릴리즈 빨강은 지금 버전의 가장 최근 사고로 날짜를 단다.
            latest[.release] = (recent.crashes + recent.hangs).compactMap(\.happenedAt).max()
            latest[.purchase] = UsageRollups.recentDayKeys(7).last { day in
                (days[day.key]?.byEvent ?? [:]).contains { $0.key.split(separator: ":").first == "purchase_completed" && $0.value > 0 }
            }?.date

            // 나머지는 칸의 뱃지 그대로 — 읽으면 지워진다.
            if let badge = metrics.itemBadge(.feedback, project: project) { counts[.feedback] = badge.count }
            // 리뷰는 둘 다 따로 — 새로 온 것(볼 리뷰)과 답해야 할 것(답할 리뷰). 새 리뷰가 있다고
            // 답할 리뷰가 가려지면 답장할 일이 카드에서 사라진다.
            if let badge = metrics.itemBadge(.reviews, project: project), badge.name == "새 리뷰" {
                counts[.newReview] = badge.count
            }
            let unanswered = purchases.unansweredReviews(for: project)
            if unanswered > 0 { counts[.unansweredReview] = unanswered }
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
                       downloads: downloads,
                       signals: Signal.Kind.allCases.compactMap { kind in
                           counts[kind].map { Signal(kind: kind, count: $0) }
                       },
                       latest: latest)
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
            let growing = rows.filter { !$0.good.isEmpty }
            figure("좋은 소식", value: growing.isEmpty ? "없음" : "\(growing.count)개 앱") {
                let kinds = Signal.Kind.allCases.filter { $0.tier == .good }.compactMap { kind -> String? in
                    let apps = rows.filter { $0.has(kind) }.count
                    return apps > 0 ? "\(kind.label) \(apps)" : nil
                }
                Text(kinds.isEmpty ? "이번 주는 아직" : kinds.joined(separator: " · "))
                    .foregroundStyle(growing.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
            }
            figure("급한 앱", value: critical.isEmpty ? "없음" : "\(critical.count)개") {
                Text(critical.isEmpty ? "크래시 · 릴리즈 빨강 · 사용 급감 없음" : criticalKinds.joined(separator: " · "))
                    .foregroundStyle(critical.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
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

    // MARK: - 언제

    /// 급한 것 · 좋은 소식에 세우는 것은 이 안에 일어난 것만 — 지난주 크래시 · 구매는 이미 지난 소식이다.
    static let freshWindow: TimeInterval = 3 * 86_400

    /// 가장 최근 일이 `freshWindow` 안인가. 날짜가 없는 것(사용 추이 · 날짜 모르는 릴리즈 판정)은 지금 상태라 남긴다.
    static func isFresh(_ signal: Signal, row: Row, now: Date = Date()) -> Bool {
        guard let date = row.latest[signal.kind] else { return true }
        return now.timeIntervalSince(date) <= freshWindow
    }

    /// 줄 끝에 적을 때 — "3시간 전" · "어제", 사용 추이는 "지난 7일".
    static func whenText(_ signal: Signal, row: Row) -> String? {
        if let date = row.latest[signal.kind] {
            if signal.kind == .purchase {
                // 구매는 날짜 단위로만 안다.
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                           to: Calendar.current.startOfDay(for: Date())).day ?? 0
                return days == 0 ? "오늘" : days == 1 ? "어제" : "\(days)일 전"
            }
            return date.formatted(.relative(presentation: .named).locale(AppFormat.locale))
        }
        switch signal.kind {
        case .usageUp, .usageDrop: return "지난 7일"
        default: return nil
        }
    }

    // MARK: - 가리기

    /// 사용 추이(%)는 날마다 조금씩 흔들린다 — 가린 뒤 이만큼(%p) 더 움직여야 새 일로 본다.
    private static let trendStep = 10

    /// 가린 기록 하나 — 그때의 수와 가린 때.
    private struct Dismissal: Equatable {
        var count: Int
        var at: Date
    }

    /// 가린 기록은 이만큼 지나면 버린다 — 그사이 다시 선 적이 없으면 다시 볼 일도 없다.
    private static let dismissalLifetime: TimeInterval = 60 * 86_400

    private var dismissed: [String: Dismissal] {
        var map: [String: Dismissal] = [:]
        for line in dismissedRaw.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3, let count = Int(parts[2]) else { continue }
            // 예전 기록(수만 있던 것)은 지금 가린 것으로 읽는다 — 다시 튀어나오지 않게.
            let at = parts.count > 3 ? Double(parts[3]).map(Date.init(timeIntervalSince1970:)) ?? Date() : Date()
            map["\(parts[0])|\(parts[1])"] = Dismissal(count: count, at: at)
        }
        return map
    }

    private func saveDismissed(_ map: [String: Dismissal]) {
        let cutoff = Date().addingTimeInterval(-Self.dismissalLifetime)
        dismissedRaw = map.filter { $0.value.at >= cutoff }
            .sorted { $0.key < $1.key }.suffix(500)
            .map { "\($0.key)|\($0.value.count)|\(Int($0.value.at.timeIntervalSince1970))" }
            .joined(separator: "\n")
    }

    private static func dismissKey(_ project: String, _ kind: Signal.Kind) -> String {
        "\(project.replacingOccurrences(of: "|", with: "/"))|\(kind.rawValue)"
    }

    /// 가린 뒤 새로 생긴 일이 없으면 가린 채로.
    ///
    /// - 날짜를 아는 것(크래시 · 멈춤 · 릴리즈 · 구매)은 가린 **뒤에** 새로 일어났을 때만 다시 선다.
    ///   수로 따지면 앱을 켤 때마다 데이터가 다 오기 전의 작은 수를 보고 기록이 흔들려, 빌드하고 켤
    ///   때마다 가린 것이 다 되살아났다. 날짜는 데이터가 덜 와도 흔들리지 않는다.
    /// - 날짜가 없는 것은 수가 늘면(사용 추이는 `trendStep` 넘게 움직이면) 다시 선다.
    /// - 좋은 소식은 한 번 가리면 계속 가린다. 되돌리려면 "다시 보기".
    private static func isDismissed(_ signal: Signal, row: Row, in map: [String: Dismissal]) -> Bool {
        guard let stored = map[dismissKey(row.project, signal.kind)] else { return false }
        if signal.kind.tier == .good { return true }
        if let latest = row.latest[signal.kind] { return latest <= stored.at }
        let isTrend = signal.kind == .usageUp || signal.kind == .usageDrop
        return signal.count < stored.count + (isTrend ? trendStep : 1)
    }

    private func dismiss(_ items: [(row: Row, signal: Signal)]) {
        var map = dismissed
        for item in items {
            map[Self.dismissKey(item.row.project, item.signal.kind)] = Dismissal(count: item.signal.count, at: Date())
        }
        withAnimation(listAnimation) { saveDismissed(map) }
    }

    /// 지금 선 표시 전부를 한 줄로 — 바뀌면 목록이 부드럽게 움직인다.
    private static func signalFingerprint(_ rows: [Row]) -> String {
        rows.map { row in row.project + ":" + row.signals.map { "\($0.kind.rawValue)=\($0.count)" }.joined(separator: ",") }
            .joined(separator: ";")
    }

    private func dismissAllButton(_ groups: [SignalGroup]) -> some View {
        Button {
            dismiss(groups.flatMap(\.items))
        } label: {
            Label("모두 읽음", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderless)
        .font(.body)
        .help("읽음으로 — 새로 올라오기 전까지 숨깁니다")
    }

    /// 줄 하나와 그 줄을 가리는 단추.
    private func dismissibleRow(_ row: Row, _ signal: Signal, tint: Color) -> some View {
        HStack(spacing: 0) {
            urgentRow(row, signal, tint: tint)
            Button {
                dismiss([(row: row, signal: signal)])
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("읽음 — 새로 올라오면 다시 보입니다")
            .accessibilityLabel("\(row.name) \(signal.kind.label) 읽음")
            .padding(.trailing, 4)
        }
    }

    /// 가린 것이 있으면 한 줄 — 몇 개인지와 다시 보기.
    @ViewBuilder
    private func dismissedNotice(_ rows: [Row]) -> some View {
        let map = dismissed
        let kinds = Set(Signal.Kind.allCases.filter { $0.tier == .critical } + [.purchase, .usageUp])
        let count = rows.reduce(0) { sum, row in
            sum + row.signals.filter { kinds.contains($0.kind) && Self.isDismissed($0, row: row, in: map) }.count
        }
        if count > 0 {
            HStack(spacing: 8) {
                Label("읽은 것 \(count)개 — 새로 올라오면 다시 보입니다", systemImage: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("다시 보기") { withAnimation(listAnimation) { dismissedRaw = "" } }
                    .buttonStyle(.borderless)
                    .font(.body)
            }
        }
    }

    // MARK: - Urgent

    /// 지금 급한 것 — 모든 앱의 크래시 · 릴리즈 빨강 · 사용 급감을 한 줄씩, 임팩트가 큰 앱부터.
    /// 카드를 훑어 빨간 것을 찾지 않아도 되게, 무슨 일인지(어느 버전 · 최근 사고 · 판정 까닭)를
    /// 그 줄에 적는다. 누르면 그 앱의 그 칸이 바로 열린다. 급한 것이 없으면 자리를 차지하지 않는다.
    /// 종류 하나에 모인 줄들 — 급한 것 · 좋은 소식을 종류마다 따로 묶어 보인다.
    /// 크래시 옆에 사용 급감이, 결제 옆에 사용 늘어남이 섞여 있으면 무슨 일인지 줄마다 다시 읽어야 했다.
    private struct SignalGroup: Identifiable {
        let kind: Signal.Kind
        let items: [(row: Row, signal: Signal)]
        var id: Signal.Kind { kind }
    }

    /// `order` 의 차례로 종류를 세우고, 한 종류 안에서는 가장 최근에 일이 난 앱부터.
    /// 날짜가 같거나 없으면(사용 추이) `rank` 가 큰 앱부터. 빈 종류는 뺀다.
    private func grouped(_ rows: [Row], order: [Signal.Kind],
                         rank: (Row, Signal) -> Double) -> [SignalGroup] {
        let dismissed = dismissed
        return order.compactMap { kind in
            let items = rows.compactMap { row in
                row.signals.first { $0.kind == kind }.map { (row: row, signal: $0) }
            }
            .filter { !Self.isDismissed($0.signal, row: $0.row, in: dismissed) }
            .filter { Self.isFresh($0.signal, row: $0.row) }
            .sorted { a, b in
                let dateA = a.row.latest[kind] ?? .distantPast, dateB = b.row.latest[kind] ?? .distantPast
                return dateA != dateB ? dateA > dateB : rank(a.row, a.signal) > rank(b.row, b.signal)
            }
            return items.isEmpty ? nil : SignalGroup(kind: kind, items: items)
        }
    }

    /// 칸 안의 줄이 바뀌었나 — 앱 · 수가 달라지면 줄이 들고 나며 움직인다.
    private static func motionKey(_ groups: [SignalGroup]) -> [String] {
        groups.flatMap { group in group.items.map { "\(group.kind.rawValue)|\($0.row.project)|\($0.signal.count)" } }
    }

    private var listAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.35) }

    /// 줄이 새로 서면 위에서 내려앉고, 읽음 · 사라짐은 옅어지며 줄어든다.
    private static let rowTransition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .move(edge: .top)),
        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))

    /// 종류 이름 한 줄 — "크래시 · 3개 앱".
    private func groupHeader(_ group: SignalGroup, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.kind.systemImage)
            Text(group.kind.label)
            Text("· \(group.items.count)개 앱")
                .foregroundStyle(.secondary)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func urgent(_ rows: [Row]) -> some View {
        let groups = grouped(rows, order: Signal.Kind.allCases.filter { $0.tier == .critical },
                             rank: { row, _ in row.impact })
        let total = groups.reduce(0) { $0 + $1.items.count }
        if total > 0 {
            // 접어 둔 동안은 종류마다 세 줄까지 — 한 종류가 다른 종류를 밀어내지 않게.
            let perKind = 3
            let hidden = groups.reduce(0) { $0 + max(0, $1.items.count - perKind) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("지금 급한 것 \(total)", systemImage: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    if hidden > 0 {
                        Button(showsAllUrgent ? "접기" : "\(hidden)건 더 보기") { showsAllUrgent.toggle() }
                            .buttonStyle(.borderless)
                            .font(.body)
                    }
                    dismissAllButton(groups)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 10, alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        let shown = showsAllUrgent ? group.items : Array(group.items.prefix(perKind))
                        VStack(alignment: .leading, spacing: 0) {
                            groupHeader(group, tint: .red)
                            ForEach(Array(shown.enumerated()), id: \.element.row.project) { index, item in
                                VStack(spacing: 0) {
                                    if index > 0 { Divider().padding(.leading, 50) }
                                    dismissibleRow(item.row, item.signal, tint: .red)
                                }
                                .transition(Self.rowTransition)
                            }
                        }
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.35), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
            .transition(.opacity)
            .animation(listAnimation, value: Self.motionKey(groups))
            .animation(listAnimation, value: showsAllUrgent)
        }
    }

    /// 좋은 소식 — 이번 주 구매 · 사용 늘어남 · 별 5개를 종류마다 따로. 급한 것 바로 아래에
    /// 초록으로 — 줄어든 숫자만 보이는 날에도 무엇이 자라는지 같은 자리에서 보인다.
    /// 돈이 들어온 것을 맨 앞에 둔다.
    @ViewBuilder
    private func growing(_ rows: [Row]) -> some View {
        let groups = grouped(rows, order: [.purchase, .usageUp],
                             rank: { row, signal in
                                 // 구매 · 별은 건수, 사용 늘어남은 쓰는 사람 수가 큰 앱부터.
                                 signal.kind == .usageUp ? Double(row.reach) : Double(signal.count) * 1_000_000 + Double(row.reach)
                             })
        let total = groups.reduce(0) { $0 + $1.items.count }
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("좋은 소식 \(total)", systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    dismissAllButton(groups)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 10, alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            groupHeader(group, tint: .green)
                            ForEach(Array(group.items.enumerated()), id: \.element.row.project) { index, item in
                                VStack(spacing: 0) {
                                    if index > 0 { Divider().padding(.leading, 50) }
                                    dismissibleRow(item.row, item.signal, tint: .green)
                                }
                                .transition(Self.rowTransition)
                            }
                        }
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.green.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.3), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
            .transition(.opacity)
            .animation(listAnimation, value: Self.motionKey(groups))
        }
    }

    /// 사람이 직접 남긴 말 — 스토어 리뷰와 앱 안 피드백. 숫자 뱃지만으로는 무슨 말인지 모르니
    /// 48시간 안의 것을 글 그대로 첫 화면에 펴 둔다. 누르면 그 앱의 리뷰 · 피드백 칸이 열리고,
    /// 한 번 연 것, 답을 단 리뷰, 반영했거나 답장한 피드백은 다시 펴지 않는다.
    private struct Voice: Identifiable {
        let id: String
        let row: Row
        let date: Date
        let isReview: Bool
        let label: String
        let text: String
        let rating: Int?
        /// 한 문장 의견이면 그 사람이 받은 질문 — 답만으로는 뜻이 서지 않는다.
        var question: String? = nil
    }

    private func recentVoices(_ rows: [Row]) -> [Voice] {
        let since = Date().addingTimeInterval(-48 * 3600)
        let seen = seenVoices
        var items: [Voice] = []
        for row in rows {
            // 답을 단 리뷰 · 반영했거나 답장한 피드백은 이미 손댄 것이라 다시 펴지 않는다.
            for review in purchases.reviewFeeds[row.project]?.reviews ?? []
            where review.createdDate >= since && review.response == nil {
                let words = [review.title, review.body].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                items.append(Voice(id: "r-" + review.id, row: row, date: review.createdDate, isReview: true,
                                   label: "리뷰 · \(review.territory)",
                                   text: words, rating: review.rating))
            }
            for item in store.feedback(for: row.project) {
                guard let date = item.createdAt, date >= since,
                      !store.status(of: item).isHandled, !store.isReplied(item) else { continue }
                let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                items.append(Voice(id: "f-" + item.id, row: row, date: date, isReview: false,
                                   label: item.isVoice ? (item.usefulnessLabel.map { "한 문장 의견 · \($0)" } ?? "한 문장 의견")
                                                       : item.typeLabel.map { "피드백 · \($0)" } ?? "피드백",
                                   text: text, rating: item.rating, question: item.voiceQuestion))
            }
        }
        return items.filter { !seen.contains($0.id) }.sorted { $0.date > $1.date }
    }

    private var seenVoices: Set<String> {
        Set(seenVoicesRaw.split(separator: "\n").map(String.init))
    }

    private func markSeen(_ ids: [String]) {
        var list = seenVoicesRaw.split(separator: "\n").map(String.init)
        list.append(contentsOf: ids.filter { !list.contains($0) })
        seenVoicesRaw = list.suffix(500).joined(separator: "\n")
    }

    @ViewBuilder
    private func voices(_ rows: [Row]) -> some View {
        let items = recentVoices(rows)
        if !items.isEmpty {
            let limit = 6
            let shown = showsAllVoices ? Array(items.prefix(30)) : Array(items.prefix(limit))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("48시간 안의 리뷰 · 피드백 \(items.count)", systemImage: "text.bubble.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    // 애니메이션 없이 지운다 — 그리드가 크기를 바꾸는 중의 애니메이션은 AttributeGraph 를 죽일 수 있다.
                    Button("모두 봤어요") { markSeen(items.map(\.id)) }
                        .buttonStyle(.borderless)
                        .font(.body)
                    if items.count > limit {
                        Button(showsAllVoices ? "접기" : "\(min(items.count, 30) - limit)건 더 보기") { showsAllVoices.toggle() }
                            .buttonStyle(.borderless)
                            .font(.body)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                    ForEach(shown) { voiceCard($0) }
                }
            }
        }
    }

    private func voiceCard(_ voice: Voice) -> some View {
        Button {
            markSeen([voice.id])
            store.open(project: voice.row.project, section: voice.isReview ? .reviews : .feedback)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AppIcon(url: icons.url(for: voice.row.project, keywords: keywords), size: 24)
                    Text(voice.row.name)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(voice.date, format: .relative(presentation: .named).locale(AppFormat.locale))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    if let rating = voice.rating, (1...5).contains(rating) {
                        Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                            .foregroundStyle(rating >= 4 ? .orange : (rating <= 2 ? .red : .secondary))
                            .accessibilityLabel("별 \(rating)개")
                    }
                    Text(voice.label)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                if let question = voice.question {
                    VoiceQuestionLine(question: question, font: .callout)
                }
                Text(voice.text)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill((voice.question == nil ? Color.blue : .voice).opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder((voice.question == nil ? Color.blue : .voice).opacity(0.25), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func urgentRow(_ row: Row, _ signal: Signal, tint: Color = .red) -> some View {
        let kind = signal.kind
        let lines = SignalEvidence.lines(signal, row: row, store: store, purchases: purchases)
        return Button {
            store.open(project: row.project, section: kind.section)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    // 앱 이름과 무슨 일인지는 잘리지 않게 이어 쓰고(좁으면 다음 줄로), 쓰는 사람은 그 아래 따로.
                    Text("\(Text(row.name))   \(Text("\(Image(systemName: kind.systemImage)) \(Self.chipText(signal, named: true))").foregroundStyle(tint))")
                        .font(.body.weight(.semibold))
                    if row.reach > 0 {
                        Text("쓰는 사람 \(AppFormat.count(row.reach))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // 세부 내용은 두 줄까지 — 넘치면 … 으로 줄인다.
                    if !lines.isEmpty {
                        Text(lines.joined(separator: "  ·  "))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let when = Self.whenText(signal, row: row) {
                    Text(when)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 44)
                Text(row.name)
                    .font(.title3.weight(.semibold))
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
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            }

            goodRow(row)
            signalRow(row)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(row.isCritical ? AnyShapeStyle(.red.opacity(0.5))
                          : row.good.isEmpty ? AnyShapeStyle(.clear) : AnyShapeStyle(.green.opacity(0.45)), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// 카드 맨 아래 — 종류마다 따로 선 표시. 급한 것 · 목소리는 이름까지, 알아만 둘 것은 기호와
    /// 수만. 자리가 모자라면 전부 기호와 수로 줄인다. 누르면 그 칸으로 바로 간다.
    /// 좋은 소식 줄 — 늘 이름까지 적은 초록 뱃지. 없으면 자리를 차지하지 않는다.
    @ViewBuilder
    private func goodRow(_ row: Row) -> some View {
        if !row.good.isEmpty {
            ViewThatFits(in: .horizontal) {
                chips(row.good, project: row.project, compact: false)
                chips(row.good, project: row.project, compact: true)
            }
            .frame(height: 28, alignment: .leading)
        }
    }

    @ViewBuilder
    private func signalRow(_ row: Row) -> some View {
        if row.issues.isEmpty {
            Text("볼 것 없음")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(height: 26, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                chips(row.issues, project: row.project, compact: false)
                chips(row.issues, project: row.project, compact: true)
                chips(row.issues, project: row.project, compact: true, limit: 5)
            }
            .frame(height: 28, alignment: .leading)
        }
    }

    /// 뱃지의 수 — 사용 변화는 비율, 나머지는 건수.
    static func chipText(_ signal: Signal, named: Bool) -> String {
        let value: String
        switch signal.kind {
        case .usageDrop: value = "▼\(signal.count)%"
        case .usageUp: value = "▲\(signal.count)%"
        default: value = AppFormat.count(signal.count) + (named ? "건" : "")
        }
        return named ? "\(signal.kind.label) \(value)" : value
    }

    private func chips(_ signals: [Signal], project: String, compact: Bool, limit: Int? = nil) -> some View {
        let shown = limit.map { Array(signals.prefix($0)) } ?? signals
        return HStack(spacing: 6) {
            ForEach(shown) { signal in
                let kind = signal.kind
                let named = !compact && kind.tier != .chore
                let filled = kind.tier == .critical || kind.tier == .good
                Button {
                    store.open(project: project, section: kind.section)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: kind.systemImage)
                        Text(Self.chipText(signal, named: named))
                            .monospacedDigit()
                    }
                    .font(.body.weight(filled ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(kind.tint))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(filled ? AnyShapeStyle(kind.tint) : AnyShapeStyle(kind.tint.opacity(0.14))))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(Self.chipText(signal, named: true)) — 눌러서 보기")
                .accessibilityLabel(Self.chipText(signal, named: true))
            }
            if let limit, signals.count > limit {
                Text("+\(signals.count - limit)")
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AppFormat.count(metric.current))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    HomeDelta(current: metric.current, previous: metric.previous)
                        .font(.body.monospacedDigit())
                }
                .fixedSize()
                Sparkline(points: metric.points, tint: tint)
                    .frame(height: 44)
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

/// 최근에 도착한 진단을 **난 버전**으로 가른 것 — 지금 버전의 크래시 · 멈춤과, 옛 버전의 것.
///
/// 진단의 `appVersion` 은 배달될 때 깔려 있던 버전이라 죽은 버전이 아닐 수 있다. 죽은 빌드는
/// `buildNumber` 가 가리키고, 같은 빌드의 보고들이 가장 많이 적은 버전이 그 빌드의 버전이다
/// (`ReleaseHealth.versionResolver`). 지금 버전은 사용 이벤트로 본 최신 버전(릴리즈 판정과 같은 값),
/// 없으면 진단들 가운데 가장 새 버전이다.
struct RecentDiagnostics {
    var crashes: [CrashReport] = []
    var hangs: [CrashReport] = []
    /// 지금 버전보다 옛 버전에서 난 것(크래시 · 멈춤 모두).
    var old: [CrashReport] = []
    /// 난 버전을 돌려주는 함수.
    let version: (CrashReport) -> String
    let currentVersion: String?

    @MainActor
    init(project: String, store: FeedbackStore, since: Date) {
        let all = store.crashes(for: project)
        let resolve = ReleaseHealth.versionResolver(for: all)
        version = resolve
        let known = all.map(resolve).filter(ReleaseHealth.isRealVersion)
        let current = store.releaseHealth(for: project)?.latest.version
            ?? known.max { ReleaseHealth.isOlder($0, than: $1) }
        currentVersion = current
        for report in all where (report.receivedAt ?? .distantPast) >= since {
            let reported = resolve(report)
            // 버전을 못 읽는 보고는 지금 것으로 본다 — 모르는 것을 옛것으로 치우지 않는다.
            if let current, ReleaseHealth.isRealVersion(reported), ReleaseHealth.isOlder(reported, than: current) {
                old.append(report)
            } else if report.kind == "crash" {
                crashes.append(report)
            } else {
                hangs.append(report)
            }
        }
    }
}

/// 홈에서 무엇을 볼까.
enum HomeMode: String, CaseIterable, Identifiable {
    /// 급한 것 · 바뀐 것 · 앱마다의 지금.
    case now = "지금"
    /// 깔때기를 업계 평균과 견줘 어느 앱에 시간을 더 들일지(`PotentialBoard`).
    case potential = "잠재력"
    var id: String { rawValue }
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

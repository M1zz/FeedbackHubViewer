//
//  SectionMetrics.swift
//  FeedbackHubViewer
//
//  기능 하나가 앱 하나(nil 이면 전체 앱)에 대해 말하는 숫자. 기능 목록 · 그 기능의 앱 목록 ·
//  기능 화면의 부제가 모두 여기서 읽는다 — 세 자리가 같은 사실을 따로 세면 언젠가 어긋난다.
//
//  뷰가 아니라 값이다. 각 뷰가 `@EnvironmentObject` 로 가게들을 지켜보고 있다가 몸통에서
//  이것을 만들어 쓰므로, 바뀌면 그 뷰가 다시 그려진다.
//

import SwiftUI

@MainActor
struct SectionMetrics {
    let store: FeedbackStore
    let keywords: KeywordStore
    let purchases: AppStoreConnectStore
    let design: DesignDocsStore
    let charts: ChartStore
    let news: NewsStore

    /// 기능 이름 옆에 붙는 "손볼 것" 표시 하나. 숫자 칸과 같은 활자로 적으면 읽을 것과
    /// 구경할 것이 같은 무게로 보여서 따로 뱃지로 뺀다.
    struct Badge {
        let count: Int
        let systemImage: String
        let tint: Color
        let name: String
    }

    // MARK: - Badge

    /// 우선순위: 안 읽은 피드백 → 새 진단 → 새 리뷰 → 답 안 한 리뷰.
    /// 설정 → 알림에서 끈 종류는 뱃지를 달지 않는다(기본: 진단은 안 단다).
    func badge(_ section: FeedbackStore.ProjectSection, project: String?) -> Badge? {
        switch section {
        case .inbox:
            let count = inboxCount
            return count > 0 ? Badge(count: count, systemImage: "tray.full.fill", tint: .orange, name: "남은 일") : nil
        case .news:
            let count = news.unreadCount(for: project)
            return count > 0 ? Badge(count: count, systemImage: "newspaper.fill", tint: .purple, name: "새 소식") : nil
        case .feedback:
            guard store.showsBadge(.feedback) else { return nil }
            let unread = store.unreadCount(for: project)
            return unread > 0 ? Badge(count: unread, systemImage: "envelope.badge.fill", tint: .red, name: "안 읽은 피드백") : nil
        case .crashes:
            guard store.showsBadge(.crash) else { return nil }
            let fresh = store.newCrashCount(for: project)
            return fresh > 0 ? Badge(count: fresh, systemImage: "exclamationmark.triangle.fill", tint: .red, name: "새 진단") : nil
        case .reviews:
            // 새 리뷰가 답 안 한 리뷰보다 먼저 — 새것을 봐야 답할 것도 안다.
            let fresh = store.showsBadge(.review) ? purchases.newReviewCount(for: project) : 0
            if fresh > 0 {
                return Badge(count: fresh, systemImage: "star.bubble.fill", tint: .red, name: "새 리뷰")
            }
            let unanswered = unansweredReviews(project)
            return unanswered > 0 ? Badge(count: unanswered, systemImage: "bubble.left.fill", tint: .orange, name: "답 안 한 리뷰") : nil
        case .release:
            let red = releaseRedCount(project)
            // 한 앱이면 빨강이라는 사실은 점이 말한다. 뱃지는 전체에서 "몇 개가 빨강" 일 때만.
            guard project == nil, red > 0 else { return nil }
            return Badge(count: red, systemImage: "stethoscope", tint: .red, name: "빨강인 앱")
        default:
            return nil
        }
    }

    // MARK: - Count

    func count(_ section: FeedbackStore.ProjectSection, project: String?) -> Int {
        switch section {
        case .inbox: return inboxCount
        case .news: return news.items.filter { project == nil || $0.project == project }.count
        case .feedback: return store.feedback(for: project).count
        case .stats: return store.usage(for: project).installs
        // 빨강인 앱 수. 한 앱이면 0 아니면 1.
        case .release: return releaseRedCount(project)
        case .acquisition:
            guard let project else { return AcquisitionCatalog.all.count }
            return AcquisitionCatalog.map(for: project)?.activeChannels.count ?? 0
        case .crashes: return store.crashSummary(for: project).total
        case .keywords: return keywords.standings(for: project).filter(\.isRanked).count
        case .charts:
            // 한 앱이면 차트에 든 나라 수, 전체면 어디든 차트에 든 앱 수.
            guard let project else {
                return store.projectCounts.filter { entry in
                    keywords.trackId(for: entry.key).map { !charts.history.current(for: $0).isEmpty } ?? false
                }.count
            }
            return keywords.trackId(for: project).map(charts.history.countriesRanked(for:)) ?? 0
        case .purchases: return project.flatMap { purchases.products(for: $0)?.count } ?? 0
        case .reviews: return reviewCount(project)
        case .design: return design.docs(for: project).count
        case .storeAnalytics:
            guard let project else { return purchases.analyticsCoverage?.value?.missing.count ?? 0 }
            guard case .ready(let analytics)? = purchases.storeAnalytics[project]?.value else { return 0 }
            return analytics.insights?.findings.filter { $0.level == .bad }.count ?? 0
        }
    }

    /// 숫자를 말로 — "3건", "설치 120대", "빨강 없음". 맨 숫자는 무엇을 센 것인지 모른다.
    func label(_ section: FeedbackStore.ProjectSection, project: String?) -> String {
        let count = count(section, project: project)
        switch section {
        case .inbox:
            return count > 0 ? "\(AppFormat.count(count))건" : "없음"
        case .news:
            return count > 0 ? "\(AppFormat.count(count))건" : "아직 없음"
        case .feedback:
            // 안 읽은 수는 뱃지가 말한다 — 여기서 또 적으면 같은 사실이 한 줄에 두 번 있다.
            return "\(count)건"
        case .stats:
            return count > 0 ? "설치 \(AppFormat.count(count))대" : "사용 통계 없음"
        case .release:
            guard let project else {
                return count > 0 ? "빨강 \(count)개" : "빨강 없음"
            }
            return store.releaseLevel(for: project)?.label ?? "판정 없음"
        case .acquisition:
            guard project != nil else { return count > 0 ? "지도 \(count)개" : "지도 없음" }
            return count > 0 ? "길 \(count)개" : "지도 없음"
        case .crashes:
            guard count > 0 else { return "없음" }
            let recent = store.crashSummary(for: project).last7Days
            return recent > 0 ? "\(count)건 · 7일 \(recent)건" : "\(count)건"
        case .keywords:
            let tracked = keywords.standings(for: project).count
            guard tracked > 0 else { return "추적 안 함" }
            // 전체에는 순위를 읽을 앱이 하나가 아니라, "잡힘" 비율이 아무 뜻 없는 0이 된다.
            guard project != nil else { return "\(tracked)개 추적" }
            return "\(count)/\(tracked) 잡힘"
        case .charts:
            guard charts.history.lastScan != nil else { return "확인 전" }
            guard let project else { return count > 0 ? "앱 \(count)개 차트인" : "차트 밖" }
            guard let trackId = keywords.trackId(for: project) else { return "스토어에 없음" }
            let byCountry = charts.history.bestByCountry(for: trackId)
            guard !byCountry.isEmpty else { return "100위 밖" }
            return ChartStorefronts.summary(byCountry)
        case .purchases:
            guard purchases.isConfigured else { return "연결 안 됨" }
            guard project != nil else { return "판매 순위" }
            return count > 0 ? "상품 \(count)개" : "상품 없음"
        case .reviews:
            guard purchases.isConfigured else { return "연결 안 됨" }
            return count > 0 ? "\(AppFormat.count(count))건" : "리뷰 없음"
        case .storeAnalytics:
            guard purchases.isConfigured else { return "연결 안 됨" }
            guard let project else {
                guard let coverage = purchases.analyticsCoverage?.value else { return "요청 현황" }
                return "요청 \(coverage.apps.count - coverage.missing.count)/\(coverage.apps.count)"
            }
            guard case .ready? = purchases.storeAnalytics[project]?.value else { return "리포트 없음" }
            return count > 0 ? "문제 \(count)개" : "문제 없음"
        case .design:
            let blueprint = project.map { DesignBlueprints.source(for: $0, design: design) != nil ? "설계도 있음" : "설계도 없음" }
                ?? "설계도 \(DesignBlueprints.webURLs.count)개"
            guard DesignDocsStore.isSupported, design.workspace != nil, count > 0 else { return blueprint }
            return "\(blueprint) · 문서 \(count)장"
        }
    }

    /// 이 줄이 경고인가 — 앱 목록에서 그 줄의 글자를 붉게 칠한다.
    func isAlarming(_ section: FeedbackStore.ProjectSection, project: String?) -> Bool {
        switch section {
        case .crashes: return store.crashSummary(for: project).last7Days > 0
        case .release: return project.map { store.releaseLevel(for: $0) == .red } ?? false
        case .storeAnalytics: return project != nil && count(section, project: project) > 0
        default: return false
        }
    }

    // MARK: - Subtitle

    /// 기능 화면의 부제 — 열어 놓은 화면이 무엇을 말하는지 한 줄로.
    func subtitle(_ section: FeedbackStore.ProjectSection, project: String?) -> String {
        switch section {
        case .inbox:
            let count = inboxCount
            return count > 0 ? "모든 앱에서 남은 일 \(AppFormat.count(count))건" : "남은 일 없음"
        case .news:
            let fresh = news.unreadCount
            return fresh > 0 ? "새 소식 \(AppFormat.count(fresh))건" : "차트 · 링크 · 기사 · 출시 · 이정표"
        case .feedback:
            let shown = store.filteredFeedback.count
            let total = store.scopedFeedback.count
            var text = shown == total ? "피드백 \(total)건" : "\(shown)건 표시 / 전체 \(total)건"
            // 남은 일이 몇 건인지가 이 화면의 요점이다 — 다 끝냈다는 사실도.
            if store.scopedPendingCount > 0 {
                text += " · 확인 필요 \(store.scopedPendingCount)건"
            } else if total > 0 {
                text += " · 모두 처리 완료"
            }
            return text
        case .stats:
            let usage = store.usage(for: project)
            guard usage.hasUsageData else {
                return "사용 통계 없음 · 피드백 \(store.feedback(for: project).count)건"
            }
            // 절대값 하나로는 열어 볼 이유가 안 된다. 설치 수는 규모라 그대로
            // 두고, 움직이는 두 값(사람·건수)은 지난주와 견준 결과를 붙인다.
            var text = "설치 \(AppFormat.count(usage.installs))대"
            text += " · 7일 사용자 \(usage.activeInstalls7)명\(Self.change(usage.activeInstalls7, usage.previousActiveInstalls7))"
            text += " · 7일 사용 \(AppFormat.count(usage.events7))건\(Self.change(usage.events7, usage.previousEvents7))"
            return text
        case .release:
            guard let project else {
                let levels = store.projectCounts.compactMap { store.releaseLevel(for: $0.key) }
                guard !levels.isEmpty else { return "판정할 수 있는 앱 없음" }
                let red = levels.filter { $0 == .red }.count
                let yellow = levels.filter { $0 == .yellow }.count
                return "앱 \(levels.count)개 판정 · 빨강 \(red) · 노랑 \(yellow)"
            }
            guard let report = store.releaseHealth(for: project) else {
                return "최근 \(ReleaseHealth.windowDays)일에 버전을 가를 사용 이벤트 없음"
            }
            var text = "최신 \(report.latest.version)"
            if let previous = report.previous { text += " · 앞 버전 \(previous.version)" }
            return text + " · \(report.verdict.level.label)"
        case .acquisition:
            guard let project else { return "앱마다 어디서 새는지" }
            guard let map = AcquisitionCatalog.map(for: project) else { return "유입 지도 없음" }
            return "쓰는 길 \(map.activeChannels.count)개" + (map.asOf.map { " · 지도 \($0) 기준" } ?? "")
        case .crashes:
            let summary = store.crashSummary(for: project)
            guard !summary.isEmpty else { return "올라온 진단 없음" }
            return "전체 \(summary.total)건 · 최근 7일 \(summary.last7Days)건"
        case .keywords:
            let standings = keywords.standings(for: project)
            guard !standings.isEmpty else { return "추적 중인 키워드 없음" }
            guard project != nil else { return "키워드 \(standings.count)개 추적 중 · 앱을 골라 순위를 봅니다" }
            let ranked = standings.filter(\.isRanked)
            let best = ranked.compactMap(\.rank).min()
            var text = "키워드 \(standings.count)개 · \(ranked.count)개 잡힘"
            if let best { text += " · 최고 \(best)위" }
            return text
        case .charts:
            guard let scan = charts.history.lastScan else { return "국가별 App Store 인기 차트 상위 100위" }
            let when = "국가 \(scan.countries.count)개 · \(AppFormat.relative(scan.date)) 확인"
            guard let project else { return "앱마다 차트에 든 나라와 가장 높은 자리 · " + when }
            guard let trackId = keywords.trackId(for: project),
                  let best = charts.history.bestCurrent(for: trackId) else { return "고른 나라 차트 100위 밖 · " + when }
            return "\(charts.history.countriesRanked(for: trackId))개국 차트인 · 최고 \(ChartStorefronts.name(best.slot.country)) \(best.rank)위 · " + when
        case .purchases:
            guard purchases.isConfigured else { return "App Store Connect 키를 넣으면 상품과 판매가 나옵니다" }
            guard let project else { return "앱별 최근 \(AppStoreConnectStore.salesDays)일 판매 순위" }
            guard let products = purchases.products(for: project) else { return "App Store Connect 상품" }
            return "상품 \(products.count)개 · 판매 중 \(products.filter(\.isOnSale).count)개"
        case .reviews:
            guard purchases.isConfigured else { return "App Store Connect 키를 넣으면 리뷰를 읽고 답할 수 있습니다" }
            guard let project else {
                let feeds = purchases.reviewFeeds.filter { !store.hiddenProjects.contains($0.key) }.values
                let total = feeds.reduce(0) { $0 + $1.reviews.count }
                guard total > 0 else { return "모든 앱의 App Store 리뷰" }
                let unanswered = feeds.reduce(0) { $0 + $1.unanswered }
                var text = "앱 \(feeds.filter { !$0.reviews.isEmpty }.count)개 · 리뷰 \(AppFormat.count(total))건"
                text += unanswered > 0 ? " · 답 안 함 \(unanswered)건" : " · 모두 답함"
                return text
            }
            guard let feed = purchases.reviewFeeds[project], feed.fetchedAt != nil else { return "App Store 리뷰" }
            var text = "리뷰 \(AppFormat.count(feed.reviews.count))건"
            if let average = feed.average { text += String(format: " · 평균 %.2f", average) }
            text += feed.unanswered > 0 ? " · 답 안 함 \(feed.unanswered)건" : " · 모두 답함"
            return text
        case .design:
            return "화면 설계도 · 문제 정의부터 솔루션까지 · 리포의 \(DesignDocsStore.folder)"
        case .storeAnalytics:
            guard purchases.isConfigured else { return "App Store Connect 키를 넣으면 Apple 이 모은 분석 리포트가 나옵니다" }
            guard let project else {
                if let analysis = purchases.priority {
                    return "앱 \(analysis.rows.count)개 위험 · 기회 순위 · \(AppFormat.relative(analysis.date))"
                }
                guard let coverage = purchases.analyticsCoverage?.value else { return "앱마다 위험 · 기회 순위와 리포트 현황" }
                return coverage.missing.isEmpty ? "앱 \(coverage.apps.count)개 모두 쌓는 중"
                    : "앱 \(coverage.apps.count)개 중 \(coverage.missing.count)개는 요청 없음"
            }
            guard case .ready(let analytics)? = purchases.storeAnalytics[project]?.value else { return "App Store Connect 분석 리포트" }
            var text = "최근 \(analytics.days)일 · 리포트 파일 \(analytics.instances)개"
            if let surge = analytics.insights?.surge { text += " · \(surge.range) 몰림 제외하고 판정" }
            return text
        }
    }

    // MARK: - Parts

    /// 할 일 — 모든 앱의 답 안 한 리뷰(완료로 둔 것 빼고) + 처리 안 한 피드백(버그 포함).
    /// `InboxView` 가 보여 주는 행과 같은 기준이어야 뱃지와 목록이 같은 수를 말한다.
    private var inboxCount: Int {
        let reviews = purchases.reviewFeeds
            .filter { !store.hiddenProjects.contains($0.key) }
            .values.reduce(0) { total, feed in
                total + feed.reviews.filter { $0.response == nil && !store.isReviewDone($0.id) }.count
            }
        return reviews + store.countPending(in: store.feedback(for: nil))
    }

    /// 이 앱(전체면 모든 앱)의 받아 둔 리뷰 수.
    private func reviewCount(_ project: String?) -> Int {
        guard let project else { return purchases.reviewFeeds.values.reduce(0) { $0 + $1.reviews.count } }
        return purchases.reviewFeeds[project]?.reviews.count ?? 0
    }

    private func unansweredReviews(_ project: String?) -> Int {
        guard let project else { return purchases.reviewFeeds.values.reduce(0) { $0 + $1.unanswered } }
        return purchases.unansweredReviews(for: project)
    }

    /// 한 앱이면 그 앱이 빨강일 때 1, 전체면 빨강인 앱 수.
    private func releaseRedCount(_ project: String?) -> Int {
        let keys = project.map { [$0] } ?? store.projectCounts.map(\.key)
        return keys.filter { store.releaseLevel(for: $0) == .red }.count
    }

    /// "(지난주 대비 ▲12%)" — 견줄 것이 없으면 아무 말도 하지 않는다.
    private static func change(_ current: Int, _ previous: Int) -> String {
        guard previous > 0 else { return current > 0 ? " (이번 주 처음)" : "" }
        let ratio = Double(current - previous) / Double(previous)
        if current == previous { return " (지난주와 같음)" }
        let magnitude = abs(ratio)
        let amount = magnitude >= 10 ? String(format: "%.0f배", magnitude)
                                     : String(format: "%.0f%%", (magnitude * 100).rounded())
        return " (지난주 대비 \(amount) " + (current > previous ? "▲)" : "▼)")
    }
}

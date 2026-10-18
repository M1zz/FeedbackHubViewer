//
//  AppNews.swift
//  FeedbackHubViewer
//
//  "내 앱 소식" — 문장 하나로 말할 수 있는, 한 번 일어난 일.
//
//  통계 화면은 "지난주보다 12% 늘었다" 처럼 **숫자의 움직임**을 말한다. 소식은 다르다:
//  "일본 생산성 무료 차트 47위에 처음 들어갔다", "어느 블로그가 링크를 걸어 8명이 왔다",
//  "5.2.0 이 심사를 통과했다". 지나고 나서 "그날 무슨 일이 있었지?" 에 답하는 기록이다.
//
//  ── 세 규칙 ──
//
//  1. 같은 사건은 한 번만. 소식의 `id` 가 사건을 가리키고(앱 · 종류 · 대상 · 날짜),
//     한 번 본 id 는 다시 알리지 않는다(`NewsStore.seen`).
//  2. 처음 보는 데이터는 조용히 기준선만. 리뷰를 처음 받은 날 지난 1년 치 5점 리뷰가
//     한꺼번에 "소식" 으로 쏟아지면 안 된다. 그래서 탐지는 묶음(`NewsBatch`)으로 내고,
//     묶음이 처음 준비됐을 때(`ready`) 그 안의 것은 다 본 것으로 친다.
//  3. 소식마다 더 볼 곳이 있다 — 바깥 링크거나 앱 안의 한 칸.
//
//  전하는 것은 따로다. 일어난 일은 다 기록하지만, 사람에게는 그중 볼 만한 것만 골라
//  하루 한 번 짧게 전한다(`Briefing`).
//
//  탐지는 여기 순수 함수로만 한다. 데이터를 받아 오는 일 · 기억 · 알림은 `NewsStore`.
//

import Foundation
import SwiftUI

// MARK: - 소식 하나

struct NewsItem: Codable, Identifiable, Hashable {
    /// 사건을 가리키는 키. 같은 사건이면 언제 다시 탐지해도 같은 값이어야 한다.
    let id: String
    let project: String
    let kind: NewsKind
    let title: String
    let body: String
    /// 일이 일어난 때(아는 만큼). 모르면 찾은 때.
    let date: Date
    /// 찾은 때. 아침 묶음 알림은 이것으로 가른다.
    let foundAt: Date
    /// 바깥 링크(기사 · 레딧 · 링크를 건 사이트).
    var url: URL?
}

/// 소식의 종류. 순서가 곧 같은 날 안에서의 차례다.
enum NewsKind: String, Codable, CaseIterable {
    // 경고
    case releaseRed, newCrash, versionRejected, reviewLowCluster
    // 스토어
    case versionLive, chartEntered, chartBest, storeSurge, keywordTop10, keywordRefresh, chartDropped, versionInReview
    // 사람들
    case webMention, referralNew, referralSurge, reviewGlowing, reviewNewTerritory
    // 이정표
    case installMilestone, dailyInstallRecord, dauRecord, newCountry

    var category: NewsCategory {
        switch self {
        case .releaseRed, .newCrash, .versionRejected, .reviewLowCluster: .warning
        case .versionLive, .chartEntered, .chartBest, .storeSurge, .keywordTop10, .keywordRefresh, .chartDropped, .versionInReview: .store
        case .webMention: .web
        case .referralNew, .referralSurge, .reviewGlowing, .reviewNewTerritory: .people
        case .installMilestone, .dailyInstallRecord, .dauRecord, .newCountry: .milestone
        }
    }

    var systemImage: String {
        switch self {
        case .releaseRed: "stethoscope"
        case .newCrash: "exclamationmark.triangle.fill"
        case .versionRejected: "xmark.seal.fill"
        case .reviewLowCluster: "hand.thumbsdown.fill"
        case .versionLive: "checkmark.seal.fill"
        case .versionInReview: "hourglass"
        case .chartEntered: "chart.line.uptrend.xyaxis"
        case .chartBest: "trophy.fill"
        case .chartDropped: "chart.line.downtrend.xyaxis"
        case .storeSurge: "sparkles"
        case .keywordTop10: "magnifyingglass"
        case .keywordRefresh: "arrow.triangle.2.circlepath"
        case .webMention: "newspaper.fill"
        case .referralNew: "link"
        case .referralSurge: "arrow.up.forward.app"
        case .reviewGlowing: "star.bubble.fill"
        case .reviewNewTerritory: "globe"
        case .installMilestone: "flag.checkered"
        case .dailyInstallRecord: "arrow.down.app.fill"
        case .dauRecord: "person.3.fill"
        case .newCountry: "mappin.and.ellipse"
        }
    }

    /// 앱 안에서 더 볼 칸. 바깥 링크가 있으면 그쪽이 먼저다.
    var section: FeedbackStore.ProjectSection {
        switch self {
        case .releaseRed: .release
        case .newCrash: .crashes
        case .versionRejected, .versionLive, .versionInReview: .reviews
        case .reviewLowCluster, .reviewGlowing, .reviewNewTerritory: .reviews
        case .chartEntered, .chartBest, .chartDropped: .charts
        case .storeSurge: .storeAnalytics
        case .keywordTop10, .keywordRefresh: .keywords
        case .webMention, .referralNew, .referralSurge: .acquisition
        case .installMilestone, .dailyInstallRecord, .dauRecord, .newCountry: .stats
        }
    }
}

extension NewsKind {
    /// 브리핑에 올릴 차례. nil 이면 기록에만 남고 브리핑에는 안 오른다 — 심사 시작 · 차트에서
    /// 빠짐 · 새 나라의 설치는 일어난 일이지만, 일부러 보러 갈 만한 일은 아니다.
    var briefingRank: Int? {
        let order: [NewsKind] = [
            .releaseRed, .versionRejected, .reviewLowCluster, .newCrash,
            .webMention, .chartEntered, .storeSurge, .referralNew, .versionLive,
            .installMilestone, .chartBest, .keywordTop10, .keywordRefresh, .referralSurge, .reviewGlowing,
            .dailyInstallRecord, .dauRecord, .reviewNewTerritory
        ]
        return order.firstIndex(of: self)
    }

    /// "그래서 무엇을" 한 줄. 브리핑의 화살표 뒤에 붙는다.
    var action: String {
        switch self {
        case .releaseRed: "릴리즈 화면에서 무엇이 빨강인지 보세요"
        case .newCrash: "진단에서 어디서 죽는지 보세요"
        case .versionRejected: "해결 센터에서 까닭을 보고 고쳐 다시 내세요"
        case .reviewLowCluster: "무엇이 깨졌는지 리뷰를 읽어 보세요"
        case .versionLive: "새 버전 소식을 알려도 좋을 때예요"
        case .versionInReview: "결과를 기다리면 돼요"
        case .chartEntered: "지금 그 나라 말로 홍보를 얹을 때예요"
        case .chartBest: "무엇이 먹혔는지 유입에서 확인해 보세요"
        case .chartDropped: "차트에서 순위를 확인해 보세요"
        case .storeSurge: "어디서 몰려왔는지 스토어 분석에서 보세요"
        case .keywordTop10: "이 말을 부제 · 키워드에서 지키세요"
        case .keywordRefresh: "키워드 칸에서 글을 복사해 Claude 에게 맡기세요"
        case .webMention: "글을 읽고, 틀린 내용이 있으면 바로잡을 수 있어요"
        case .referralNew: "어떤 곳인지 들어가 보세요"
        case .referralSurge: "그곳에 무슨 글이 올라왔는지 보세요"
        case .reviewGlowing: "답장으로 고마움을 전해 보세요"
        case .reviewNewTerritory: "그 나라 말로 답장해 보세요"
        case .installMilestone: "기념으로 알려도 좋아요"
        case .dailyInstallRecord, .dauRecord: "그날 무슨 일이 있었는지 보세요"
        case .newCountry: "통계에서 나라별로 보세요"
        }
    }
}

// MARK: - 브리핑

/// "오늘 볼 만한 것" — 소식을 다 늘어놓지 않고 골라서 짧게 전한다.
///
/// 같은 앱의 같은 종류는 한 줄로 합친다(차트 세 곳에 든 것은 세 줄이 아니라
/// "차트 세 곳에 들었어요" 한 줄). 그리고 중요한 차례(`briefingRank`)로 `limit` 줄까지만.
struct Briefing {
    struct Line: Identifiable {
        let id: String
        let project: String
        let kind: NewsKind
        let title: String
        let detail: String?
        let url: URL?
        var action: String { kind.action }
    }

    let lines: [Line]
    /// 줄 수를 넘겨 빠진 것.
    let more: Int

    static let limit = 5

    var isEmpty: Bool { lines.isEmpty }

    init(items: [NewsItem], name: (String) -> String) {
        let picked = items.filter { $0.kind.briefingRank != nil }
        let groups = Dictionary(grouping: picked) { "\($0.project)|\($0.kind.rawValue)" }
        let merged: [Line] = groups.values.compactMap { group in
            let sorted = group.sorted { $0.date > $1.date }
            guard let first = sorted.first else { return nil }
            if sorted.count == 1 {
                return Line(id: first.id, project: first.project, kind: first.kind,
                            title: first.title, detail: first.body, url: first.url)
            }
            return Line(id: first.id, project: first.project, kind: first.kind,
                        title: Self.mergedTitle(first.kind, app: name(first.project), count: sorted.count),
                        detail: sorted.prefix(3).map(\.title).joined(separator: "\n"),
                        url: first.url)
        }
        let ranked = merged.sorted {
            let (a, b) = ($0.kind.briefingRank ?? .max, $1.kind.briefingRank ?? .max)
            return a == b ? $0.title < $1.title : a < b
        }
        lines = Array(ranked.prefix(Self.limit))
        more = max(0, ranked.count - Self.limit)
    }

    private static func mergedTitle(_ kind: NewsKind, app: String, count: Int) -> String {
        switch kind {
        case .chartEntered: "\(app.이가) 차트 \(count)곳에 새로 들었어요"
        case .chartBest: "\(app.이가) 차트 \(count)곳에서 최고 순위예요"
        case .webMention: "\(app) 이야기가 바깥에 \(count)건 나왔어요"
        case .referralNew: "\(count)곳에서 \(app) 링크를 새로 걸었어요"
        case .referralSurge: "\(count)곳에서 \(app.으로) 오는 사람이 늘었어요"
        case .reviewGlowing: "\(app)에 정성 들인 5점 리뷰가 \(count)건 왔어요"
        case .reviewNewTerritory: "\(app)에 처음 보는 나라의 리뷰가 \(count)곳에서 왔어요"
        case .keywordTop10: "\(app.이가) 검색어 \(count)개에서 10위 안에 들었어요"
        case .newCrash: "\(app)에서 처음 보는 크래시가 \(count)가지 나왔어요"
        default: "\(app) 소식 \(count)건"
        }
    }
}

enum NewsCategory: String, CaseIterable, Identifiable {
    case warning = "경고"
    case store = "스토어"
    case web = "바깥 뉴스"
    case people = "사람들"
    case milestone = "이정표"
    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .warning: .red
        case .store: .blue
        case .web: .purple
        case .people: .orange
        case .milestone: .green
        }
    }
}

/// 한 탐지가 한 앱에 대해 낸 것. `group` 이 처음 `ready` 로 오면 그 안의 소식은
/// 기준선이 되고 알리지 않는다(머리말 규칙 2).
struct NewsBatch {
    let group: String
    /// 탐지할 데이터가 실제로 있었나. 아직 안 받은 데이터를 "소식 없음" 으로 읽고 기준선을
    /// 잡으면, 나중에 받았을 때 옛일이 전부 새 소식이 된다.
    let ready: Bool
    let items: [NewsItem]
}

// MARK: - 탐지

/// 데이터 → 소식 후보. 기억은 하지 않는다 — 같은 입력이면 같은 후보(같은 id)를 낸다.
enum NewsDetector {

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: 차트

    /// 차트에 처음 듦 · 석 달 중 최고 순위 · 빠짐.
    static func charts(project: String, name: String, trackId: Int?, history: ChartHistory,
                       now: Date) -> NewsBatch {
        let group = "charts:\(project)"
        guard let trackId, let scan = history.lastScan else { return NewsBatch(group: group, ready: false, items: []) }
        let scanDay = day(scan.date)
        var items: [NewsItem] = []
        let genre = history.apps[trackId]?.genreName

        func slotName(_ slot: ChartSlot) -> String {
            let chart = slot.isOverall ? "전체" : (genre ?? "카테고리")
            return "\(ChartStorefronts.flag(slot.country)) \(ChartStorefronts.name(slot.country)) \(slot.platform.label) \(chart) \(slot.kind.label) 차트"
        }
        func slotKey(_ slot: ChartSlot) -> String {
            "\(slot.platform.rawValue)-\(slot.kind.rawValue)-\(slot.genreId.map(String.init) ?? "all")-\(slot.country)"
        }

        let best = Dictionary(history.best(for: trackId, days: ChartHistory.keepDays).map { ($0.hit.slot, $0.hit.rank) },
                              uniquingKeysWith: min)
        for hit in history.current(for: trackId) {
            if case .entered = history.move(of: hit) {
                items.append(NewsItem(id: "chart-in:\(slotKey(hit.slot)):\(trackId):\(scanDay)", project: project,
                                      kind: .chartEntered,
                                      title: "\(name) · \(slotName(hit.slot)) \(hit.rank)위에 들어갔어요",
                                      body: "직전 확인 때는 100위 밖이었어요. 지금 그 나라 사람들에게 스토어 첫 화면 쪽에서 보이는 중입니다.",
                                      date: scan.date, foundAt: now))
            } else if let top = best[hit.slot], hit.rank <= top {
                // 석 달 기록 중 가장 높은 자리. 같은 순위를 지키는 동안은 한 번만(순위가 id 에 있다).
                items.append(NewsItem(id: "chart-best:\(slotKey(hit.slot)):\(trackId):\(hit.rank)", project: project,
                                      kind: .chartBest,
                                      title: "\(name) · \(slotName(hit.slot)) \(hit.rank)위, 최근 석 달 중 가장 높아요",
                                      body: "기록을 남긴 \(ChartHistory.keepDays)일 동안 이 차트에서 가장 좋은 자리입니다.",
                                      date: scan.date, foundAt: now))
            }
        }
        for hit in history.dropped(for: trackId) {
            items.append(NewsItem(id: "chart-out:\(slotKey(hit.slot)):\(trackId):\(scanDay)", project: project,
                                  kind: .chartDropped,
                                  title: "\(name) · \(slotName(hit.slot))에서 빠졌어요",
                                  body: "직전 확인 때 \(hit.rank)위였는데 이번에는 100위 밖입니다.",
                                  date: scan.date, foundAt: now))
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    // MARK: 스토어 분석 — 몰린 기간

    /// 첫 다운로드가 평소보다 크게 몰린 기간. 스토어 소개(투데이 · 앱 추천)나 행사의 흔적이다.
    static func surge(project: String, name: String, insights: StoreInsights?, now: Date) -> NewsBatch {
        let group = "surge:\(project)"
        guard let insights else { return NewsBatch(group: group, ready: false, items: []) }
        guard let surge = insights.surge else { return NewsBatch(group: group, ready: true, items: []) }
        var body = "\(surge.range) \(surge.days)일 동안 첫 다운로드 \(Int(surge.firstDownloads))건"
        if let baseline = insights.baseline, baseline.firstDownloadsPerDay > 0 {
            let multiple = surge.firstDownloadsPerDay / baseline.firstDownloadsPerDay
            body += ", 평소 하루의 \(String(format: "%.0f", multiple))배"
        }
        body += ". 스토어에 소개됐거나 행사 · 홍보가 먹힌 때입니다. 어디서 왔는지 스토어 분석에서 보세요."
        let date = dayFormatter.date(from: surge.firstDay) ?? now
        return NewsBatch(group: group, ready: true, items: [
            NewsItem(id: "surge:\(project):\(surge.firstDay)", project: project, kind: .storeSurge,
                     title: "\(name) 다운로드가 몰렸어요 (\(surge.range))", body: body, date: date, foundAt: now)
        ])
    }

    // MARK: 키워드

    /// 키워드 검색 10위 안에 처음 듦. 순위가 오르내릴 때마다가 아니라 "처음" 만.
    static func keywords(project: String, name: String, standings: [KeywordStanding], now: Date) -> NewsBatch {
        let group = "keywords:\(project)"
        guard !standings.isEmpty else { return NewsBatch(group: group, ready: false, items: []) }
        let items = standings.compactMap { standing -> NewsItem? in
            guard let rank = standing.rank, rank <= 10 else { return nil }
            let term = standing.keyword.term
            return NewsItem(id: "kw10:\(project):\(standing.keyword.id)", project: project, kind: .keywordTop10,
                            title: "\(name) · '\(term)' 검색 \(rank)위",
                            body: "\(ChartStorefronts.flag(standing.keyword.country)) App Store 에서 '\(term)' 를 치면 첫 화면(10위 안)에 나옵니다.",
                            date: standing.seenAt ?? now, foundAt: now)
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    // MARK: 키워드 칸

    /// 키워드 칸을 바꾼 지 두 주가 지났다 — 다시 짤 때. 한 번 바꾼 칸마다 한 번만(바뀐 날이 id 에 있다).
    static func keywordRefresh(project: String, name: String, states: [KeywordRefreshState], now: Date) -> NewsBatch {
        let group = "kwrefresh:\(project)"
        guard !states.isEmpty else { return NewsBatch(group: group, ready: false, items: []) }
        let settled = states.filter(\.isSettled)
        guard let oldest = settled.max(by: { $0.days < $1.days }) else { return NewsBatch(group: group, ready: true, items: []) }
        let ranked = settled.map(\.ranked).reduce(0, +)
        let total = settled.map(\.terms.count).reduce(0, +)
        let title = oldest.changedAt == nil
            ? "\(name) · 키워드 칸이 \(oldest.days)일째 그대로예요"
            : "\(name) · 키워드 칸을 바꾼 지 \(oldest.days)일, 다시 짤 때예요"
        return NewsBatch(group: group, ready: true, items: [
            NewsItem(id: "kw-refresh:\(project):\(day(oldest.current.seenAt))", project: project, kind: .keywordRefresh,
                     title: title,
                     body: "칸의 말 \(total)개 중 \(ranked)개가 검색 200위 안에 있어요. 순위가 자리 잡았으니 무엇이 먹혔는지 보고 다시 짤 수 있어요.",
                     date: now, foundAt: now)
        ])
    }

    // MARK: 링크 출처

    /// 새로 링크를 건 곳 · 갑자기 많이 보내는 곳. 앱 · 웹 출처만(검색 · 둘러보기 같은 통로는 뺀다).
    static func referrals(project: String, name: String, detection: ReferralDetection?, now: Date) -> NewsBatch {
        let group = "referrals:\(project)"
        guard let detection else { return NewsBatch(group: group, ready: false, items: []) }
        var items: [NewsItem] = []
        for item in detection.places {
            let source = item.profile.name
            let url = item.source.kind == .web ? URL(string: "https://\(item.source.info)") : nil
            switch item.status {
            case .new:
                items.append(NewsItem(id: "ref-new:\(project):\(item.source.id)", project: project, kind: .referralNew,
                                      title: "\(source)에서 \(name) 링크를 걸었어요",
                                      body: "처음 보는 출처입니다. 지금까지 \(item.tally.firstDownloads)명이 그 링크로 와서 받았어요.",
                                      date: NewsDetector.dayFormatter.date(from: item.firstSeen) ?? now, foundAt: now, url: url))
            case .surging:
                let week = item.tally.lastDate ?? day(now)
                items.append(NewsItem(id: "ref-surge:\(project):\(item.source.id):\(week)", project: project, kind: .referralSurge,
                                      title: "\(source)에서 \(name.으로) 오는 사람이 늘었어요",
                                      body: "최근 \(ReferralDetection.recentDays)일 \(item.recent)명, 그 앞 \(ReferralDetection.recentDays)일 \(item.previous)명.",
                                      date: now, foundAt: now, url: url))
            default:
                break
            }
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    // MARK: 리뷰

    /// 길게 쓴 5점 리뷰 · 처음 보는 나라의 리뷰 · 이틀 안에 낮은 별점이 몰림.
    static func reviews(project: String, name: String, reviews: [CustomerReview]?, now: Date) -> NewsBatch {
        let group = "reviews:\(project)"
        guard let reviews else { return NewsBatch(group: group, ready: false, items: []) }
        var items: [NewsItem] = []

        for review in reviews where review.rating == 5 {
            let text = (review.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= glowingLength else { continue }
            items.append(NewsItem(id: "review-glow:\(review.id)", project: project, kind: .reviewGlowing,
                                  title: "\(name)에 정성 들인 5점 리뷰가 왔어요",
                                  body: "“\(text.prefix(120))\(text.count > 120 ? "…" : "")”",
                                  date: review.createdDate, foundAt: now))
        }

        // 나라마다 가장 먼저 온 리뷰 하나. 기준선이 지난 나라를 다 덮으므로, 뒤에 생기는 것은
        // 정말 처음 리뷰가 온 나라뿐이다.
        let firstByTerritory = Dictionary(grouping: reviews, by: \.territory)
            .compactMapValues { $0.min { $0.createdDate < $1.createdDate } }
        for (territory, review) in firstByTerritory {
            items.append(NewsItem(id: "review-territory:\(project):\(territory)", project: project, kind: .reviewNewTerritory,
                                  title: "\(name)에 처음으로 \(territoryName(territory)) 리뷰가 달렸어요",
                                  body: "\(String(repeating: "★", count: review.rating)) \(review.title ?? "")",
                                  date: review.createdDate, foundAt: now))
        }

        // 낮은 별점 몰림: 48시간 안에 2점 이하가 셋 이상. 하루 하나씩 따로 알리면 묻히는 것을
        // 묶어서 한 번. 같은 날 시작한 몰림은 한 번만.
        let low = reviews.filter { $0.rating <= 2 }.sorted { $0.createdDate < $1.createdDate }
        var index = 0
        while index < low.count {
            let start = low[index].createdDate
            let window = low[index...].prefix { $0.createdDate.timeIntervalSince(start) <= 48 * 3600 }
            if window.count >= lowClusterSize {
                items.append(NewsItem(id: "review-low:\(project):\(day(start))", project: project, kind: .reviewLowCluster,
                                      title: "\(name)에 낮은 별점이 몰렸어요 (이틀 동안 \(window.count)건)",
                                      body: window.compactMap { $0.title }.prefix(3).joined(separator: " · "),
                                      date: window.last?.createdDate ?? start, foundAt: now))
                index += window.count
            } else {
                index += 1
            }
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    static let glowingLength = 80
    static let lowClusterSize = 3

    // MARK: 버전

    /// 심사 통과(판매 시작) · 거절 · 심사 들어감. 상태가 바뀔 때마다 id 가 달라진다.
    static func version(project: String, name: String, status: AppVersionStatus?, now: Date) -> NewsBatch {
        let group = "version:\(project)"
        guard let status else { return NewsBatch(group: group, ready: false, items: []) }
        let id = "version:\(project):\(status.version):\(status.state)"
        let item: NewsItem?
        switch status.state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION":
            item = NewsItem(id: id, project: project, kind: .versionLive,
                            title: "\(name) \(status.version)이 스토어에 나왔어요",
                            body: "심사를 통과해 판매 중입니다. 지금부터 받는 사람은 이 버전을 받아요.", date: now, foundAt: now)
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
            item = NewsItem(id: id, project: project, kind: .versionRejected,
                            title: "\(name) \(status.version) \(status.stateLabel)",
                            body: "App Store Connect 의 해결 센터에서 까닭을 보고 고쳐 다시 내야 합니다.", date: now, foundAt: now)
        case "IN_REVIEW":
            item = NewsItem(id: id, project: project, kind: .versionInReview,
                            title: "\(name) \(status.version) 심사가 시작됐어요",
                            body: "보통 하루 안에 결과가 나옵니다.", date: now, foundAt: now)
        default:
            item = nil
        }
        return NewsBatch(group: group, ready: true, items: item.map { [$0] } ?? [])
    }

    // MARK: 릴리즈 건강

    /// 새 버전이 빨강 · 새 버전에서 처음 본 크래시.
    static func release(project: String, name: String, report: ReleaseHealth.Report?, now: Date) -> NewsBatch {
        let group = "release:\(project)"
        guard let report else { return NewsBatch(group: group, ready: false, items: []) }
        let version = report.latest.version
        var items: [NewsItem] = []
        if report.verdict.level == .red {
            items.append(NewsItem(id: "release-red:\(project):\(version)", project: project, kind: .releaseRed,
                                  title: "\(name) \(version)에 적신호가 켜졌어요",
                                  body: report.verdict.headline, date: now, foundAt: now))
        }
        for signature in report.latest.newSignatures where signature.isCrash {
            items.append(NewsItem(id: "sig:\(project):\(signature.fingerprint)", project: project, kind: .newCrash,
                                  title: "\(name) \(version)에서 처음 보는 크래시",
                                  body: "\(signature.title) · \(signature.reports)건", date: now, foundAt: now))
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    // MARK: 이정표

    static let installMilestones = [100, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000]

    /// 누적 설치 이정표 · 하루 설치 최고 기록 · 처음 보는 나라의 설치.
    static func milestones(project: String, name: String, installs: Int,
                           daily: [FeedbackStore.DailyInstall], regions: [String],
                           now: Date) -> NewsBatch {
        let group = "milestones:\(project)"
        guard installs > 0 else { return NewsBatch(group: group, ready: false, items: []) }
        var items: [NewsItem] = []
        if let reached = installMilestones.last(where: { installs >= $0 }) {
            items.append(NewsItem(id: "installs:\(project):\(reached)", project: project, kind: .installMilestone,
                                  title: "\(name) 누적 설치 \(AppFormat.count(reached))대를 넘었어요",
                                  body: "지금 \(AppFormat.count(installs))대. 지웠다 다시 설치한 것도 한 번씩 셉니다.",
                                  date: now, foundAt: now))
        }
        // 어제(끝난 하루)가 그 전 모든 날보다 많으면. 오늘은 아직 안 끝나서 보지 않는다.
        let finished = daily.dropLast()
        if let yesterday = finished.last, yesterday.count >= recordMinimum {
            let before = finished.dropLast().map(\.count).max() ?? 0
            if yesterday.count > before, finished.count > 7 {
                items.append(NewsItem(id: "record-installs:\(project):\(day(yesterday.date))", project: project,
                                      kind: .dailyInstallRecord,
                                      title: "\(name) 하루 설치 최고 기록: \(yesterday.count)대",
                                      body: "\(AppFormat.chartDay(yesterday.date)) 하루에 \(yesterday.count)대가 새로 설치됐어요. 지금까지 가장 많던 날은 \(before)대였습니다.",
                                      date: yesterday.date, foundAt: now))
            }
        }
        for code in regions {
            items.append(NewsItem(id: "country:\(project):\(code)", project: project, kind: .newCountry,
                                  title: "\(name.이가) 처음으로 \(regionName(code))에서 설치됐어요",
                                  body: "기기 지역 설정이 \(regionName(code))인 사람이 처음 설치했습니다.",
                                  date: now, foundAt: now))
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    /// 어제 DAU 가 기록을 넘었나. 일별 DAU 이력은 30일만 남아서, 최고값은 `NewsStore` 가
    /// 따로 기억해 넘긴다(`previousBest` nil 이면 아직 기준이 없다).
    static func dauRecord(project: String, name: String, yesterdayDAU: Int, previousBest: Int?, now: Date) -> NewsItem? {
        guard let previousBest, yesterdayDAU > previousBest, yesterdayDAU >= recordMinimum else { return nil }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return NewsItem(id: "record-dau:\(project):\(day(yesterday))", project: project, kind: .dauRecord,
                        title: "\(name) 하루 사용자 최고 기록: \(yesterdayDAU)명",
                        body: "어제 \(yesterdayDAU)명이 썼어요. 지금까지 가장 많던 날은 \(previousBest)명이었습니다.",
                        date: yesterday, foundAt: now)
    }

    /// 기록이라고 부를 최소치. 하루 2대가 최고 기록이면 소식이 아니라 소음이다.
    static let recordMinimum = 5

    // MARK: 바깥 뉴스

    static func web(project: String, name: String, mentions: [WebMention]?, now: Date) -> NewsBatch {
        let group = "web:\(project)"
        guard let mentions else { return NewsBatch(group: group, ready: false, items: []) }
        let items = mentions.map { mention in
            NewsItem(id: "web:\(mention.url.absoluteString)", project: project, kind: .webMention,
                     title: mention.title,
                     body: "\(mention.source)에서 \(name) 이야기 · '\(mention.term)' 로 찾음",
                     date: mention.date ?? now, foundAt: now, url: mention.url)
        }
        return NewsBatch(group: group, ready: true, items: items)
    }

    // MARK: 이름

    /// "KOR" → "대한민국". 리뷰의 지역은 세 글자다.
    static func territoryName(_ code: String) -> String {
        guard let two = alpha3.first(where: { $0.value == code })?.key else { return code }
        return regionName(two)
    }

    static func regionName(_ code: String) -> String {
        Locale(identifier: "ko_KR").localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    /// ISO 두 글자 → 세 글자. Foundation 에 바로 가는 길이 없어 리뷰가 올 만한 나라만 적는다.
    private static let alpha3: [String: String] = [
        "KR": "KOR", "US": "USA", "JP": "JPN", "CN": "CHN", "TW": "TWN", "HK": "HKG", "GB": "GBR", "DE": "DEU",
        "FR": "FRA", "IT": "ITA", "ES": "ESP", "CA": "CAN", "AU": "AUS", "NZ": "NZL", "SG": "SGP", "MY": "MYS",
        "TH": "THA", "VN": "VNM", "ID": "IDN", "PH": "PHL", "IN": "IND", "BR": "BRA", "MX": "MEX", "AR": "ARG",
        "CL": "CHL", "CO": "COL", "RU": "RUS", "UA": "UKR", "PL": "POL", "NL": "NLD", "BE": "BEL", "CH": "CHE",
        "AT": "AUT", "SE": "SWE", "NO": "NOR", "DK": "DNK", "FI": "FIN", "IE": "IRL", "PT": "PRT", "GR": "GRC",
        "TR": "TUR", "IL": "ISR", "AE": "ARE", "SA": "SAU", "EG": "EGY", "ZA": "ZAF", "CZ": "CZE", "HU": "HUN",
        "RO": "ROU", "SK": "SVK", "KZ": "KAZ", "PK": "PAK", "BD": "BGD", "MO": "MAC", "MN": "MNG"
    ]
}

// MARK: - 조사

/// 앱 이름 뒤의 조사를 받침에 맞춘다 — "두번알림이", "클립키보드가". 한글로 끝나지 않는
/// 이름(Goldweek)은 받침을 알 수 없어 "이(가)" 처럼 둘 다 적는다.
extension String {
    /// 마지막 글자의 받침. 한글이 아니면 nil, ㄹ 받침이면 `rieul` 이 true.
    private var finalConsonant: (has: Bool, rieul: Bool)? {
        guard let scalar = unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        let jong = (scalar.value - 0xAC00) % 28
        return (jong != 0, jong == 8)
    }

    var 이가: String {
        guard let final = finalConsonant else { return self + "이(가)" }
        return self + (final.has ? "이" : "가")
    }

    /// "(으)로" — 받침이 없거나 ㄹ 받침이면 "로".
    var 으로: String {
        guard let final = finalConsonant else { return self + "(으)로" }
        return self + (final.has && !final.rieul ? "으로" : "로")
    }
}

//
//  Referrals.swift
//  FeedbackHubViewer
//
//  누가 내 앱을 링크했나 — App Store 상세 리포트의 출처 이름으로 찾는다.
//
//  App Downloads Detailed 와 Discovery and Engagement Detailed 에는 `Source Type` 옆에
//  `Source Info` 가 있다. 웹에서 왔으면 도메인(`reddit.com`), 다른 앱에서 왔으면 그 앱의
//  번들 ID(`com.tencent.xin`)다. 이걸 모으면 "어디서 내 앱 얘기가 돌고 있나"가 보인다 —
//  실측으로 클립키보드 한 달에 AppRaven(딜 앱) · 什么值得买(중국 딜 커뮤니티) · 텔레그램 ·
//  위챗 · 태국 유튜브 · reddit.com 이 잡혔다. 판매 리포트로는 나라까지만 보였던 것이다.
//
//  ── 이 데이터가 못 보는 것 ──
//
//   · **개별 글 주소는 없다.** 도메인까지다. 어떤 글인지는 그 도메인에서 직접 찾아야 한다.
//   · **작은 출처는 빠진다.** 프라이버시 임계값 아래의 칸은 이름이 비거나 행이 통째로
//     없다. 그래서 이름 없는 웹 유입(`Web referrer` + 빈 칸)을 따로 세어 "가려진 몫"으로
//     밝힌다. 합계는 Standard 리포트 쪽이 맞다.
//   · **iOS 의 Safari 가 아닌 브라우저는 웹이 아니라 그 브라우저 앱으로 잡힌다**
//     (Chrome → `com.google.chrome.ios`). 브라우저 · 메모 같은 앱은 "누가 링크했나"가
//     아니라 "링크가 어디서 열렸나"라서, 곳이 아니라 **통로**로 따로 적는다.
//   · 언급 모니터링이 아니다. 링크 없이 이름만 말한 글, 아직 아무도 안 누른 링크는 없다.
//

import Foundation

// MARK: - 출처

/// 앱으로 사람을 보낸 곳 하나.
struct ReferralSource: Hashable, Codable, Identifiable {
    enum Kind: String, Codable {
        /// Safari 에서 연 웹 페이지. `info` 는 도메인.
        case web
        /// 다른 앱. `info` 는 그 앱의 번들 ID.
        case app
    }

    let kind: Kind
    let info: String

    var id: String { "\(kind.rawValue):\(info)" }

    /// 리포트 한 행에서. 출처 종류가 링크가 아니거나(검색 · 둘러보기) 이름이 가려졌으면 nil.
    init?(sourceType: String?, sourceInfo: String?) {
        let info = (sourceInfo ?? "").trimmingCharacters(in: .whitespaces)
        switch sourceType {
        case "Web referrer": kind = .web
        case "App referrer": kind = .app
        default: return nil
        }
        guard !info.isEmpty else { return nil }
        // 도메인은 대소문자가 뜻이 없다. 번들 ID 는 그대로 둔다(사전과 맞춰야 한다).
        self.info = kind == .web ? info.lowercased() : info
    }

    init(kind: Kind, info: String) {
        self.kind = kind
        self.info = info
    }

    /// 사람이 읽을 이름과 종류.
    var profile: ReferralProfile { ReferralProfile.of(self) }
}

/// 출처가 무엇인가 — 이름과 종류.
struct ReferralProfile {
    enum Category: String {
        case dealCommunity = "딜 · 앱 할인"
        case community = "커뮤니티"
        case messenger = "메신저"
        case social = "SNS"
        case video = "동영상"
        case search = "검색"
        case news = "뉴스 · 블로그"
        /// 링크가 열린 통로일 뿐, 링크를 건 곳이 아니다(브라우저 · 메모 · 메일).
        case passage = "통로"
        case other = "기타"
    }

    let name: String
    let category: Category

    /// 곳이 아니라 통로인가 — "누가 링크했나"의 답이 아니다.
    var isPassage: Bool { category == .passage }

    /// 알려진 출처 사전. 모르는 것은 도메인 · 번들 ID 를 이름으로 쓴다.
    ///
    /// 여기 없는 출처가 잡히면 화면이 "모르는 출처"로 띄운다 — 그게 사전에 한 줄 더할 신호다.
    static func of(_ source: ReferralSource) -> ReferralProfile {
        let table = source.kind == .app ? apps : webs
        if let known = table[source.info] { return known }
        if source.kind == .web {
            // 하위 도메인은 본 도메인으로 찾는다(m.youtube.com → youtube.com).
            let parts = source.info.split(separator: ".")
            if parts.count > 2, let known = webs[parts.suffix(2).joined(separator: ".")] { return known }
        }
        return ReferralProfile(name: source.info, category: .other)
    }

    private static let apps: [String: ReferralProfile] = [
        // 딜 · 앱 할인
        "net.appraven.app": .init(name: "AppRaven", category: .dealCommunity),
        "com.smzdm.client.ios": .init(name: "什么值得买 (SMZDM)", category: .dealCommunity),
        "com.appadvice.appadvice": .init(name: "AppAdvice", category: .dealCommunity),
        "com.xmlabs.appshopper": .init(name: "AppShopper", category: .dealCommunity),
        // 커뮤니티
        "com.reddit.Reddit": .init(name: "Reddit 앱", category: .community),
        "com.christianselig.Apollo": .init(name: "Apollo (Reddit)", category: .community),
        "com.hackemist.narwhal": .init(name: "Narwhal (Reddit)", category: .community),
        "com.xingin.discover": .init(name: "小红书 (Xiaohongshu)", category: .community),
        "com.zhihu.ios": .init(name: "知乎 (Zhihu)", category: .community),
        "com.coolapk.market": .init(name: "酷安 (Coolapk)", category: .community),
        "com.ptt.PTTApp": .init(name: "PTT", category: .community),
        "com.dcard.app": .init(name: "Dcard", category: .community),
        "com.clien.ClienApp": .init(name: "클리앙", category: .community),
        "com.daum.cafe": .init(name: "다음 카페", category: .community),
        "com.nhncorp.NaverCafe": .init(name: "네이버 카페", category: .community),
        // 메신저
        "com.tencent.xin": .init(name: "WeChat", category: .messenger),
        "com.tencent.mqq": .init(name: "QQ", category: .messenger),
        "ph.telegra.Telegraph": .init(name: "Telegram", category: .messenger),
        "jp.naver.line": .init(name: "LINE", category: .messenger),
        "com.iwilab.KakaoTalk": .init(name: "카카오톡", category: .messenger),
        "net.whatsapp.WhatsApp": .init(name: "WhatsApp", category: .messenger),
        "com.hammerandchisel.discord": .init(name: "Discord", category: .messenger),
        "com.tinyspeck.chatlyio": .init(name: "Slack", category: .messenger),
        "com.facebook.Messenger": .init(name: "Messenger", category: .messenger),
        // SNS
        "com.facebook.Facebook": .init(name: "Facebook", category: .social),
        "com.burbn.instagram": .init(name: "Instagram", category: .social),
        "com.atebits.Tweetie2": .init(name: "X (Twitter)", category: .social),
        "com.burbn.barcelona": .init(name: "Threads", category: .social),
        "xyz.blueskyweb.app": .init(name: "Bluesky", category: .social),
        "com.sina.weibo": .init(name: "微博 (Weibo)", category: .social),
        "com.zhiliaoapp.musically": .init(name: "TikTok", category: .social),
        "com.ss.iphone.ugc.Aweme": .init(name: "抖音 (Douyin)", category: .social),
        "com.linkedin.LinkedIn": .init(name: "LinkedIn", category: .social),
        // 동영상
        "com.google.ios.youtube": .init(name: "YouTube 앱", category: .video),
        "tv.danmaku.bilianime": .init(name: "bilibili", category: .video),
        // 검색
        "com.google.GoogleMobile": .init(name: "Google 앱", category: .search),
        "com.nhncorp.NaverSearch": .init(name: "네이버 앱", category: .search),
        "com.baidu.BaiduMobile": .init(name: "百度 (Baidu)", category: .search),
        // 통로
        "com.google.chrome.ios": .init(name: "Chrome", category: .passage),
        "org.mozilla.ios.Firefox": .init(name: "Firefox", category: .passage),
        "com.microsoft.msedge": .init(name: "Edge", category: .passage),
        "com.brave.ios.browser": .init(name: "Brave", category: .passage),
        "com.duckduckgo.mobile.ios": .init(name: "DuckDuckGo", category: .passage),
        "com.apple.mobilenotes": .init(name: "메모", category: .passage),
        "com.apple.mobilemail": .init(name: "메일", category: .passage),
        "com.google.Gmail": .init(name: "Gmail", category: .passage),
        "com.apple.MobileSMS": .init(name: "메시지", category: .passage),
    ]

    private static let webs: [String: ReferralProfile] = [
        "reddit.com": .init(name: "Reddit", category: .community),
        "news.ycombinator.com": .init(name: "Hacker News", category: .community),
        "producthunt.com": .init(name: "Product Hunt", category: .community),
        "macrumors.com": .init(name: "MacRumors", category: .community),
        "ptt.cc": .init(name: "PTT", category: .community),
        "dcard.tw": .init(name: "Dcard", category: .community),
        "v2ex.com": .init(name: "V2EX", category: .community),
        "clien.net": .init(name: "클리앙", category: .community),
        "ppomppu.co.kr": .init(name: "뽐뿌", category: .dealCommunity),
        "smzdm.com": .init(name: "什么值得买 (SMZDM)", category: .dealCommunity),
        "appraven.net": .init(name: "AppRaven", category: .dealCommunity),
        "appadvice.com": .init(name: "AppAdvice", category: .dealCommunity),
        "appsliced.co": .init(name: "AppSliced", category: .dealCommunity),
        "youtube.com": .init(name: "YouTube", category: .video),
        "bilibili.com": .init(name: "bilibili", category: .video),
        "x.com": .init(name: "X (Twitter)", category: .social),
        "twitter.com": .init(name: "X (Twitter)", category: .social),
        "t.co": .init(name: "X (Twitter)", category: .social),
        "facebook.com": .init(name: "Facebook", category: .social),
        "instagram.com": .init(name: "Instagram", category: .social),
        "threads.net": .init(name: "Threads", category: .social),
        "weibo.com": .init(name: "微博 (Weibo)", category: .social),
        "google.com": .init(name: "Google 검색", category: .search),
        "bing.com": .init(name: "Bing 검색", category: .search),
        "duckduckgo.com": .init(name: "DuckDuckGo 검색", category: .search),
        "naver.com": .init(name: "네이버", category: .search),
        "baidu.com": .init(name: "百度 (Baidu)", category: .search),
        "medium.com": .init(name: "Medium", category: .news),
        "tistory.com": .init(name: "티스토리", category: .news),
        "blog.naver.com": .init(name: "네이버 블로그", category: .news),
        "brunch.co.kr": .init(name: "브런치", category: .news),
        "github.com": .init(name: "GitHub", category: .news),
        "github.io": .init(name: "GitHub Pages", category: .news),
    ]
}

// MARK: - 리포트

/// 한 앱의 최근 `days`일 출처별 셈.
struct ReferralReport {
    struct Tally {
        /// 날짜 → 그날 첫 다운로드.
        var downloadsByDate: [String: Int] = [:]
        /// 제품 페이지 조회(고유). 다운로드로 안 이어진 관심까지 보인다.
        var pageViews = 0
        /// 나라 → 첫 다운로드.
        var territories: [String: Int] = [:]
        /// 다운로드든 조회든 이 출처가 나타난 날.
        var seenDates: Set<String> = []

        var firstDownloads: Int { downloadsByDate.values.reduce(0, +) }
        var firstDate: String? { seenDates.min() }
        var lastDate: String? { downloadsByDate.keys.max() }

        /// 첫 다운로드가 많은 나라부터.
        var topTerritories: [(code: String, count: Int)] {
            territories.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { ($0.key, $0.value) }
        }
    }

    let days: Int
    var sources: [ReferralSource: Tally] = [:]
    /// 웹에서 왔지만 이름이 가려진 첫 다운로드(프라이버시 임계값).
    var hiddenWebDownloads = 0
    /// 읽은 리포트 인스턴스 수. 0이면 상세 리포트가 아직 안 쌓였다.
    var instances = 0

    init(days: Int) { self.days = days }

    /// 두 상세 리포트의 행을 출처별로 모은다.
    init(days: Int, downloads: AnalyticsRows, engagement: AnalyticsRows) {
        self.days = days
        instances = downloads.instances + engagement.instances
        for (date, rows) in downloads.byDate {
            for row in rows where row["Download Type"] == "First-time download" {
                let count = Int(row["Counts"] ?? "") ?? 0
                guard count > 0 else { continue }
                guard let source = ReferralSource(sourceType: row["Source Type"], sourceInfo: row["Source Info"]) else {
                    if row["Source Type"] == "Web referrer" { hiddenWebDownloads += count }
                    continue
                }
                sources[source, default: .init()].downloadsByDate[date, default: 0] += count
                sources[source, default: .init()].seenDates.insert(date)
                if let territory = row["Territory"], !territory.isEmpty {
                    sources[source, default: .init()].territories[territory, default: 0] += count
                }
            }
        }
        for (date, rows) in engagement.byDate {
            for row in rows where row["Event"] == "Page view" {
                guard let source = ReferralSource(sourceType: row["Source Type"], sourceInfo: row["Source Info"]) else { continue }
                sources[source, default: .init()].pageViews += Int(row["Unique Counts"] ?? "") ?? Int(row["Counts"] ?? "") ?? 0
                sources[source, default: .init()].seenDates.insert(date)
            }
        }
    }
}

// MARK: - 감지

/// 리포트와 지난 기록을 견줘 "새로 링크한 곳"과 "갑자기 늘어난 곳"을 가린다.
///
/// 새로움은 리포트 창이 아니라 **처음 본 날의 기록**(`ledger`)으로 판단한다. 창은 30일이라,
/// 창만 보면 두 달 전에 링크했던 곳이 다시 나타나도 새 곳이 된다. 기록은 한 번 본 출처의
/// 첫날을 잊지 않는다. 기록이 처음 생기는 날에는 창의 첫날이 곧 처음 본 날이다.
struct ReferralDetection {
    enum Status: Int, Comparable {
        /// 최근 `recentDays` 안에 처음 나타났다.
        case new = 0
        /// 최근 `recentDays` 가 그 앞 같은 길이보다 크게 늘었다.
        case surging
        /// 꾸준히 보내 온 곳.
        case steady
        /// 창 안에 있었지만 최근엔 조용하다.
        case quiet

        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }

        /// 알릴 상태인가 — 새로 링크했거나 급증했다.
        var isAlert: Bool { self == .new || self == .surging }

        var label: String {
            switch self {
            case .new: return "새로"
            case .surging: return "급증"
            case .steady: return "꾸준"
            case .quiet: return "잠잠"
            }
        }
    }

    struct Item: Identifiable {
        let source: ReferralSource
        let tally: ReferralReport.Tally
        let status: Status
        /// 처음 본 날(기록 기준).
        let firstSeen: String
        let recent: Int
        let previous: Int

        var id: String { source.id }
        var profile: ReferralProfile { source.profile }
    }

    /// "최근"의 길이.
    static let recentDays = 7
    /// 급증으로 부르려면 최근 창에 이만큼은 와야 한다 — 1 → 3은 급증이 아니라 우연이다.
    static let surgeMinimum = 5
    /// 급증 배수.
    static let surgeRatio = 3.0

    /// 곳(링크를 건 곳)과 통로를 가른 목록. 상태가 급한 것부터, 같으면 최근에 많이 보낸 순.
    let places: [Item]
    let passages: [Item]
    /// 이번에 처음 본 출처를 더한 기록. 스토어가 디스크에 쓴다.
    let ledger: [String: String]

    init(report: ReferralReport, ledger old: [String: String], today: Date = Date()) {
        let calendar = Calendar(identifier: .gregorian)
        func day(_ offset: Int) -> String {
            AppStoreConnect.day.string(from: calendar.date(byAdding: .day, value: -offset, to: today) ?? today)
        }
        let recentStart = day(Self.recentDays)
        let previousStart = day(Self.recentDays * 2)

        var ledger = old
        var items: [Item] = []
        for (source, tally) in report.sources {
            guard let first = tally.firstDate else { continue }
            let firstSeen = min(ledger[source.id] ?? first, first)
            ledger[source.id] = firstSeen

            let recent = tally.downloadsByDate.filter { $0.key >= recentStart }.values.reduce(0, +)
            let previous = tally.downloadsByDate.filter { $0.key >= previousStart && $0.key < recentStart }.values.reduce(0, +)
            let status: Status
            if firstSeen >= recentStart {
                status = .new
            } else if recent >= Self.surgeMinimum, Double(recent) >= Double(max(previous, 1)) * Self.surgeRatio {
                status = .surging
            } else if recent > 0 {
                status = .steady
            } else {
                status = .quiet
            }
            items.append(Item(source: source, tally: tally, status: status,
                              firstSeen: firstSeen, recent: recent, previous: previous))
        }
        items.sort {
            ($0.status, -$0.recent, -$0.tally.firstDownloads, $0.source.info)
                < ($1.status, -$1.recent, -$1.tally.firstDownloads, $1.source.info)
        }
        places = items.filter { !$0.profile.isPassage }
        passages = items.filter { $0.profile.isPassage }
        self.ledger = ledger
    }

    /// 알릴 것 — 새로 링크했거나 급증한 곳. 통로는 알리지 않는다.
    var alerts: [Item] { places.filter(\.status.isAlert) }

    /// 한 줄 판정.
    var headline: String {
        let new = places.filter { $0.status == .new }
        let surging = places.filter { $0.status == .surging }
        if new.isEmpty && surging.isEmpty {
            if places.isEmpty { return "이름이 드러난 링크 출처가 아직 없습니다." }
            let active = places.filter { $0.status == .steady }.count
            return active > 0
                ? "최근 \(Self.recentDays)일에 새로 링크한 곳은 없습니다. \(active)곳이 꾸준히 보내고 있어요."
                : "최근 \(Self.recentDays)일엔 링크로 온 사람이 없습니다. 그 전에 \(places.count)곳이 보냈어요."
        }
        var parts: [String] = []
        if !new.isEmpty { parts.append("새로 링크한 곳 \(new.count)곳(\(new.prefix(3).map(\.profile.name).joined(separator: " · ")))") }
        if !surging.isEmpty { parts.append("갑자기 늘어난 곳 \(surging.count)곳(\(surging.prefix(3).map(\.profile.name).joined(separator: " · ")))") }
        return "최근 \(Self.recentDays)일에 " + parts.joined(separator: ", ") + "이 있습니다."
    }
}

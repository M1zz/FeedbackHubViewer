//
//  ProjectStatsSpec+Dashboard.swift
//  FeedbackHubViewer
//
//  앱마다 다른 대시보드를 **스펙만으로** 구성하기 위한 층.
//
//  왜 이 층이 필요한가. 앱이 늘수록 보고 싶은 것은 갈라진다 — ClipKeyboard는
//  키보드에 닿은 비율과 무료 한도까지의 거리를 보고, 두번알림은 알림 개수 수요와
//  체험 잔여를 본다. 그런데 예전 구조는 **카드의 종류도, 차례도, 묶음도 Swift에
//  박혀 있었다.** `tileGroups`를 먼저 그리고 그 다음 `distributions`… 하는 식이라
//  앱이 자기 화면의 순서를 정할 수 없었고, 새 종류를 더하려면 스펙·평가·뷰 세
//  파일을 함께 고쳐야 했다.
//
//  그래서 카드를 **한 줄로 세운다**:
//
//      "cards": [
//        { "kind": "ladder", "section": "수익", "title": "활성화 사다리", ... },
//        { "kind": "wall",   "section": "수익", "title": "잠재 결제 고객", ... },
//        { "kind": "tiles",  "title": "키보드 사용량", ... }
//      ]
//
//  적은 차례가 그리는 차례이고, `section`이 같은 카드끼리 묶인다. 종류마다 필요한
//  입력이 다르지만 그건 `Context` 자루가 이미 다 들고 있으므로, 앱은
//  무엇을 어디에 둘지만 고르면 된다.
//
//  ── 옛 스펙을 안 고쳐도 되는 이유 ──
//
//  `cards`가 없으면 옛 절들(`tileGroups` · `distributions` · `shares` ·
//  `segments` · `funnels` · `monetization`)을 지금까지의 차례 그대로 풀어 쓴다.
//  즉 옛 절은 **짧게 쓰는 법**이지 다른 기능이 아니다. 두 길이 같은 곳으로
//  모이므로 화면 코드에는 분기가 하나도 안 생긴다.
//
//  ── 새 종류를 더하는 법 (세 곳, 전부 한 줄~한 함수) ──
//
//   1. 이 파일에 스펙 타입과 `DashboardCardSpec`의 case 하나
//   2. `ProjectStatsSpec+Evaluation.swift`에 `…Insight(_:in:)` 함수 하나와
//      `build(_:in:)`의 분기 한 줄
//   3. 그 카드가 `tiles`·`bars`·`funnel` 중 하나로 그려지면 **뷰는 안 고친다**
//
//  3번이 이 구조의 요점이다. 카드 종류는 늘어나도 그리는 모양은 안 늘린다 —
//  앱마다 모양이 달라지면 두 앱을 나란히 못 읽는다.
//

import Foundation

// MARK: - 카드 한 장

extension ProjectStatsSpec {

    /// 대시보드에 놓을 카드 한 장. `kind`로 갈린다.
    enum DashboardCardSpec {
        case tiles(TileGroupSpec)
        case distribution(DistributionSpec)
        case share(ShareSpec)
        case segments(SegmentSpec)
        case funnel(FunnelSpec)
        case ladder(LadderSpec)
        case wall(WallSpec)
        case moments(MomentsSpec)
    }

    /// `cards` 배열 한 칸을 읽는다. 모르는 `kind`는 **조용히 버리지 않고**
    /// 오류를 낸다 — 오타 하나로 카드가 소리 없이 사라지면, 화면이 빈 이유를
    /// 찾는 데 스펙을 한 줄씩 지워 보는 수밖에 없다.
    enum CardKind: String, Decodable {
        case tiles, distribution, share, segments, funnel, ladder, wall, moments
    }

    /// 모든 카드 스펙이 함께 갖는 겉 정보. 타입마다 따로 적지 않게 모아 둔다.
    struct CardChrome: Decodable {
        let title: String
        var note: String?
        /// SF Symbol. 안 적으면 그 종류의 기본 아이콘.
        var icon: String?
        /// 같은 이름끼리 한 묶음으로 그려진다. 안 적으면 안 묶인다.
        var section: String?
    }

    /// 이 앱이 그릴 카드를 차례대로.
    ///
    /// `cards`를 적었으면 그것이 전부다(옛 절은 그때 무시된다 — 두 벌이 섞이면
    /// 같은 카드가 두 번 그려진다). 안 적었으면 옛 절을 지금까지의 차례로 푼다.
    var cards: [DashboardCardSpec] {
        if !declaredCards.isEmpty { return declaredCards }
        var result: [DashboardCardSpec] = []
        // 수익 절이 맨 앞인 이유: 쐐기에 닿은 사람 수는 다른 어떤 숫자보다
        // 먼저 읽혀야 한다. 가치를 못 받은 사람에게는 어떤 값도 비싸다.
        if let money = monetization {
            if let ladder = money.ladder { result.append(.ladder(ladder)) }
            if let wall = money.wallCard { result.append(.wall(wall)) }
            if let moments = money.momentsCard { result.append(.moments(moments)) }
        }
        result += tileGroups.map(DashboardCardSpec.tiles)
        result += distributions.map(DashboardCardSpec.distribution)
        result += shares.map(DashboardCardSpec.share)
        if let segments { result.append(.segments(segments)) }
        result += funnels.map(DashboardCardSpec.funnel)
        return result
    }
}

// MARK: - 종류별 스펙

extension ProjectStatsSpec {

    /// 설치에서 **가치를 받은 상태**까지 가는 사다리.
    struct LadderSpec: Decodable {
        var chrome: CardChrome
        /// 이 앱이 목표로 삼은 마지막 칸 도달률(0~1).
        var target: Double?
        /// 이 밑이면 가격이 아니라 제품 문제라고 그 앱이 정해 둔 선(0~1).
        var floor: Double?
        let steps: [Step]

        /// 한 칸. `metric`이 없으면 "설치 전부"(첫 칸).
        struct Step: Decodable {
            let label: String
            var metric: String?
            /// 이 값 이상이면 이 칸에 든다. 기본 1 — 0/1 플래그를 그냥 쓸 수 있게.
            var atLeast: Double?
            var hint: String?
        }

        enum CodingKeys: String, CodingKey { case target, floor, steps }
        init(from decoder: Decoder) throws {
            chrome = try CardChrome(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            target = try c.decodeIfPresent(Double.self, forKey: .target)
            floor = try c.decodeIfPresent(Double.self, forKey: .floor)
            steps = try c.decode([Step].self, forKey: .steps)
        }
    }

    /// 무료로 쓸 수 있는 한도와, 거기까지의 거리.
    struct WallSpec: Decodable {
        var chrome: CardChrome
        /// 사람이 읽는 한도의 이름 — "단축어", "알림".
        let label: String
        /// 한도를 재는 스냅샷 지표.
        let metric: String
        /// 무료로 가질 수 있는 최대 개수. 이 수까지는 무료다.
        let limit: Int
        /// 한도에서 몇 칸 안쪽부터 "곧 막힌다"로 볼 것인가. 기본 1.
        var nearBy: Int?

        enum CodingKeys: String, CodingKey { case label, metric, limit, nearBy }
        init(from decoder: Decoder) throws {
            chrome = try CardChrome(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            metric = try c.decode(String.self, forKey: .metric)
            limit = try c.decode(Int.self, forKey: .limit)
            nearBy = try c.decodeIfPresent(Int.self, forKey: .nearBy)
        }
    }

    /// 결제 화면이 뜨기로 설계된 자리들.
    struct MomentsSpec: Decodable {
        var chrome: CardChrome
        let moments: [Moment]
        /// 자리마다 "눌렀다 · 냈다"를 셀 때 쓸 이벤트 기본형.
        var tappedEvent: String?
        var purchasedEvent: String?

        struct Moment: Decodable {
            let label: String
            /// 노출 이벤트. 슬라이스까지 적으면 그 슬라이스만 센다.
            let event: String
            var note: String?
        }

        init(chrome: CardChrome, moments: [Moment],
             tappedEvent: String?, purchasedEvent: String?) {
            self.chrome = chrome
            self.moments = moments
            self.tappedEvent = tappedEvent
            self.purchasedEvent = purchasedEvent
        }

        enum CodingKeys: String, CodingKey { case moments, tappedEvent, purchasedEvent }
        init(from decoder: Decoder) throws {
            chrome = try CardChrome(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            moments = try c.decode([Moment].self, forKey: .moments)
            tappedEvent = try c.decodeIfPresent(String.self, forKey: .tappedEvent)
            purchasedEvent = try c.decodeIfPresent(String.self, forKey: .purchasedEvent)
        }
    }
}

// MARK: - 겉 정보 꺼내기

/// 모든 카드 스펙이 자기 `Frame`을 만들 수 있게 하는 한 가지 통로.
/// 종류를 더할 때 화면 코드가 아니라 여기에만 한 줄이 는다.
protocol DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { get }
}

extension DashboardCardShaped {
    func frame(default icon: String) -> ProjectStatsSpec.Insight.Frame {
        .init(title: chrome.title, note: chrome.note,
              icon: chrome.icon ?? icon, section: chrome.section)
    }
}

/// 겉 정보를 **고쳐 쓸 수 있는** 카드. 옛 절을 풀 때 묶음 이름을 찍어 주려면
/// 필요하다(옛 절에는 `section`을 적을 자리가 없다).
protocol DashboardCardStamped: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { get set }
}

extension ProjectStatsSpec.LadderSpec: DashboardCardStamped {}
extension ProjectStatsSpec.WallSpec: DashboardCardStamped {}
extension ProjectStatsSpec.MomentsSpec: DashboardCardStamped {}

// 옛 절들은 `chrome`을 따로 안 들고 있으므로 자기 필드에서 만들어 준다.
// 이 네 줄이 "옛 스펙을 한 글자도 안 고쳐도 된다"의 값이다.
extension ProjectStatsSpec.TileGroupSpec: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { .init(title: title, note: note, icon: icon, section: section) }
}
extension ProjectStatsSpec.DistributionSpec: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { .init(title: title, note: note, icon: icon, section: section) }
}
extension ProjectStatsSpec.ShareSpec: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { .init(title: title, note: note, icon: icon, section: section) }
}
extension ProjectStatsSpec.SegmentSpec: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { .init(title: title, note: note, icon: icon, section: section) }
}
extension ProjectStatsSpec.FunnelSpec: DashboardCardShaped {
    var chrome: ProjectStatsSpec.CardChrome { .init(title: title, note: note, icon: icon, section: section) }
}

// MARK: - `cards` 읽기

extension ProjectStatsSpec.DashboardCardSpec: Decodable {
    private enum Key: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Key.self)
            .decode(ProjectStatsSpec.CardKind.self, forKey: .kind)
        // 같은 컨테이너를 종류에 맞는 타입으로 한 번 더 읽는다. 겉 정보(title ·
        // note · icon · section)는 어느 종류든 같은 자리에 있으므로 `CardChrome`이
        // 가져가고, 나머지는 종류마다의 필드가 가져간다.
        switch kind {
        case .tiles:        self = .tiles(try .init(from: decoder))
        case .distribution: self = .distribution(try .init(from: decoder))
        case .share:        self = .share(try .init(from: decoder))
        case .segments:     self = .segments(try .init(from: decoder))
        case .funnel:       self = .funnel(try .init(from: decoder))
        case .ladder:       self = .ladder(try .init(from: decoder))
        case .wall:         self = .wall(try .init(from: decoder))
        case .moments:      self = .moments(try .init(from: decoder))
        }
    }
}

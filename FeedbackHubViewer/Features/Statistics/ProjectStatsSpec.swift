//
//  ProjectStatsSpec.swift
//  FeedbackHubViewer
//
//  각 앱이 자기 통계 화면에서 쓰는 어휘와 해석을, 뷰어가 그대로 쓸 수 있게 담은 스펙.
//
//  왜 필요한가: 허브가 받는 데이터(UsageSnapshot의 `metrics`, UsageEvent 이름)는 앱마다
//  뜻이 다르다. `shortcuts`는 ClipKeyboard의 단축어 수이고 `alertsMax`는 두번알림의
//  알림 개수 수요다. 무료 한도 10개·알림 1개 같은 경계도 그 앱에서만 뜻이 있다.
//  뷰어가 이걸 모르면 키 원문과 평균값만 늘어놓게 된다.
//
//  왜 JSON인가: 지표를 만드는 곳은 앱이다. 스펙 원본은 각 앱 리포의
//  `docs/usage-spec.json`에 두고(지표를 추가하는 커밋에서 라벨도 같이 쓰게 된다),
//  `scripts/sync-stats-specs.sh`로 여기 `Specs/`에 복사해 온다. 계산식이 아니라
//  **경계값과 규칙**만 데이터로 적으므로, 앱이 지표를 늘려도 뷰어 코드는 그대로다.
//
//  ⚠️ 스펙에 없는 키는 절대 감추지 않는다. 원문 그대로 계속 보여주고, 화면에는
//     "스펙에 없는 지표"로 모아 알린다 — 드리프트가 조용히 사라지는 대신 할 일이 된다.
//

import Foundation

// MARK: - Spec

struct ProjectStatsSpec: Decodable {
    /// 이 파일이 따르는 스키마 버전. 뷰어가 모르는 버전이면 무시하고 일반 화면으로 떨어진다.
    let specVersion: Int
    /// 이 앱의 CloudKit `appId`. 프로젝트 키와 맞춰 스펙을 고른다.
    let appId: String
    /// 사람이 읽는 이름. `appId` 대신 이 이름으로 기록된 프로젝트도 같은 스펙을 쓴다.
    let appName: String?
    /// 스냅샷 `metrics` 키 → 화면 라벨.
    var metricLabels: [String: MetricLabel] = [:]
    /// 접두사로 붙는 동적 키(`persona.memo`, `flag.ownsWatch`)의 라벨.
    var metricPrefixLabels: [String: String] = [:]
    /// 이벤트 이름 → 화면 라벨. 슬라이스(`paywall_view:memo`)는 앞부분만 맞춘다.
    var eventLabels: [String: String] = [:]
    /// 이 앱에서 제일 먼저 볼 숫자들. 여러 묶음을 둘 수 있다.
    var tileGroups: [TileGroupSpec] = []
    /// 설치를 어떤 지표의 구간으로 나눈 분포.
    var distributions: [DistributionSpec] = []
    /// 합이 전체인 몫(도넛/막대) — 종류별 비중.
    var shares: [ShareSpec] = []
    /// 규칙에서 이름으로 쓸 파생값.
    var derived: [DerivedSpec] = []
    /// 설치 하나하나를 무리로 나누는 규칙.
    var segments: SegmentSpec?
    /// 이벤트를 순서대로 세워 단계별로 몇이 남는지 본다(페이월 → 결제).
    var funnels: [FunnelSpec] = []
    /// 이 앱이 **어떻게 돈을 버는가**를 관측하는 절. 없으면 수익 카드가 안 뜬다.
    var monetization: MonetizationSpec?
    /// 그릴 카드를 차례대로 직접 적은 것. 적었으면 이게 전부이고, 위의 절들은
    /// 그때 안 쓰인다(두 벌이 섞이면 같은 카드가 두 번 그려진다).
    /// 화면이 쓰는 최종 목록은 `cards`다 — `ProjectStatsSpec+Dashboard.swift`.
    var declaredCards: [DashboardCardSpec] = []
    /// 이 앱에서 **지금 유료 기능을 쓸 수 있는 사람**을 뜻하는 0/1 플래그 키.
    ///
    /// 규약 이름은 `flag.hasAccess`. 이게 이 화면의 큰 숫자다 — 거의 모든 앱이
    /// 이미 이 값을 보내고 있기 때문이다. 안 적고 `flag.hasAccess`도 안 보내면
    /// 흔한 이름들로 찾는데(`FeedbackStore.accessFlagCandidates`), `flag.isPro`
    /// 같은 옛 이름이 실제로 재고 있던 값이 바로 이것이라 그 추측은 대개 맞다.
    /// 아래 `paidFlag`가 있으면 그것도 접근의 근거가 되므로, 셋 중 하나라도
    /// 켜져 있으면 열린 것으로 본다.
    var accessFlag: String?

    /// 이 앱에서 **지금 유효한 결제가 있는 사람**을 뜻하는 0/1 플래그 키.
    ///
    /// 규약 이름은 `flag.isPaid`이고, 그 이름으로 보내면 안 적어도 알아본다.
    /// 다른 이름을 쓴다면 여기 적어야 한다. 둘 다 없으면 흔한 이름들로 추측하는데
    /// 위 `accessFlag`와 달리 **추측하지 않는다.** `flag.isPro` 같은 옛 이름은
    /// 실무에서 대개 결제가 아니라 접근 권한을 뜻하므로, 결제 자리에 넣으면
    /// 유료가 부풀기 때문이다. 그 이름들은 전부 접근 쪽으로 간다.
    ///
    /// ⚠️ 여기에 "기능이 열려 있는가"를 넣지 말 것. 한 앱이 그랬다가 신규 설치의
    ///    99%가 유료로 기록됐다 — 결제 ∪ 그랜드파더 ∪ 체험을 한 값에 담았기
    ///    때문이다. 그런 것들은 아래 두 줄로 따로 보낸다.
    var paidFlag: String?

    /// 체험 기간 중인 설치를 뜻하는 0/1 플래그 키. 규약 이름은 `flag.isTrial`.
    /// 아직 돈을 안 낸 사람이라 유료에 섞이면 매출로 읽힌다.
    var trialFlag: String?

    /// 돈을 안 내고 접근이 열린 설치 — 그랜드파더·가족 공유·내부
    /// 테스터. 규약 이름은 `flag.isComped`. 영구 면제라 전환 대상이 아니다.
    var compedFlag: String?

    /// 유료 기능을 **열지 않는** 작은 결제(칸 추가·기기 추가 같은 것)를 한 설치를 뜻하는
    /// 0/1 플래그 키. 규약 이름은 `flag.boughtAddOn`. 접근의 근거가 아니고, 결제 축에서
    /// 돈을 낸 사람을 "안 냄"과 가르는 데만 쓴다.
    var addOnFlag: String?

    /// 결제가 켜진 설치 중 **앱이 유료 다운로드였던 시절에 산** 설치를 뜻하는 0/1 플래그 키.
    /// 규약 이름은 `flag.isLegacyPaid`. 돈은 냈지만 지금의 인앱 결제와 무관해서, 결제 축에서
    /// Pro 결제와 가른다 — 섞이면 매출과 대조할 때 전환율이 부푼다.
    var legacyPaidFlag: String?

    static let supportedVersion = 1

    // 합성된 Decodable은 기본값이 있는 프로퍼티라도 키가 없으면 실패한다. 스펙은 앱마다
    // 쓰는 절(節)이 달라서(어떤 앱은 `shares`가 없고 어떤 앱은 `derived`가 없다) 빠진
    // 절은 빈 값으로 읽어야 한다.
    enum CodingKeys: String, CodingKey {
        case specVersion, appId, appName, metricLabels, metricPrefixLabels
        case eventLabels, tileGroups, distributions, shares, derived, segments, funnels
        case accessFlag, paidFlag, trialFlag, compedFlag, addOnFlag, legacyPaidFlag
        case monetization
        case cards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specVersion = try c.decode(Int.self, forKey: .specVersion)
        appId = try c.decode(String.self, forKey: .appId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        metricLabels = try c.decodeIfPresent([String: MetricLabel].self, forKey: .metricLabels) ?? [:]
        metricPrefixLabels = try c.decodeIfPresent([String: String].self, forKey: .metricPrefixLabels) ?? [:]
        eventLabels = try c.decodeIfPresent([String: String].self, forKey: .eventLabels) ?? [:]
        tileGroups = try c.decodeIfPresent([TileGroupSpec].self, forKey: .tileGroups) ?? []
        distributions = try c.decodeIfPresent([DistributionSpec].self, forKey: .distributions) ?? []
        shares = try c.decodeIfPresent([ShareSpec].self, forKey: .shares) ?? []
        derived = try c.decodeIfPresent([DerivedSpec].self, forKey: .derived) ?? []
        segments = try c.decodeIfPresent(SegmentSpec.self, forKey: .segments)
        funnels = try c.decodeIfPresent([FunnelSpec].self, forKey: .funnels) ?? []
        monetization = try c.decodeIfPresent(MonetizationSpec.self, forKey: .monetization)
        declaredCards = try c.decodeIfPresent([DashboardCardSpec].self, forKey: .cards) ?? []
        accessFlag = try c.decodeIfPresent(String.self, forKey: .accessFlag)
        paidFlag = try c.decodeIfPresent(String.self, forKey: .paidFlag)
        trialFlag = try c.decodeIfPresent(String.self, forKey: .trialFlag)
        compedFlag = try c.decodeIfPresent(String.self, forKey: .compedFlag)
        addOnFlag = try c.decodeIfPresent(String.self, forKey: .addOnFlag)
        legacyPaidFlag = try c.decodeIfPresent(String.self, forKey: .legacyPaidFlag)
    }

    struct MetricLabel: Decodable {
        let label: String
        /// "분", "개" 같은 꼬리. 없으면 붙이지 않는다.
        var unit: String?
        /// 이 지표를 "설치당 평균"에 넣지 않는다(플래그·최대값처럼 평균이 뜻 없는 값).
        var excludeFromAverages: Bool?
    }

    struct TileGroupSpec: Decodable {
        /// 카드 겉 정보. 안 적으면 그 종류의 기본 아이콘을 쓰고, 안 묶인다.
        var icon: String?
        var section: String?
        let title: String
        var note: String?
        let tiles: [TileSpec]
    }

    struct TileSpec: Decodable {
        let label: String
        let kind: Kind
        /// `kind`가 쓰는 지표 키.
        var metric: String?
        /// `sumPerMatchingInstall`에서 "어떤 설치를 셀지" 고르는 플래그 키.
        var condition: String?
        /// `kind == .segment`일 때 셀 무리 이름.
        var segment: String?
        var unit: String?
        var format: Format?
        var hint: String?

        enum Kind: String, Decodable {
            /// 이 지표가 0보다 큰 설치 수(그리고 전체 대비 비율).
            case installsWithMetric
            /// 모든 설치의 합계.
            case sum
            /// 설치당 평균.
            case average
            /// `condition` 플래그가 켜진 설치들만 놓고 본 `metric` 평균.
            case sumPerMatchingInstall
            /// 두 지표의 비율(metric ÷ condition).
            case ratio
            /// `segments` 규칙에서 이 이름으로 분류된 설치 수.
            case segment
        }

        enum Format: String, Decodable {
            case integer, decimal1, percent, countAndPercent
        }
    }

    struct DistributionSpec: Decodable {
        /// 카드 겉 정보. 안 적으면 그 종류의 기본 아이콘을 쓰고, 안 묶인다.
        var icon: String?
        var section: String?
        let title: String
        let metric: String
        var note: String?
        let buckets: [Bucket]

        struct Bucket: Decodable {
            let label: String
            let from: Double
            /// 없으면 위로 열린 구간.
            var to: Double?
        }
    }

    struct ShareSpec: Decodable {
        /// 카드 겉 정보. 안 적으면 그 종류의 기본 아이콘을 쓰고, 안 묶인다.
        var icon: String?
        var section: String?
        let title: String
        var note: String?
        let parts: [Part]

        struct Part: Decodable {
            let label: String
            let metric: String
        }
    }

    /// 수익 설계를 관측하는 절. **짧게 쓰는 법**이지 다른 기능이 아니다 —
    /// `cards`에 `ladder`·`wall`·`moments` 세 장을 직접 적은 것과 같은 곳으로
    /// 모인다(`ProjectStatsSpec+Dashboard.swift`).
    ///
    /// 가격은 여기 안 적는다. 값은 App Store Connect가 진실이고 뷰어가 받는 것은
    /// 설치가 보낸 지표와 이벤트뿐이라, 적어 봤자 대조할 상대가 없다. 여기 적는
    /// 것은 **값을 정당화하거나 무너뜨리는 세 가지 사실**이다.
    struct MonetizationSpec: Decodable {
        var note: String?
        /// 쐐기에 닿는 사람이 몇인가. 가격표보다 먼저 봐야 할 숫자다.
        var activation: LadderSpec?
        /// 값을 낼 이유가 생긴 사람이 몇인가.
        var wall: WallSpec?
        /// 설계한 벽이 실제로 섰는가.
        var moments: [MomentsSpec.Moment] = []
        var tappedEvent: String?
        var purchasedEvent: String?

        /// 이 절에서 나오는 카드 셋. 전부 "수익" 묶음에 들어간다.
        var ladder: LadderSpec? { activation.map { stamped($0) } }
        var wallCard: WallSpec? { wall.map { stamped($0) } }
        var momentsCard: MomentsSpec? {
            guard !moments.isEmpty else { return nil }
            return stamped(MomentsSpec(
                chrome: .init(title: "결제 화면이 뜬 순간", note: note, section: Self.section),
                moments: moments, tappedEvent: tappedEvent, purchasedEvent: purchasedEvent))
        }

        static let section = "수익"
        /// 묶음 이름을 안 적었으면 "수익"으로 찍어 준다. 적었으면 그대로 둔다 —
        /// 앱이 자기 화면을 다르게 묶고 싶을 수 있다.
        private func stamped<T: DashboardCardStamped>(_ card: T) -> T {
            var copy = card
            if copy.chrome.section == nil { copy.chrome.section = Self.section }
            return copy
        }

        enum CodingKeys: String, CodingKey {
            case note, activation, wall, moments, tappedEvent, purchasedEvent
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            activation = try c.decodeIfPresent(LadderSpec.self, forKey: .activation)
            wall = try c.decodeIfPresent(WallSpec.self, forKey: .wall)
            moments = try c.decodeIfPresent([MomentsSpec.Moment].self, forKey: .moments) ?? []
            tappedEvent = try c.decodeIfPresent(String.self, forKey: .tappedEvent)
            purchasedEvent = try c.decodeIfPresent(String.self, forKey: .purchasedEvent)
        }
    }

    struct DerivedSpec: Decodable {
        let name: String
        let kind: Kind
        /// `choose`: 이 플래그가 켜져 있으면 `whenSet`, 아니면 `whenUnset`.
        var flag: String?
        var whenSet: Double?
        var whenUnset: Double?
        /// `difference`: `from` - `subtract` (0 아래로는 내려가지 않는다).
        var from: String?
        var subtract: String?
        /// `anyAbove`: 하나라도 참이면 1.
        var terms: [Condition]?

        enum Kind: String, Decodable {
            case choose, difference, anyAbove
        }
    }

    struct SegmentSpec: Decodable {
        /// 카드 겉 정보. 안 적으면 그 종류의 기본 아이콘을 쓰고, 안 묶인다.
        var icon: String?
        var section: String?
        let title: String
        var note: String?
        /// 위에서부터 처음 걸리는 규칙 하나로 정해진다 — 그래야 한 설치가 한 무리에만
        /// 속하고 합이 전체와 맞는다.
        let rules: [Rule]

        struct Rule: Decodable {
            let name: String
            var hint: String?
            /// 모두 참이어야 이 무리다. 비어 있으면 "나머지 전부".
            var when: [Condition]

            enum CodingKeys: String, CodingKey { case name, hint, when }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                hint = try c.decodeIfPresent(String.self, forKey: .hint)
                when = try c.decodeIfPresent([Condition].self, forKey: .when) ?? []
            }
        }
    }

    /// 이벤트를 순서대로 세운 퍼널. 다른 절과 달리 스냅샷 `metrics`가 아니라
    /// **이벤트 집계**를 읽는다 — 결제는 설치에 남는 상태가 아니라 일어난 일이다.
    ///
    /// 단계는 이벤트의 **기본형**으로 적는다. 앱이 슬라이스를 붙여 보내면
    /// (`paywall_cta_tapped:buy`, `:memo`) 같은 기본형끼리 합쳐서 한 단계로 센다.
    struct FunnelSpec: Decodable {
        /// 카드 겉 정보. 안 적으면 그 종류의 기본 아이콘을 쓰고, 안 묶인다.
        var icon: String?
        var section: String?
        let title: String
        var note: String?
        /// 무엇을 셀지. 기본은 `installs` — "몇 명이 여기까지 왔나"가 전환율이고,
        /// 건수는 한 사람이 페이월을 열 번 봐도 열로 세어 비율을 부풀린다.
        var basis: Basis?
        let steps: [Step]

        enum Basis: String, Decodable { case installs, events }

        struct Step: Decodable {
            let label: String
            /// 이벤트 기본형 하나.
            var event: String?
            /// 여러 이름을 한 단계로 묶을 때(`purchase_cancelled` + `purchase_failed`).
            var anyOf: [String]?
            var hint: String?

            var names: [String] {
                if let anyOf, !anyOf.isEmpty { return anyOf }
                return event.map { [$0] } ?? []
            }
        }
    }

    /// 값 하나를 읽어 비교하는 조건. 값은 지표 키 하나, 여러 키의 합, 두 키의 비율,
    /// 또는 `derived`가 정의한 이름이다.
    struct Condition: Decodable {
        var metric: String?
        var sum: [String]?
        /// [분자, 분모]. 분모가 0이면 0으로 본다.
        var ratio: [String]?
        var derived: String?

        var lt: Double?
        var lte: Double?
        var gt: Double?
        var gte: Double?
        var eq: Double?
    }
}

// MARK: - Catalog

/// 번들에 들어 있는 앱별 스펙 전부. 앱을 켜는 동안 한 번만 읽는다.
enum ProjectStatsSpecCatalog {

    private static var all: [ProjectStatsSpec] { loaded.specs }

    /// 이 프로젝트 키에 맞는 스펙. `appId`로 먼저 찾고, 이름으로 기록된 프로젝트도 받는다.
    static func spec(for projectKey: String) -> ProjectStatsSpec? {
        all.first { $0.appId == projectKey }
            ?? all.first { $0.appName == projectKey }
    }

    /// 읽다가 **실패한** 스펙 — 파일 이름과 그 이유.
    ///
    /// 왜 남기는가: 예전에는 `try?` 하나로 조용히 버렸다. 스펙이 커질수록(카드
    /// 종류·묶음·수익 절) 오타 한 글자로 그 앱의 대시보드가 통째로 사라지는데,
    /// 화면에는 "스펙이 아직 없습니다"가 떠서 **없는 것과 깨진 것이 같아 보인다.**
    /// 둘은 할 일이 정반대다 — 하나는 쓰는 것이고 하나는 고치는 것이다.
    static let failures: [Failure] = loaded.failures

    struct Failure: Identifiable {
        let file: String
        let reason: String
        var id: String { file }
    }

    private static let loaded = load()

    private static func load() -> (specs: [ProjectStatsSpec], failures: [Failure]) {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        var specs: [ProjectStatsSpec] = []
        var failures: [Failure] = []

        for url in urls {
            // 스펙이 아닌 JSON 도 번들에 있다. 그런 파일까지 실패로 세면 경보가
            // 소음이 되므로, `appId` 가 있는 파일만 스펙으로 본다.
            guard let data = try? Data(contentsOf: url),
                  let probe = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  probe["appId"] != nil
            else { continue }

            do {
                let spec = try decoder.decode(ProjectStatsSpec.self, from: data)
                guard spec.specVersion == ProjectStatsSpec.supportedVersion else {
                    failures.append(.init(file: url.lastPathComponent,
                                          reason: "이 뷰어가 모르는 specVersion \(spec.specVersion)입니다 "
                                                + "(아는 것은 \(ProjectStatsSpec.supportedVersion))."))
                    continue
                }
                specs.append(spec)
            } catch {
                failures.append(.init(file: url.lastPathComponent, reason: Self.explain(error)))
            }
        }
        return (specs, failures)
    }

    /// 디코딩 오류를 고칠 수 있는 말로. 경로가 있어야 스펙의 **어느 줄**인지 안다.
    private static func explain(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: " → ")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "\(path(context)) 에 \"\(key.stringValue)\" 가 없습니다."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context)) 의 값이 기대한 모양이 아닙니다. \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

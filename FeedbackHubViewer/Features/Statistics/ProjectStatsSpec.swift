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

    static let supportedVersion = 1

    // 합성된 Decodable은 기본값이 있는 프로퍼티라도 키가 없으면 실패한다. 스펙은 앱마다
    // 쓰는 절(節)이 달라서(어떤 앱은 `shares`가 없고 어떤 앱은 `derived`가 없다) 빠진
    // 절은 빈 값으로 읽어야 한다.
    enum CodingKeys: String, CodingKey {
        case specVersion, appId, appName, metricLabels, metricPrefixLabels
        case eventLabels, tileGroups, distributions, shares, derived, segments, funnels
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
    }

    struct MetricLabel: Decodable {
        let label: String
        /// "분", "개" 같은 꼬리. 없으면 붙이지 않는다.
        var unit: String?
        /// 이 지표를 "설치당 평균"에 넣지 않는다(플래그·최대값처럼 평균이 뜻 없는 값).
        var excludeFromAverages: Bool?
    }

    struct TileGroupSpec: Decodable {
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
        let title: String
        var note: String?
        let parts: [Part]

        struct Part: Decodable {
            let label: String
            let metric: String
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

    private static let all: [ProjectStatsSpec] = load()

    /// 이 프로젝트 키에 맞는 스펙. `appId`로 먼저 찾고, 이름으로 기록된 프로젝트도 받는다.
    static func spec(for projectKey: String) -> ProjectStatsSpec? {
        all.first { $0.appId == projectKey }
            ?? all.first { $0.appName == projectKey }
    }

    private static func load() -> [ProjectStatsSpec] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let spec = try? decoder.decode(ProjectStatsSpec.self, from: data),
                  spec.specVersion == ProjectStatsSpec.supportedVersion
            else { return nil }
            return spec
        }
    }
}

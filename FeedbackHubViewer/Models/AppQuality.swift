//
//  AppQuality.swift
//  FeedbackHubViewer
//
//  앱 하나의 서비스 품질 — "잘 팔리나" 가 아니라 "쓰는 사람이 겪는 것이 멀쩡한가".
//
//  틀은 ISO/IEC 25010(소프트웨어 제품 품질 모델)의 특성 중 허브가 숫자를 가진 것만 고른다.
//  문턱은 공개된 기준이 있으면 그것을, 없으면 그렇다고 적고 허브 기준을 쓴다.
//
//    안정성   (25010 신뢰성)        크래시 없는 설치 비율
//             좋음 ≥ 99%            Instabug 안정성 보고서 권장(crash-free users > 99%)
//             나쁨 < 98.91%         Google Play Android vitals "나쁜 동작" 문턱 — 사용자 체감 크래시율 1.09%
//    실행 속도 (25010 성능 효율성)   첫 화면까지 걸린 시간(MetricKit, 가운데 값)
//             좋음 ≤ 400ms          Apple WWDC19 "Optimizing App Launch" 의 목표
//             나쁨 ≥ 5s             Google Play Android vitals "과도한 콜드 스타트"
//    멈춤     (25010 성능 효율성)    앞에 떠 있던 한 시간에 멈춘 초(Xcode Organizer 의 hang rate)
//             좋음 < 1초 · 나쁨 ≥ 5초  Apple 은 문턱을 공개하지 않는다 — 허브 기준
//    만족도   (25010 사용 품질)      App Store 평균 별점
//             좋음 ≥ 4.5 · 나쁨 < 4.0  업계 관례(4점 아래는 받기 전환이 크게 떨어진다)
//    지원 응답 (서비스 품질)          3일 넘은 피드백 중 처리(반영 · 답장)한 몫
//             좋음 ≥ 90% · 나쁨 < 50%  공인 기준 없음 — 허브 기준
//    기기 테스트 (25010 기능 적합성)  연결한 아이폰에서 단위 · UI 테스트와 설치하고 켜 보기
//             좋음 켜지고 실패 0 · 나쁨 못 켜짐이나 실패 1개 이상 · 주의 빌드 못 함  허브 기준
//    핵심 기능 (25010 기능 적합성)   가장 새 버전에서도 핵심 행동이 오는가(릴리즈 건강의 핵심 행동률)
//             나쁨 앞 버전에선 오던 것이 0명 — 우연일 확률 5% 미만  ·  주의 앞 버전보다 문턱(기본 20%) 넘게 줄었다
//             허브 기준(릴리즈 건강과 같은 문턱)
//    온보딩   (25010 사용 품질)      지난 30일 새 설치 중 온보딩을 끝내거나 건너뛰고 들어온 몫
//             좋음 ≥ 80% · 나쁨 < 50%  공인 기준 없음 — 허브 기준
//    커버리지 (25010 유지보수성)     앱 · 확장 코드의 줄 커버리지(가장 새 xcresult)
//             좋음 ≥ 75% · 나쁨 < 60%  Google Testing Blog "Code Coverage Best Practices"(2020):
//                                      60% 받아들일 만 · 75% 칭찬할 만 · 90% 모범
//
//  모르는 것은 nil 이다. 표본이 모자라면 "데이터 없음" 이지 0 이나 100% 가 아니다.
//  종합은 가장 나쁜 항목을 따른다 — 평균을 내면 크래시 나는 앱이 별점으로 가려진다.
//
//  판정은 화면과 떨어진 순수 함수다 — 같은 숫자면 같은 말이 나온다.
//

import Foundation

struct AppQuality: Identifiable {

    // MARK: - 기준

    enum Standard {
        static let crashFreeGood = 0.99
        static let crashFreeBad = 1 - 0.0109
        static let launchGoodMs = 400.0
        static let launchBadMs = 5_000.0
        static let hangGood = 1.0
        static let hangBad = 5.0
        static let ratingGood = 4.5
        static let ratingBad = 4.0
        static let supportGood = 0.9
        static let supportBad = 0.5
        static let onboardingGood = 0.8
        static let onboardingBad = 0.5
        static let coverageGood = 0.75
        static let coverageBad = 0.6
        /// 핵심 행동이 0명이 된 것을 우연이 아니라고 볼 문턱.
        static let coreSilenceChance = 0.05

        /// 이보다 적은 표본으로는 판정하지 않는다.
        static let minRatings = 5
        static let minFeedback = 3
        static let minNewInstalls = 10
    }

    // MARK: - 재료

    /// 모르는 것은 nil — 0 과 다르다.
    struct Input {
        var project: String
        var name: String
        /// 크래시 없는 설치 비율과 그 버전.
        var crashFree: Double?
        /// 설치 ID 가 없어 크래시 보고 건수로 어림한 값인가.
        var crashFreeIsEstimate = false
        var crashVersion: String?
        var launchMs: Double?
        var hangPerHour: Double?
        /// 성능 값이 어디서 왔나 — "5.2 버전" · "최근 30일 12대".
        var performanceVersion: String?
        var rating: Double?
        var ratingCount = 0
        /// 별점을 모은 나라 수. 0 이면 한 가게(한국)만 본 값.
        var ratingCountries = 0
        /// 처리한 피드백 · 셈에 든 피드백.
        var supportHandled = 0
        var supportTotal = 0
        /// 허브가 본 7일 활성 — 같은 등급이면 쓰는 사람이 많은 앱부터.
        var active7 = 0
        /// 연결한 아이폰에서 돌린 테스트(`scripts/device-qa.sh`). 안 돌렸으면 nil.
        var deviceTest: DeviceTestResult?
        /// 릴리즈 건강의 버전들(새것부터)과 핵심 행동 이름 · 문턱. 핵심 행동을 안 정했으면 nil.
        var core: Core?
        /// 지난 30일 새 설치의 온보딩. 앱이 온보딩 이벤트를 안 보내면 nil.
        var onboarding: Onboarding?
        /// `scripts/test-coverage.py` 가 모은 커버리지. 안 돌렸으면 nil.
        var coverage: TestCoverage?
    }

    struct Core {
        var label: String
        var versions: [ReleaseHealth.VersionMetrics]
        var dropMax: Double
        var minInstalls: Int
    }

    struct Onboarding: Equatable {
        var newInstalls = 0
        /// 끝냈거나 건너뛰고 앱에 들어온 새 설치.
        var passed = 0
        var skipped = 0
    }

    // MARK: - 판정

    enum Grade: Int, Comparable, CaseIterable, Identifiable {
        case bad, warning, good, unknown
        var id: Int { rawValue }
        static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .good: return "좋음"
            case .warning: return "주의"
            case .bad: return "나쁨"
            case .unknown: return "데이터 없음"
            }
        }
    }

    enum Dimension: String, CaseIterable, Identifiable {
        case stability = "안정성"
        case launch = "실행 속도"
        case hang = "멈춤"
        case rating = "만족도"
        case support = "지원 응답"
        case core = "핵심 기능"
        case onboarding = "온보딩"
        case deviceTest = "기기 테스트"
        case coverage = "커버리지"
        var id: String { rawValue }

        /// 기준 한 줄 — 화면의 각 줄에 작게.
        var standard: String {
            switch self {
            case .stability: return "좋음 99% 이상 · 나쁨 98.91% 아래 (Instabug · Google Play vitals)"
            case .launch: return "좋음 0.4초 이하 · 나쁨 5초 이상 (Apple WWDC19 · Google Play vitals)"
            case .hang: return "시간당 좋음 1초 아래 · 나쁨 5초 이상 (허브 기준, Apple 은 문턱 미공개)"
            case .rating: return "좋음 4.5 이상 · 나쁨 4.0 아래 (업계 관례)"
            case .support: return "좋음 90% 이상 · 나쁨 50% 아래 (허브 기준)"
            case .core: return "앞 버전에선 오던 핵심 행동이 0명이면 나쁨 · 문턱 넘게 줄면 주의 (허브 기준)"
            case .onboarding: return "새 설치 중 좋음 80% 이상 · 나쁨 50% 아래가 통과 (허브 기준)"
            case .deviceTest: return "좋음 켜지고 실패 0 · 나쁨 못 켜짐이나 테스트 실패 · 주의 아이폰용 빌드 못 함 (허브 기준)"
            case .coverage: return "좋음 75% 이상 · 나쁨 60% 아래 (Google Testing Blog 2020)"
            }
        }

        var systemImage: String {
            switch self {
            case .stability: return "bolt.trianglebadge.exclamationmark"
            case .launch: return "timer"
            case .hang: return "hourglass"
            case .rating: return "star"
            case .support: return "bubble.left.and.bubble.right"
            case .core: return "checkmark.seal"
            case .onboarding: return "figure.walk.arrival"
            case .deviceTest: return "iphone.gen3"
            case .coverage: return "checklist"
            }
        }
    }

    struct Score: Identifiable {
        let dimension: Dimension
        let grade: Grade
        /// 화면에 적을 값. 모르면 "데이터 없음".
        let value: String
        /// 값이 어디서 왔나 — "5.2 버전" · "별점 120개".
        let basis: String?
        var id: String { dimension.rawValue }
    }

    let input: Input
    let scores: [Score]
    var id: String { input.project }

    /// 가장 나쁜 항목. 아는 항목이 하나도 없으면 데이터 없음.
    var grade: Grade { scores.map(\.grade).min() ?? .unknown }
    var worst: Score? { scores.filter { $0.grade != .unknown }.min { $0.grade < $1.grade } }
    var badCount: Int { scores.filter { $0.grade == .bad }.count }

    init(_ input: Input) {
        self.input = input
        scores = Dimension.allCases.map { Self.score($0, input) }
    }

    /// 나쁜 앱부터, 같은 등급이면 나쁜 항목이 많은 앱, 쓰는 사람이 많은 앱부터.
    static func rank(_ inputs: [Input]) -> [AppQuality] {
        inputs.map(AppQuality.init).sorted {
            if $0.grade != $1.grade { return $0.grade < $1.grade }
            if $0.badCount != $1.badCount { return $0.badCount > $1.badCount }
            if $0.input.active7 != $1.input.active7 { return $0.input.active7 > $1.input.active7 }
            return $0.input.name < $1.input.name
        }
    }

    static func score(_ dimension: Dimension, _ input: Input) -> Score {
        switch dimension {
        case .stability:
            guard let rate = input.crashFree else { return unknown(dimension) }
            let grade = higherIsBetter(rate, good: Standard.crashFreeGood, bad: Standard.crashFreeBad)
            let version = input.crashVersion.map { "\($0) 버전" }
            let basis = [version, input.crashFreeIsEstimate ? "크래시 보고로 어림" : nil].compactMap { $0 }
            return Score(dimension: dimension, grade: grade, value: String(format: "%.2f%%", rate * 100),
                         basis: basis.isEmpty ? nil : basis.joined(separator: " · "))
        case .launch:
            guard let ms = input.launchMs else { return unknown(dimension) }
            let grade: Grade = ms <= Standard.launchGoodMs ? .good : (ms >= Standard.launchBadMs ? .bad : .warning)
            let value = ms < 1_000 ? "\(Int(ms.rounded()))ms" : String(format: "%.1f초", ms / 1_000)
            return Score(dimension: dimension, grade: grade, value: value, basis: input.performanceVersion)
        case .hang:
            guard let hang = input.hangPerHour else { return unknown(dimension) }
            let grade: Grade = hang < Standard.hangGood ? .good : (hang >= Standard.hangBad ? .bad : .warning)
            return Score(dimension: dimension, grade: grade, value: String(format: "시간당 %.1f초", hang),
                         basis: input.performanceVersion)
        case .rating:
            guard let rating = input.rating, input.ratingCount >= Standard.minRatings else { return unknown(dimension) }
            return Score(dimension: dimension,
                         grade: higherIsBetter(rating, good: Standard.ratingGood, bad: Standard.ratingBad),
                         value: String(format: "★ %.1f", rating),
                         basis: "별점 \(input.ratingCount)개" + (input.ratingCountries > 1 ? " · \(input.ratingCountries)개 나라" : ""))
        case .support:
            guard input.supportTotal >= Standard.minFeedback else { return unknown(dimension) }
            let share = Double(input.supportHandled) / Double(input.supportTotal)
            return Score(dimension: dimension,
                         grade: higherIsBetter(share, good: Standard.supportGood, bad: Standard.supportBad),
                         value: "\(Int((share * 100).rounded()))%",
                         basis: "\(input.supportTotal)건 중 \(input.supportHandled)건")
        case .deviceTest:
            guard let test = input.deviceTest else { return unknown(dimension) }
            return deviceTestScore(test)
        case .core:
            guard let core = input.core else {
                return unknown(dimension, hint: "스펙 release.coreAction 이나 통계의 가치 행동을 정하면 잽니다")
            }
            return coreScore(core)
        case .onboarding:
            guard let onboarding = input.onboarding else {
                return unknown(dimension, hint: "onboarding_completed · onboarding_skipped 이벤트를 보내면 잽니다")
            }
            guard onboarding.newInstalls >= Standard.minNewInstalls else {
                return unknown(dimension, hint: "새 설치 \(onboarding.newInstalls)대 — \(Standard.minNewInstalls)대부터 판정")
            }
            let share = Double(onboarding.passed) / Double(onboarding.newInstalls)
            let skipped = onboarding.skipped > 0 ? " · 건너뜀 \(onboarding.skipped)" : ""
            return Score(dimension: dimension,
                         grade: higherIsBetter(share, good: Standard.onboardingGood, bad: Standard.onboardingBad),
                         value: "\(Int((share * 100).rounded()))%",
                         basis: "새 설치 \(onboarding.newInstalls)대 중 \(onboarding.passed)대\(skipped)")
        case .coverage:
            guard let coverage = input.coverage else {
                return unknown(dimension, hint: "scripts/test-coverage.py 를 돌리면 잽니다")
            }
            guard let rate = coverage.lineCoverage else {
                // 커버리지를 켜고 돌린 적이 없다 — 테스트가 하나도 없으면 0% 와 같다.
                if coverage.testFunctions == 0 {
                    return Score(dimension: dimension, grade: .bad, value: "테스트 없음",
                                 basis: "소스 \(coverage.sourceFiles)개")
                }
                return Score(dimension: dimension, grade: .unknown, value: "커버리지 모름",
                             basis: "테스트 \(coverage.testFunctions)개 · 커버리지 켜고 돌리면 잽니다")
            }
            let date = coverage.measuredAt.map { $0.formatted(.dateTime.month().day()) }
            return Score(dimension: dimension,
                         grade: higherIsBetter(rate, good: Standard.coverageGood, bad: Standard.coverageBad),
                         value: "\(Int((rate * 100).rounded()))%",
                         basis: (["테스트 \(coverage.testFunctions)개"] + [date].compactMap { $0 }).joined(separator: " · "))
        }
    }

    /// 핵심 기능이 아직 도는가. 가장 새 버전에서 핵심 행동이 0명이고, 앞 버전의 비율로는
    /// 그럴 확률이 5% 미만이면 "동작 안 함 의심". 아니면 판정할 만큼 설치가 모인 가장 새 버전을
    /// 그 앞 버전과 견준다 — 문턱 넘게 줄면 주의. 비율의 높낮이는 묻지 않는다(쓰임새는 앱마다 다르다).
    private static func coreScore(_ core: Core) -> Score {
        let versions = core.versions.filter { $0.coreActionInstalls != nil }
        if let newest = versions.first, newest.coreActionInstalls == 0, newest.activeInstalls > 0,
           let before = versions.dropFirst().first(where: { ($0.coreActionRate ?? 0) > 0 }),
           let rate = before.coreActionRate,
           pow(1 - rate, Double(newest.activeInstalls)) < Standard.coreSilenceChance {
            return Score(dimension: .core, grade: .bad, value: "0명 · 동작 안 함 의심",
                         basis: "\(newest.version) 설치 \(newest.activeInstalls)대 · \(before.version) 은 \(percent(rate))")
        }
        let enough = versions.filter { $0.activeInstalls >= core.minInstalls }
        guard let current = enough.first, let rate = current.coreActionRate else {
            return unknown(.core, hint: "\(core.label) — 설치 \(core.minInstalls)대 넘는 버전이 아직 없음")
        }
        if rate == 0 {
            return Score(dimension: .core, grade: .warning, value: "0명",
                         basis: "\(current.version) — \(core.label) 이벤트가 오는지 확인")
        }
        if let before = enough.dropFirst().first, let previous = before.coreActionRate, previous > 0,
           rate < previous * (1 - core.dropMax) {
            return Score(dimension: .core, grade: .warning, value: percent(rate),
                         basis: "\(current.version) · \(before.version) 은 \(percent(previous))")
        }
        return Score(dimension: .core, grade: .good, value: percent(rate),
                     basis: "\(current.version) · \(core.label)")
    }

    struct Stability: Equatable {
        var rate: Double
        var version: String
        var isEstimate: Bool
    }

    /// 크래시 없는 설치 — 설치가 `minInstalls` 넘게 모인 가장 새 버전에서.
    ///
    /// 버전별 설치는 일 버킷과 함께 쌓는 전 기간 집계(`UsageRollups.versionTallies`)다. 14일 원본
    /// 이벤트로 세면 버전을 자주 내는 작은 앱은 어느 버전도 문턱에 못 닿았다(14일에 50대가 써도 버전마다 15대).
    /// 불안정 이벤트를 믿을 수 있으면 그 설치를 빼고, 아니면 그 버전의 크래시 보고 한 건을 한 설치로 보고
    /// 어림한다(아래 한계). `crashReports` 가 nil 이면 진단을 한 번도 안 보낸 앱 — 크래시 0건은 모르는 것이다.
    static func stability(tallies: [String: UsageVersionTally], minInstalls: Int,
                          stabilityKnown: Bool, crashReports: [String: Int]?) -> Stability? {
        let newest = tallies.keys.sorted { ReleaseHealth.isOlder($1, than: $0) }
        guard let version = newest.first(where: { (tallies[$0]?.installs.count ?? 0) >= minInstalls }),
              let tally = tallies[version] else { return nil }
        let installs = Double(tally.installs.count)
        if stabilityKnown {
            return Stability(rate: (installs - Double(tally.unstable.count)) / installs, version: version, isEstimate: false)
        }
        guard let crashReports else { return nil }
        return Stability(rate: max(0, 1 - Double(crashReports[version] ?? 0) / installs), version: version, isEstimate: true)
    }

    /// 지난 `days` 일 새 설치의 온보딩 — 일 버킷에서 순수하게 센다. 키는 "yyyy-MM-dd".
    ///
    /// 새 설치는 그 앱의 일 버킷에 처음 나온 날이 창 안인 설치다(기록 첫날은 빼고 — 그날은 모두가 처음이다).
    /// 오늘 처음 온 설치는 아직 온보딩 중일 수 있어 뺀다. 이벤트별 설치 기록이 생긴 뒤의 날만 본다.
    /// 앱이 통과 이벤트를 한 번도 안 보냈으면 nil — 0% 가 아니라 모르는 것이다.
    static func onboarding(_ buckets: [String: UsageDayBucket], today: String, windowStart: String) -> Onboarding? {
        let passNames: Set<String> = ["onboarding_complete", "onboarding_completed", "onboarding_done",
                                      "onboarding_finished", "onboarding_skipped", "onboarding_skip"]
        let skipNames: Set<String> = ["onboarding_skipped", "onboarding_skip"]
        let keys = buckets.keys.sorted()
        let tracked = keys.filter { buckets[$0]?.eventInstalls != nil }
        guard let firstDay = keys.first, let firstTracked = tracked.first,
              tracked.contains(where: { key in buckets[key]?.eventInstalls?.keys.contains(where: passNames.contains) == true })
        else { return nil }

        var firstSeen: [String: String] = [:]
        for key in keys {
            for install in buckets[key]?.installs ?? [] where firstSeen[install] == nil { firstSeen[install] = key }
        }
        let start = max(windowStart, firstTracked)
        let fresh = Set(firstSeen.filter { $0.value > firstDay && $0.value >= start && $0.value < today }.keys)

        var passed = Set<String>(), skipped = Set<String>()
        for key in tracked where key >= start {
            for (name, installs) in buckets[key]?.eventInstalls ?? [:] {
                if passNames.contains(name) { passed.formUnion(installs.intersection(fresh)) }
                if skipNames.contains(name) { skipped.formUnion(installs.intersection(fresh)) }
            }
        }
        return Onboarding(newInstalls: fresh.count, passed: passed.count, skipped: skipped.count)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// 못 켜짐 · 테스트 실패가 나쁨이다. 빌드를 못 하면(서명 등) 앱이 아니라 준비가 문제라 주의.
    private static func deviceTestScore(_ test: DeviceTestResult) -> Score {
        let date = test.testedAt.map { $0.formatted(.dateTime.month().day()) }
        let lead = Array(test.failures.prefix(1))
        func basis(_ parts: [String]) -> String { (parts + [date].compactMap { $0 }).joined(separator: " · ") }

        guard test.built else {
            return Score(dimension: .deviceTest, grade: .warning, value: "빌드 못 함", basis: basis(lead))
        }
        if test.launched == false {
            return Score(dimension: .deviceTest, grade: .bad, value: "켜지지 않음", basis: basis(lead))
        }
        if test.failedCount > 0 {
            return Score(dimension: .deviceTest, grade: .bad, value: "실패 \(test.failedCount)개", basis: basis(lead))
        }
        let counts = [test.unit.map { "단위 \($0.passed)" }, test.ui.map { "UI \($0.passed)" }].compactMap { $0 }
        let value = test.passedCount > 0 ? "통과 \(test.passedCount)개" : "켜짐 확인"
        return Score(dimension: .deviceTest, grade: .good, value: value, basis: basis(counts.isEmpty ? ["테스트 없음"] : counts))
    }

    private static func higherIsBetter(_ value: Double, good: Double, bad: Double) -> Grade {
        value >= good ? .good : (value < bad ? .bad : .warning)
    }

    /// 모름. `hint` 는 무엇을 하면 잴 수 있는지 한 줄.
    private static func unknown(_ dimension: Dimension, hint: String? = nil) -> Score {
        Score(dimension: dimension, grade: .unknown, value: "데이터 없음", basis: hint)
    }
}

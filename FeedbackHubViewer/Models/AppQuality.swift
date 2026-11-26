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

        /// 이보다 적은 표본으로는 판정하지 않는다.
        static let minRatings = 5
        static let minFeedback = 3
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
        var performanceVersion: String?
        var rating: Double?
        var ratingCount = 0
        /// 처리한 피드백 · 셈에 든 피드백.
        var supportHandled = 0
        var supportTotal = 0
        /// 허브가 본 7일 활성 — 같은 등급이면 쓰는 사람이 많은 앱부터.
        var active7 = 0
        /// 연결한 아이폰에서 돌린 테스트(`scripts/device-qa.sh`). 안 돌렸으면 nil.
        var deviceTest: DeviceTestResult?
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
        case deviceTest = "기기 테스트"
        var id: String { rawValue }

        /// 기준 한 줄 — 화면의 각 줄에 작게.
        var standard: String {
            switch self {
            case .stability: return "좋음 99% 이상 · 나쁨 98.91% 아래 (Instabug · Google Play vitals)"
            case .launch: return "좋음 0.4초 이하 · 나쁨 5초 이상 (Apple WWDC19 · Google Play vitals)"
            case .hang: return "시간당 좋음 1초 아래 · 나쁨 5초 이상 (허브 기준, Apple 은 문턱 미공개)"
            case .rating: return "좋음 4.5 이상 · 나쁨 4.0 아래 (업계 관례)"
            case .support: return "좋음 90% 이상 · 나쁨 50% 아래 (허브 기준)"
            case .deviceTest: return "좋음 켜지고 실패 0 · 나쁨 못 켜짐이나 테스트 실패 · 주의 아이폰용 빌드 못 함 (허브 기준)"
            }
        }

        var systemImage: String {
            switch self {
            case .stability: return "bolt.trianglebadge.exclamationmark"
            case .launch: return "timer"
            case .hang: return "hourglass"
            case .rating: return "star"
            case .support: return "bubble.left.and.bubble.right"
            case .deviceTest: return "iphone.gen3"
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
            return Score(dimension: dimension, grade: grade, value: value, basis: input.performanceVersion.map { "\($0) 버전" })
        case .hang:
            guard let hang = input.hangPerHour else { return unknown(dimension) }
            let grade: Grade = hang < Standard.hangGood ? .good : (hang >= Standard.hangBad ? .bad : .warning)
            return Score(dimension: dimension, grade: grade, value: String(format: "시간당 %.1f초", hang),
                         basis: input.performanceVersion.map { "\($0) 버전" })
        case .rating:
            guard let rating = input.rating, input.ratingCount >= Standard.minRatings else { return unknown(dimension) }
            return Score(dimension: dimension,
                         grade: higherIsBetter(rating, good: Standard.ratingGood, bad: Standard.ratingBad),
                         value: String(format: "★ %.1f", rating), basis: "별점 \(input.ratingCount)개")
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
        }
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

    private static func unknown(_ dimension: Dimension) -> Score {
        Score(dimension: dimension, grade: .unknown, value: "데이터 없음", basis: nil)
    }
}

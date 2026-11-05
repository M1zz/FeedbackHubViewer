//
//  Stabilization.swift
//  FeedbackHubViewer
//
//  안정화 지표. 릴리즈 건강이 "이번 버전 괜찮은가"를 묻는다면, 여기는 "릴리즈가 거듭되면서
//  이 앱이 예측 가능해지고 있는가"를 묻는다. 그래서 두 버전이 아니라 최근 버전들의 줄을 본다.
//
//   1. 크래시 없는 설치    99.5% 이상인가, 새 버전마다 떨어지지 않는가
//   2. 리텐션 D1 · D7 · D30  버전마다 널뛰지 않는가 (좋아짐이 아니라 고름을 본다)
//   3. 버전별 리뷰 · 버그   낮은 별점과 "업데이트 후 안 됨"이 튀지 않는가
//   4. 핫픽스 빈도         다시 올리는 비율이 30% 아래인가, 주기가 2~4주인가
//   5. 성능                멈춤 · 실행 시간 · 디스크 쓰기가 나빠지지 않는가 (Xcode Organizer 와 같은 값)
//   6. 가설                릴리즈마다 무엇을 검증하려는지 적혀 있는가
//
//  이 파일은 **순수**하다. 저장소도 화면도 모른다(`FeedbackStore+Stabilization.swift` 가
//  재료를 넘기고, `StabilizationCard` 가 그린다).
//
//  릴리즈 시각은 App Store Connect 의 버전 **생성 시각**이다. API 가 실제 출시 시각을 주지
//  않고, DeployBar 는 올릴 때 버전을 만들므로 이것이 "제출한 때"에 가장 가깝다. 출시보다
//  심사만큼(보통 하루) 이르다. 핫픽스 문턱이 48시간이 아니라 72시간인 까닭이다.
//
//  모르는 것은 0으로 적지 않는다. 잴 수 없는 신호의 `level` 은 nil 이고, 초록으로 치지 않는다.
//

import Foundation

enum Stabilization {

    static let crashFreeTarget = 0.995
    /// 이보다 작은 하락(%p)은 흔들림이다. 목표와 100% 사이가 0.5%p 뿐이라 그보다 좁아야 한다.
    static let crashFreeWobble = 0.002
    /// 이 시간 안에 다음 버전을 또 제출하면 핫픽스로 센다. 출시 뒤 48시간 + 심사 하루.
    static let hotfixHours = 72.0
    static let hotfixRateLimit = 0.3
    /// 핫픽스 비율을 재는 릴리즈 수.
    static let hotfixWindow = 10
    static let cadenceDays = 14...28
    /// 표와 신호가 보는 최근 버전 수.
    static let rowLimit = 5
    /// 버전마다 리뷰를 세는 창. 오래 살아남은 버전이 리뷰를 더 받는 것을 막는다.
    static let reviewDays = 14
    /// 비율로 말하기 위한 최소 표본.
    static let minSample = 20
    /// 양측 95%. 이보다 작은 리텐션 차이는 같은 앱에서도 우연히 난다.
    static let swingZ = 1.96
    /// 성능이 앞 버전보다 이만큼(상대값) 나빠지면 퇴행이다.
    static let performanceRegression = 0.2

    // MARK: - 재료

    /// 제출된 버전 하나.
    struct Release: Codable, Equatable, Identifiable {
        let version: String
        let submittedAt: Date
        var id: String { version }
    }

    struct Rate: Equatable {
        var returned = 0
        var eligible = 0
        var ratio: Double? { eligible > 0 ? Double(returned) / Double(eligible) : nil }
    }

    /// 그 버전이 나가 있는 동안 깐 설치들의 잔존.
    struct Cohort: Equatable {
        var d1 = Rate()
        var d7 = Rate()
        var d30 = Rate()
    }

    struct Tally: Equatable {
        let installs: Int
        let unstable: Int
    }

    /// 릴리즈마다 사람이 적는 것. 기기 사이에 오간다(`ReviewStateSync`).
    struct Hypothesis: Codable, Hashable {
        var hypothesis: String
        var exitCondition: String
        var updatedAt: Date

        var hasHypothesis: Bool { !hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var hasExitCondition: Bool { !exitCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        static func key(project: String, version: String) -> String { "\(project)|\(version)" }
    }

    /// 성능 지표 하나의 버전별 값. 값이 클수록 나쁜 지표만 담는다.
    struct PerformanceMetric: Codable, Equatable, Identifiable {
        let label: String
        let unit: String
        let values: [String: Double]
        var id: String { label }
    }

    /// App Store Connect 에서 받아 디스크에 두는 것.
    struct Source: Codable, Equatable {
        var releases: [Release]
        var performance: [PerformanceMetric]
        var fetchedAt: Date
    }

    // MARK: - 결과

    struct Row: Equatable, Identifiable {
        let version: String
        let submittedAt: Date
        /// 앞 버전 제출 뒤 `hotfixHours` 안에 제출했는가.
        let isHotfix: Bool
        let tally: Tally?
        /// 불안정 이벤트를 믿을 수 없거나 표본이 없으면 nil.
        let crashFreeRate: Double?
        let crashReports: Int
        let cohort: Cohort
        /// 리뷰를 아직 안 받았으면 nil.
        let reviews: Int?
        let lowReviews: Int?
        let updateComplaints: Int?
        let bugFeedback: Int
        let hypothesis: Hypothesis?
        var id: String { version }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case crash = "크래시"
        case retention = "리텐션"
        case reviews = "리뷰"
        case hotfix = "핫픽스"
        case performance = "성능"
        case hypothesis = "가설"
        var id: String { rawValue }
    }

    struct Signal: Equatable, Identifiable {
        let kind: Kind
        /// nil 은 "잴 수 없다"이지 괜찮다는 뜻이 아니다.
        let level: ReleaseHealth.Level?
        let headline: String
        var id: Kind { kind }
    }

    struct Report: Equatable {
        /// 새것이 위.
        let rows: [Row]
        let signals: [Signal]
        let performance: [PerformanceMetric]

        /// 잴 수 있는 신호 가운데 가장 무거운 것. 하나도 못 재면 nil.
        var level: ReleaseHealth.Level? { signals.compactMap(\.level).max() }
        var measured: Int { signals.filter { $0.level != nil }.count }
        func signal(_ kind: Kind) -> Signal? { signals.first { $0.kind == kind } }
    }

    // MARK: - 재기

    /// - Parameters:
    ///   - releases: 제출된 버전 전부(차례 무관).
    ///   - tallies: 버전 → 설치 · 불안정 설치. 전 기간 누적.
    ///   - stabilityKnown: 불안정 이벤트를 믿을 수 있는가(`ReleaseHealth` 머리말).
    ///   - cohorts: 버전 → 그 버전 동안 깐 설치의 잔존.
    ///   - reviews: 이 앱의 리뷰. 아직 안 받았으면 nil.
    static func measure(source: Source,
                        tallies: [String: Tally],
                        stabilityKnown: Bool,
                        cohorts: [String: Cohort],
                        crashes: [CrashReport],
                        reviews: [CustomerReview]?,
                        feedback: [Feedback],
                        hypotheses: [String: Hypothesis]) -> Report? {
        let ordered = source.releases.sorted { $0.submittedAt > $1.submittedAt }
        guard !ordered.isEmpty else { return nil }

        let resolve = ReleaseHealth.versionResolver(for: crashes)
        let crashesByVersion = Dictionary(grouping: crashes.filter { $0.kind == "crash" }, by: resolve)
            .mapValues(\.count)

        let rows: [Row] = ordered.prefix(rowLimit).enumerated().map { index, release in
            let previous = index + 1 < ordered.count ? ordered[index + 1] : nil
            let next = index > 0 ? ordered[index - 1] : nil
            let tally = tallies[release.version]
            let end = min(next?.submittedAt ?? .distantFuture,
                          release.submittedAt.addingTimeInterval(Double(reviewDays) * 86_400))
            let window = reviews?.filter { $0.createdDate >= release.submittedAt && $0.createdDate < end }
            let bugs = feedback.filter {
                $0.appVersion?.trimmingCharacters(in: .whitespaces) == release.version
                    && $0.feedbackType?.trimmingCharacters(in: .whitespaces).lowercased() == "bug"
            }.count
            let crashFree: Double? = {
                guard stabilityKnown, let tally, tally.installs > 0 else { return nil }
                return Double(tally.installs - tally.unstable) / Double(tally.installs)
            }()
            return Row(version: release.version,
                       submittedAt: release.submittedAt,
                       isHotfix: previous.map { isHotfix(release, after: $0) } ?? false,
                       tally: tally,
                       crashFreeRate: crashFree,
                       crashReports: crashesByVersion[release.version] ?? 0,
                       cohort: cohorts[release.version] ?? Cohort(),
                       reviews: window?.count,
                       lowReviews: window?.filter { $0.rating <= 2 }.count,
                       updateComplaints: window?.filter(isUpdateComplaint).count,
                       bugFeedback: bugs,
                       hypothesis: hypotheses[release.version])
        }

        return Report(rows: rows,
                      signals: [crashSignal(rows, stabilityKnown: stabilityKnown),
                                retentionSignal(rows),
                                reviewSignal(rows),
                                hotfixSignal(ordered),
                                performanceSignal(source.performance, rows: rows),
                                hypothesisSignal(rows)],
                      performance: source.performance)
    }

    static func isHotfix(_ release: Release, after previous: Release) -> Bool {
        release.submittedAt.timeIntervalSince(previous.submittedAt) <= hotfixHours * 3600
    }

    // MARK: - 신호

    static func crashSignal(_ rows: [Row], stabilityKnown: Bool) -> Signal {
        guard let latest = rows.first else {
            return Signal(kind: .crash, level: nil, headline: "버전 기록이 없다")
        }
        guard stabilityKnown else {
            return Signal(kind: .crash, level: nil,
                          headline: "크래시 없는 설치 비율을 못 잰다. 앱이 launch_incomplete 를 안 보낸다 (\(latest.version) 크래시 보고 \(latest.crashReports)건)")
        }
        guard let measured = rows.first(where: { ($0.tally?.installs ?? 0) >= minSample }),
              let rate = measured.crashFreeRate else {
            return Signal(kind: .crash, level: nil,
                          headline: "버전별 설치가 아직 \(minSample)대 안 쌓였다 (\(latest.version) 크래시 보고 \(latest.crashReports)건)")
        }
        let target = ReleaseHealth.percent(crashFreeTarget)
        if rate < crashFreeTarget {
            // 작은 앱은 한 대만 불안정해도 목표 아래다. 한 대는 사고이지 경향이 아니다.
            let level: ReleaseHealth.Level = (measured.tally?.unstable ?? 0) >= 2 ? .red : .yellow
            return Signal(kind: .crash, level: level,
                          headline: "\(measured.version) 크래시 없는 설치 \(ReleaseHealth.percent(rate)) (불안정 \(measured.tally?.unstable ?? 0)대), 목표 \(target) 아래")
        }
        let older = rows.drop { $0.version != measured.version }.dropFirst()
            .first { ($0.tally?.installs ?? 0) >= minSample }
        if let before = older?.crashFreeRate, rate < before - crashFreeWobble {
            return Signal(kind: .crash, level: .yellow,
                          headline: "크래시 없는 설치 \(ReleaseHealth.percent(before)) → \(ReleaseHealth.percent(rate))로 내려감")
        }
        return Signal(kind: .crash, level: .green,
                      headline: "\(measured.version) 크래시 없는 설치 \(ReleaseHealth.percent(rate)), 목표 \(target) 이상")
    }

    /// 버전끼리의 차이가 우연으로 설명되지 않는 걸음 수로 널뜀을 잰다. 작은 앱에서는 몇 명
    /// 차이로 D7 이 두 배가 되므로 퍼센트 폭만 보면 모든 앱이 널뛰는 것으로 나온다.
    static func retentionSignal(_ rows: [Row]) -> Signal {
        let series: (label: String, rates: [Rate])? = {
            let oldestFirst = Array(rows.reversed())
            let d7 = oldestFirst.map(\.cohort.d7).filter { $0.eligible >= minSample }
            if d7.count >= 3 { return ("D7", d7) }
            let d1 = oldestFirst.map(\.cohort.d1).filter { $0.eligible >= minSample }
            return d1.count >= 3 ? ("D1", d1) : nil
        }()
        guard let series else {
            return Signal(kind: .retention, level: nil,
                          headline: "견줄 버전이 모자란다 (신규 설치 \(minSample)대 넘는 버전이 3개 필요)")
        }
        let ratios = series.rates.compactMap(\.ratio)
        let lowest = ReleaseHealth.percent(ratios.min() ?? 0)
        let highest = ReleaseHealth.percent(ratios.max() ?? 0)
        let swings = zip(series.rates, series.rates.dropFirst()).filter(isSwing).count
        switch swings {
        case 0:
            return Signal(kind: .retention, level: .green,
                          headline: "버전마다 \(series.label) \(lowest)~\(highest), 우연을 넘는 움직임 없음")
        case 1:
            return Signal(kind: .retention, level: .yellow,
                          headline: "\(series.label) 이 한 번 크게 움직였다 (\(lowest)~\(highest))")
        default:
            return Signal(kind: .retention, level: .red,
                          headline: "\(series.label) 이 버전마다 널뛴다 (\(lowest)~\(highest), 큰 움직임 \(swings)번)")
        }
    }

    /// 두 비율의 차이가 우연으로 설명되지 않는가(z 검정, 양측).
    static func isSwing(_ before: Rate, _ after: Rate) -> Bool {
        guard before.eligible > 0, after.eligible > 0 else { return false }
        let n1 = Double(before.eligible), n2 = Double(after.eligible)
        let p1 = Double(before.returned) / n1, p2 = Double(after.returned) / n2
        let pooled = Double(before.returned + after.returned) / (n1 + n2)
        let se = (pooled * (1 - pooled) * (1 / n1 + 1 / n2)).squareRoot()
        guard se > 0 else { return p1 != p2 }
        return abs(p1 - p2) / se >= swingZ
    }

    static func reviewSignal(_ rows: [Row]) -> Signal {
        guard let latest = rows.first else {
            return Signal(kind: .reviews, level: nil, headline: "버전 기록이 없다")
        }
        let earlier = rows.dropFirst()
        let usualBugs = median(earlier.map(\.bugFeedback))
        let bugsSpiked = latest.bugFeedback >= 2 && Double(latest.bugFeedback) > usualBugs
        guard let low = latest.lowReviews, let complaints = latest.updateComplaints else {
            if bugsSpiked {
                return Signal(kind: .reviews, level: .yellow,
                              headline: "\(latest.version) 버그 피드백 \(latest.bugFeedback)건. 리뷰는 아직 안 받았다")
            }
            return Signal(kind: .reviews, level: nil, headline: "리뷰를 아직 안 받았다 (App Store Connect 키 필요)")
        }
        let usualLow = median(earlier.compactMap(\.lowReviews))
        let days = "\(reviewDays)일"
        if low >= 3, Double(low) > max(usualLow, 1) * 2 {
            return Signal(kind: .reviews, level: .red,
                          headline: "\(latest.version) 제출 뒤 \(days) 낮은 별점 \(low)건, 평소 \(formatted(usualLow))건")
        }
        if complaints > 0 {
            return Signal(kind: .reviews, level: .yellow,
                          headline: "\(latest.version)에 \"업데이트 후 안 됨\" 리뷰 \(complaints)건")
        }
        if bugsSpiked {
            return Signal(kind: .reviews, level: .yellow,
                          headline: "\(latest.version) 버그 피드백 \(latest.bugFeedback)건, 평소 \(formatted(usualBugs))건")
        }
        return Signal(kind: .reviews, level: .green,
                      headline: "\(latest.version) 낮은 별점 \(low)건, 튀지 않음")
    }

    static func hotfixSignal(_ ordered: [Release]) -> Signal {
        let considered = Array(ordered.prefix(hotfixWindow + 1))
        let gaps = zip(considered, considered.dropFirst()).map { newer, older in
            newer.submittedAt.timeIntervalSince(older.submittedAt)
        }
        guard gaps.count >= 3 else {
            return Signal(kind: .hotfix, level: nil, headline: "릴리즈가 \(considered.count)번뿐이라 아직 못 잰다")
        }
        let hotfixes = gaps.filter { $0 <= hotfixHours * 3600 }.count
        let rate = Double(hotfixes) / Double(gaps.count)
        let cadence = median(gaps.map { $0 / 86_400 })
        let summary = "최근 \(gaps.count)번 중 \(hotfixes)번 핫픽스(\(ReleaseHealth.percent(rate))), 주기 중앙값 \(formatted(cadence))일"
        if rate >= hotfixRateLimit {
            return Signal(kind: .hotfix, level: .red, headline: summary + ". 사용자가 베타 테스트를 하고 있다")
        }
        if cadence < Double(cadenceDays.lowerBound) {
            return Signal(kind: .hotfix, level: .yellow,
                          headline: summary + ". 본판 고정 \(cadenceDays.lowerBound)~\(cadenceDays.upperBound)일보다 잦다")
        }
        return Signal(kind: .hotfix, level: .green, headline: summary)
    }

    static func performanceSignal(_ metrics: [PerformanceMetric], rows: [Row]) -> Signal {
        // 표의 버전 차례대로 값이 있는 두 버전을 견준다. 애플은 사용자가 적은 버전의 값을 안 준다.
        var regressions: [String] = []
        var measured = false
        for metric in metrics {
            let points = rows.compactMap { row in metric.values[row.version].map { (row.version, $0) } }
            guard points.count >= 2 else { continue }
            measured = true
            let (latestVersion, now) = points[0]
            let before = points[1].1
            if before > 0, (now - before) / before > performanceRegression {
                regressions.append("\(metric.label) \(formatted(before)) → \(formatted(now))\(metric.unit) (\(latestVersion))")
            }
        }
        guard measured else {
            return Signal(kind: .performance, level: nil, headline: "애플이 버전별 성능을 아직 안 준다 (사용자가 적으면 안 준다)")
        }
        if regressions.isEmpty {
            return Signal(kind: .performance, level: .green, headline: "멈춤 · 실행 · 디스크 쓰기 나빠지지 않음")
        }
        return Signal(kind: .performance, level: .yellow, headline: regressions.joined(separator: ", "))
    }

    static func hypothesisSignal(_ rows: [Row]) -> Signal {
        guard !rows.isEmpty else {
            return Signal(kind: .hypothesis, level: nil, headline: "버전 기록이 없다")
        }
        let written = rows.filter { $0.hypothesis?.hasHypothesis == true }
        let exits = written.filter { $0.hypothesis?.hasExitCondition == true }.count
        let summary = "최근 \(rows.count)개 중 가설 \(written.count)개 · 종료 조건 \(exits)개"
        return Signal(kind: .hypothesis, level: exits == rows.count ? .green : .yellow, headline: summary)
    }

    // MARK: - 업데이트 불만

    private static let updateWords = ["업데이트", "업뎃", "update", "アップデート", "更新"]
    private static let brokenWords = [
        "안 됨", "안됨", "안 되", "안되", "안돼", "안 돼", "먹통", "튕", "꺼져", "꺼짐", "오류", "에러", "버그",
        "사라", "멈춤", "멈춰", "못 쓰", "못쓰", "망", "broke", "broken", "crash", "not working", "doesn't work",
        "stopped", "bug", "freez", "できな", "落ち", "不具合", "バグ", "无法", "崩溃", "闪退"
    ]

    /// 낮은 별점이면서 업데이트와 고장을 함께 말하는 리뷰. 형태소 분석 없는 어림이다.
    static func isUpdateComplaint(_ review: CustomerReview) -> Bool {
        guard review.rating <= 3 else { return false }
        let text = "\(review.title ?? "") \(review.body ?? "")".lowercased()
        return updateWords.contains(where: text.contains) && brokenWords.contains(where: text.contains)
    }

    // MARK: - 성능 읽기

    /// 재는 범주와 화면에 적을 이름. 값이 클수록 나쁜 것만 고른다.
    static let performanceCategories: [(identifier: String, label: String)] = [
        ("HANG", "멈춤"), ("LAUNCH", "실행 시간"), ("DISK", "디스크 쓰기")
    ]

    /// `perfPowerMetrics` 응답(xcode-metrics JSON)에서 범주마다 첫 지표의 중앙값(p50)을 뽑는다.
    /// 기기가 여럿이면 "모든 기기" 묶음을, 없으면 첫 묶음을 쓴다.
    static func parsePerformance(_ data: Data) -> [PerformanceMetric] {
        struct Document: Decodable { let productData: [Product]? }
        struct Product: Decodable { let metricCategories: [Category]? }
        struct Category: Decodable { let identifier: String?; let metrics: [Metric]? }
        struct Metric: Decodable { let unit: Unit?; let datasets: [Dataset]? }
        struct Unit: Decodable { let displayName: String? }
        struct Dataset: Decodable { let filterCriteria: Filter?; let points: [Point]? }
        struct Filter: Decodable { let percentile: String?; let device: String? }
        struct Point: Decodable { let version: String?; let value: Double? }

        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return [] }
        let categories = document.productData?.first { $0.metricCategories?.isEmpty == false }?.metricCategories ?? []
        return performanceCategories.compactMap { wanted -> PerformanceMetric? in
            guard let metric = categories.first(where: { $0.identifier == wanted.identifier })?.metrics?.first,
                  let datasets = metric.datasets, !datasets.isEmpty else { return nil }
            let median = datasets.filter { ($0.filterCriteria?.percentile ?? "").contains("fifty") }
            let pool = median.isEmpty ? datasets : median
            let dataset = pool.first { ($0.filterCriteria?.device ?? "").hasPrefix("all") } ?? pool[0]
            var values: [String: Double] = [:]
            for point in dataset.points ?? [] {
                if let version = point.version, let value = point.value { values[version] = value }
            }
            guard !values.isEmpty else { return nil }
            return PerformanceMetric(label: wanted.label, unit: metric.unit?.displayName ?? "", values: values)
        }
    }

    // MARK: - 작은 것들

    static func median(_ values: [Int]) -> Double { median(values.map(Double.init)) }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

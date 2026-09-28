//
//  ReleaseHealth.swift
//  FeedbackHubViewer
//
//  릴리즈 건강. 새 버전을 낸 뒤 앱마다 세 가지를 묻는다.
//
//   1. 원래 쓰던 사람이 여전히 **핵심 행동**을 하는가 (하위 호환)
//   2. 새 버전이 **안정적**인가
//   3. 새 버전이 **퍼지고** 있는가
//
//  최신 버전과 바로 앞 버전을 나란히 놓고, 초록 · 노랑 · 빨강 하나와 그 이유 한 줄을 낸다.
//
//  어느 앱에서나 돈다. 스펙이 없어도 크래시 · 불안정 이벤트 · 피드백 · 채택은 잴 수 있고,
//  앱 스펙(`*.usage-spec.json`)에 `release` 절이 있으면 핵심 행동률과 앱이 정한 문턱이 더해진다.
//
//  이 파일은 **순수**하다. 레코드 배열을 받아 숫자를 내고, 숫자를 받아 판정을 낸다.
//  저장소도 화면도 모른다(`FeedbackStore+Release.swift` 가 레코드를 넘기고, 카드가 그린다).
//
//  모르는 것은 0으로 적지 않는다:
//   - 스펙에 핵심 행동이 없으면 핵심 행동률은 nil 이다. 0% 가 아니다.
//   - 불안정 이벤트를 앱이 보낸다고 약속하지 않았고(스펙에 안 적음) 한 번도 도착한 적도 없으면,
//     "크래시 없는 설치 비율"은 nil 이다. 100% 로 적으면 없는 안정을 지어내는 것이다.
//   - 크래시 보고(MetricKit)에는 설치 ID 가 없다. 그래서 설치 비율에는 못 들어가고 건수로만 선다.
//

import Foundation

// MARK: - 스펙

/// 앱 스펙의 `release` 절. 없으면 `ReleaseSpec.fallback` 을 쓴다.
///
///     "release": {
///       "coreAction": { "label": "키보드로 넣은 사람", "events": ["keyboard_used"], "note": "..." },
///       "stabilityEvents": ["launch_incomplete"],
///       "thresholds": { "crashFreeInstallsMin": 0.99, "coreActionDropMax": 0.2, "minInstallsForVerdict": 20 },
///       "promises": [ { "id": "...", "title": "...", "guard": "..." } ]
///     }
struct ReleaseSpec: Decodable, Equatable {

    /// 이 앱에서 "쓰고 있다"를 뜻하는 행동. 없으면 핵심 행동률을 재지 않는다.
    var coreAction: CoreAction?
    /// 설치가 불안정했다는 신호로 읽을 이벤트 **기본형**들.
    var stabilityEvents: [String]
    /// 스펙이 `stabilityEvents` 를 직접 적었는가. 적었다면 앱이 그 이벤트를 보낸다고
    /// 약속한 것이라, 한 건도 안 왔어도 "불안정 설치 0"으로 믿는다. 기본값만 쓰는
    /// 앱은 그 이벤트가 한 번이라도 도착했어야 믿는다.
    var stabilityEventsDeclared: Bool
    var thresholds: Thresholds
    /// 이 앱이 릴리즈마다 지키기로 한 약속. 화면에 그대로 적는다.
    var promises: [Promise]

    struct CoreAction: Decodable, Equatable {
        let label: String
        /// 이 중 하나라도 보낸 설치가 핵심 행동을 한 설치다. 기본형으로 적는다.
        let events: [String]
        var note: String?
    }

    struct Thresholds: Decodable, Equatable {
        /// 불안정 이벤트가 없는 설치의 비율이 이보다 낮으면 빨강.
        var crashFreeInstallsMin: Double
        /// 핵심 행동률이 앞 버전보다 이 비율(상대값)을 넘게 떨어지면 빨강.
        var coreActionDropMax: Double
        /// 최신 버전의 활성 설치가 이보다 적으면 비율로 판단하지 않는다.
        var minInstallsForVerdict: Int

        static let fallback = Thresholds(crashFreeInstallsMin: 0.99,
                                         coreActionDropMax: 0.2,
                                         minInstallsForVerdict: 20)

        init(crashFreeInstallsMin: Double, coreActionDropMax: Double, minInstallsForVerdict: Int) {
            self.crashFreeInstallsMin = crashFreeInstallsMin
            self.coreActionDropMax = coreActionDropMax
            self.minInstallsForVerdict = minInstallsForVerdict
        }

        enum CodingKeys: String, CodingKey {
            case crashFreeInstallsMin, coreActionDropMax, minInstallsForVerdict
        }

        // 하나만 적어도 나머지는 기본값으로 채운다.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Thresholds.fallback
            crashFreeInstallsMin = try c.decodeIfPresent(Double.self, forKey: .crashFreeInstallsMin) ?? d.crashFreeInstallsMin
            coreActionDropMax = try c.decodeIfPresent(Double.self, forKey: .coreActionDropMax) ?? d.coreActionDropMax
            minInstallsForVerdict = try c.decodeIfPresent(Int.self, forKey: .minInstallsForVerdict) ?? d.minInstallsForVerdict
        }
    }

    struct Promise: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        /// 이 약속을 무엇이 지키는가(테스트 · 스크립트 · 훅). `guard` 는 Swift 예약어라 이름만 바꿔 읽는다.
        var guardText: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case guardText = "guard"
        }
    }

    static let defaultStabilityEvents = ["launch_incomplete"]

    /// 스펙에 `release` 절이 없는 앱이 쓰는 값.
    static let fallback = ReleaseSpec(coreAction: nil,
                                      stabilityEvents: defaultStabilityEvents,
                                      stabilityEventsDeclared: false,
                                      thresholds: .fallback,
                                      promises: [])

    init(coreAction: CoreAction?, stabilityEvents: [String], stabilityEventsDeclared: Bool,
         thresholds: Thresholds, promises: [Promise]) {
        self.coreAction = coreAction
        self.stabilityEvents = stabilityEvents
        self.stabilityEventsDeclared = stabilityEventsDeclared
        self.thresholds = thresholds
        self.promises = promises
    }

    enum CodingKeys: String, CodingKey {
        case coreAction, stabilityEvents, thresholds, promises
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coreAction = try c.decodeIfPresent(CoreAction.self, forKey: .coreAction)
        let declared = try c.decodeIfPresent([String].self, forKey: .stabilityEvents)
        stabilityEvents = declared ?? Self.defaultStabilityEvents
        stabilityEventsDeclared = declared != nil
        thresholds = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? .fallback
        promises = try c.decodeIfPresent([Promise].self, forKey: .promises) ?? []
    }
}

// MARK: - 계산

enum ReleaseHealth {

    /// 버전마다 사용 이벤트를 훑는 창. 한 버전이 퍼지고 자리 잡는 데 걸리는 시간으로 잡았다.
    static let windowDays = 14
    /// 채택률을 재는 창. "지금" 쓰는 사람 중 몇이 새 버전인가라서 더 짧다.
    static let adoptionDays = 7
    /// 이보다 작은 차이(%p)는 흔들림으로 보고 퇴행이라 부르지 않는다.
    static let crashFreeWobble = 0.005

    // MARK: 결과 모양

    enum Level: Int, Comparable {
        case green = 0, yellow = 1, red = 2

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .green: return "초록"
            case .yellow: return "노랑"
            case .red: return "빨강"
            }
        }
    }

    struct Verdict: Equatable {
        let level: Level
        /// 무거운 것부터. 첫 줄이 카드의 한 줄 요약이다.
        let reasons: [String]
        var headline: String { reasons.first ?? level.label }
    }

    /// 버전 하나에서 처음 본 크래시 지문.
    struct NewSignature: Equatable, Identifiable {
        let fingerprint: String
        let kind: String
        let title: String
        let reports: Int
        var id: String { fingerprint }
        var isCrash: Bool { kind == "crash" }
    }

    /// 버전 하나의 숫자들. 모르는 것은 nil 이다.
    struct VersionMetrics: Equatable {
        let version: String
        /// 창 안에서 이 버전으로 이벤트를 하나라도 보낸 설치 수.
        let activeInstalls: Int
        /// 그중 핵심 행동 이벤트를 보낸 설치. 스펙에 핵심 행동이 없으면 nil.
        let coreActionInstalls: Int?
        /// 불안정 이벤트를 보낸 설치. 모르면 nil (머리말).
        let unstableInstalls: Int?
        /// 창 안에서 이 버전에 붙은 MetricKit 진단 중 크래시 건수.
        let crashReports: Int
        /// 이 버전에서 처음 본 지문. 최신 버전에만 채운다.
        let newSignatures: [NewSignature]
        /// 창 안에 들어온 이 버전의 피드백.
        let feedback: Int
        /// 그중 버그 유형. 유형을 적은 피드백이 하나도 없으면 nil.
        let bugFeedback: Int?
        /// 이 버전을 쓴 플랫폼(iOS · macCatalyst …).
        let platforms: Set<String>

        var coreActionRate: Double? {
            guard let coreActionInstalls, activeInstalls > 0 else { return nil }
            return Double(coreActionInstalls) / Double(activeInstalls)
        }

        var crashFreeRate: Double? {
            guard let unstableInstalls, activeInstalls > 0 else { return nil }
            return Double(activeInstalls - unstableInstalls) / Double(activeInstalls)
        }

        /// 활성 설치 한 대당 크래시 보고. 설치 ID 가 없어 비율이 아니라 밀도다.
        var crashDensity: Double? {
            activeInstalls > 0 ? Double(crashReports) / Double(activeInstalls) : nil
        }
    }

    struct Adoption: Equatable {
        /// 최근 `adoptionDays` 일 활성 설치 중 최신 버전을 쓴 설치.
        let onLatest: Int
        /// 같은 창의 활성 설치(최신 버전이 도는 플랫폼만).
        let active: Int
        var share: Double? { active > 0 ? Double(onLatest) / Double(active) : nil }
    }

    struct Report: Equatable {
        let latest: VersionMetrics
        let previous: VersionMetrics?
        let adoption: Adoption
        let verdict: Verdict
        let spec: ReleaseSpec
        /// 스펙에 `release` 절이 있었는가.
        let hasReleaseSpec: Bool
        /// 불안정 이벤트를 믿을 수 있는가(머리말). 못 믿으면 크래시 없는 설치 비율이 nil.
        let stabilityKnown: Bool
        /// 설치 ID 가 없어 설치로 못 센 이벤트 수.
        let eventsWithoutInstall: Int
        /// 이 기기가 원본 이벤트를 창 끝까지 들고 있지 않을 때, 들고 있는 가장 오래된 시각.
        let coverageStart: Date?
    }

    // MARK: 버전 정렬

    /// 버전 문자열을 숫자 조각으로. "5.1.10" 이 "5.1.9" 보다 뒤에 온다.
    /// 조각마다 앞자리 숫자만 읽는다("2b1" → 2). 숫자가 전혀 없으면 nil.
    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { part -> Int? in
            let digits = part.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        guard let first = parts.first, first != nil else { return nil }
        return parts.map { $0 ?? 0 }
    }

    /// `lhs` 가 `rhs` 보다 앞선(낮은) 버전인가. 빈 조각은 0 으로 채워 "5.1" == "5.1.0".
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        guard let l = components(lhs), let r = components(rhs) else {
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b }
        }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    /// 버전으로 읽을 수 있는 값인가. 레코드가 버전을 안 실으면 대시 문자 한 글자가 들어온다.
    static func isRealVersion(_ version: String) -> Bool {
        components(version.trimmingCharacters(in: .whitespaces)) != nil
    }

    // MARK: 크래시가 난 버전

    /// 크래시 보고를 버전에 붙인다.
    ///
    /// `appVersion` 은 **배달될 때** 깔려 있던 버전이라, 크래시 다음 날 업데이트한 기기의
    /// 보고는 새 버전에 붙어 버린다. `buildNumber` 가 죽은 빌드를 정확히 가리키지만
    /// 그것은 빌드 번호라 사용 이벤트의 버전과 맞대 볼 수 없다. 그래서 같은 빌드 번호를
    /// 가진 보고들이 가장 많이 적은 `appVersion` 을 그 빌드의 버전으로 삼는다. 대부분의
    /// 보고는 죽은 그 버전에서 배달되므로 다수결이 맞고, 업데이트 뒤에 배달된 몇 건만
    /// 제자리로 돌아온다. 빌드 번호가 없는 옛 보고는 `appVersion` 그대로다.
    static func versionResolver(for crashes: [CrashReport]) -> (CrashReport) -> String {
        var votes: [String: [String: Int]] = [:]
        for report in crashes {
            guard let build = normalizedBuild(report.buildNumber), isRealVersion(report.appVersion) else { continue }
            votes[build, default: [:]][report.appVersion, default: 0] += 1
        }
        let byBuild = votes.compactMapValues { tally in
            tally.max { $0.value == $1.value ? isOlder($1.key, than: $0.key) : $0.value < $1.value }?.key
        }
        return { report in
            guard let build = normalizedBuild(report.buildNumber), let version = byBuild[build] else {
                return report.appVersion
            }
            return version
        }
    }

    private static func normalizedBuild(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }

    // MARK: 재기

    /// 한 앱의 레코드로 최신 버전과 앞 버전을 잰다. 창 안에 버전을 가를 사용 이벤트가
    /// 없으면 nil 이다(판정할 것이 없다는 뜻이지 초록이 아니다).
    ///
    /// - Parameters:
    ///   - events: 이 앱의 원본 사용 이벤트(기간 무관, 창은 여기서 자른다).
    ///   - crashes: 이 앱의 진단 전부. 새 지문을 가리려면 옛 버전 것까지 있어야 한다.
    ///   - feedback: 이 앱의 피드백 전부.
    ///   - spec: 앱 스펙의 `release` 절. 없으면 nil.
    ///   - everSeenEvents: 이 앱에서 한 번이라도 도착한 이벤트 기본형(전 기간 집계).
    ///   - coverageStart: 이 기기가 원본 이벤트를 창 끝까지 못 들고 있으면 그 시작 시각.
    static func measure(events: [UsageEvent],
                        crashes: [CrashReport],
                        feedback: [Feedback],
                        spec releaseSpec: ReleaseSpec?,
                        everSeenEvents: Set<String>,
                        coverageStart: Date? = nil,
                        now: Date = Date()) -> Report? {
        let spec = releaseSpec ?? .fallback
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let adoptionStart = now.addingTimeInterval(-Double(adoptionDays) * 86_400)

        let recent = events.filter { $0.occurredAt >= windowStart && $0.occurredAt <= now && isRealVersion($0.appVersion) }
        let byVersion = Dictionary(grouping: recent, by: { $0.appVersion.trimmingCharacters(in: .whitespaces) })
        let versions = byVersion.keys.sorted { isOlder($1, than: $0) }   // 새것부터
        guard let latestVersion = versions.first else { return nil }

        let latestPlatforms = Set(byVersion[latestVersion, default: []].map(\.platform))
        // 앞 버전은 **같은 플랫폼 줄기**에서 고른다. 맥 앱이 따로 번호를 매기면
        // iOS 5.1 의 앞 버전으로 맥 1.2 를 고르는 일이 생긴다.
        let previousVersion = versions.dropFirst().first { version in
            !Set(byVersion[version, default: []].map(\.platform)).isDisjoint(with: latestPlatforms)
        }

        let stabilityNames = Set(spec.stabilityEvents)
        let stabilityKnown = spec.stabilityEventsDeclared || !everSeenEvents.isDisjoint(with: stabilityNames)
        let coreNames = spec.coreAction.map { Set($0.events) }

        // 크래시: 버전을 제자리에 붙이고, 지문별로 "어느 버전에서 봤나"를 모은다.
        let resolve = versionResolver(for: crashes)
        let crashVersion = crashes.map { (report: $0, version: resolve($0)) }
        let olderFingerprints: Set<String> = Set(crashVersion.compactMap { pair in
            isRealVersion(pair.version) && isOlder(pair.version, than: latestVersion) ? pair.report.fingerprint : nil
        })

        func metrics(for version: String, includeNewSignatures: Bool) -> VersionMetrics {
            let group = byVersion[version, default: []]
            var installs: Set<String> = []
            var core: Set<String> = []
            var unstable: Set<String> = []
            for event in group {
                guard let install = event.installID, !install.isEmpty else { continue }
                installs.insert(install)
                let base = event.baseName
                if coreNames?.contains(base) == true { core.insert(install) }
                if stabilityNames.contains(base) { unstable.insert(install) }
            }

            let onVersion = crashVersion.filter { $0.version == version }
            let crashesInWindow = onVersion.filter {
                $0.report.kind == "crash" && ($0.report.happenedAt ?? .distantPast) >= windowStart
            }.count

            var fresh: [NewSignature] = []
            if includeNewSignatures {
                let grouped = Dictionary(grouping: onVersion.map(\.report), by: \.fingerprint)
                fresh = grouped.compactMap { fingerprint, reports in
                    guard !olderFingerprints.contains(fingerprint),
                          let first = reports.first, !first.isLegacyStack else { return nil }
                    let issue = CrashIssue.group(reports, now: now).first
                    return NewSignature(fingerprint: fingerprint, kind: first.kind,
                                        title: issue?.title ?? first.cause.label,
                                        reports: reports.count)
                }
                .sorted { $0.reports == $1.reports ? $0.fingerprint < $1.fingerprint : $0.reports > $1.reports }
            }

            let notes = feedback.filter {
                ($0.appVersion?.trimmingCharacters(in: .whitespaces) ?? "") == version
                    && ($0.createdAt ?? .distantPast) >= windowStart
            }
            let typed = notes.filter { !($0.feedbackType?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }
            let bugs = typed.filter { $0.feedbackType?.trimmingCharacters(in: .whitespaces).lowercased() == "bug" }.count

            return VersionMetrics(
                version: version,
                activeInstalls: installs.count,
                coreActionInstalls: coreNames == nil ? nil : core.count,
                unstableInstalls: stabilityKnown ? unstable.count : nil,
                crashReports: crashesInWindow,
                newSignatures: fresh,
                feedback: notes.count,
                bugFeedback: typed.isEmpty ? nil : bugs,
                platforms: Set(group.map(\.platform))
            )
        }

        let latest = metrics(for: latestVersion, includeNewSignatures: true)
        let previous = previousVersion.map { metrics(for: $0, includeNewSignatures: false) }

        // 채택: 최근 7일 활성 설치마다 그 창에서 본 가장 높은 버전.
        var newestByInstall: [String: String] = [:]
        for event in recent where event.occurredAt >= adoptionStart && latestPlatforms.contains(event.platform) {
            guard let install = event.installID, !install.isEmpty else { continue }
            let version = event.appVersion.trimmingCharacters(in: .whitespaces)
            if let seen = newestByInstall[install], !isOlder(seen, than: version) { continue }
            newestByInstall[install] = version
        }
        let adoption = Adoption(onLatest: newestByInstall.values.filter { $0 == latestVersion }.count,
                                active: newestByInstall.count)

        return Report(latest: latest,
                      previous: previous,
                      adoption: adoption,
                      verdict: verdict(latest: latest, previous: previous, thresholds: spec.thresholds),
                      spec: spec,
                      hasReleaseSpec: releaseSpec != nil,
                      stabilityKnown: stabilityKnown,
                      eventsWithoutInstall: recent.filter { ($0.installID ?? "").isEmpty }.count,
                      coverageStart: coverageStart.flatMap { $0 > windowStart ? $0 : nil })
    }

    // MARK: 판정

    /// 최신 버전과 앞 버전의 숫자로 초록 · 노랑 · 빨강을 정한다. 순수 함수다.
    ///
    /// 빨강
    ///  - 최신 버전에서 처음 본 크래시 지문이 보고 2건 이상 (설치 수와 무관하다. 크래시는 크래시다)
    ///  - 크래시 없는 설치 비율이 문턱 아래
    ///  - 핵심 행동률이 앞 버전보다 `coreActionDropMax` 넘게(상대값) 떨어짐
    /// 노랑
    ///  - 최신 버전 활성 설치가 `minInstallsForVerdict` 미만 (비율 판정은 건너뛴다)
    ///  - 견줄 앞 버전이 없음
    ///  - 작은 퇴행: 새 지문 1건 또는 크래시가 아닌 새 지문, 크래시 없는 비율이 앞보다 낮아짐,
    ///    핵심 행동률이 문턱의 절반을 넘게 떨어짐, 설치당 크래시 보고가 늘어남, 버그 피드백이 늘어남
    /// 초록
    ///  - 위 어느 것도 아님
    ///
    /// 앞 버전도 `minInstallsForVerdict` 에 못 미치면 비율끼리 견주지 않는다. 표본 셋의 33% 와
    /// 표본 삼백의 30% 는 같은 말이 아니다.
    static func verdict(latest: VersionMetrics,
                        previous: VersionMetrics?,
                        thresholds: ReleaseSpec.Thresholds) -> Verdict {
        var red: [String] = []
        var yellow: [String] = []
        var green: [String] = []

        // 새 크래시
        let newCrashes = latest.newSignatures.filter(\.isCrash)
        let seriousCrashes = newCrashes.filter { $0.reports >= 2 }
        if let worst = seriousCrashes.first {
            red.append("새 크래시 \(seriousCrashes.count)종이 \(latest.version)에서 처음 났다 (가장 많은 것 \(worst.reports)건)")
        } else if !latest.newSignatures.isEmpty {
            let lone = newCrashes.count
            let other = latest.newSignatures.count - lone
            var parts: [String] = []
            if lone > 0 { parts.append("크래시 \(lone)종(각 1건)") }
            if other > 0 { parts.append("멈춤 · 기타 \(other)종") }
            yellow.append("\(latest.version)에서 처음 본 진단: " + parts.joined(separator: ", "))
        } else {
            green.append("새 크래시 없음")
        }

        let enough = latest.activeInstalls >= thresholds.minInstallsForVerdict
        let previousEnough = (previous?.activeInstalls ?? 0) >= thresholds.minInstallsForVerdict

        if !enough {
            yellow.insert("아직 판단하기 이르다 (최신 버전 활성 설치 \(latest.activeInstalls)대, 판단에 \(thresholds.minInstallsForVerdict)대 필요)", at: 0)
        } else {
            // 안정성
            if let rate = latest.crashFreeRate {
                if rate < thresholds.crashFreeInstallsMin {
                    red.append("크래시 없는 설치 \(percent(rate)), 문턱 \(percent(thresholds.crashFreeInstallsMin)) 아래")
                } else if let before = previous?.crashFreeRate, previousEnough, rate < before - crashFreeWobble {
                    yellow.append("크래시 없는 설치 \(percent(before)) → \(percent(rate))로 내려감")
                } else {
                    green.append("크래시 없는 설치 \(percent(rate))")
                }
            }

            // 핵심 행동
            if let now = latest.coreActionRate {
                if let before = previous?.coreActionRate, previousEnough, before > 0 {
                    let drop = (before - now) / before
                    if drop > thresholds.coreActionDropMax {
                        red.append("핵심 행동률 \(percent(before)) → \(percent(now)) (\(percent(drop)) 떨어짐, 허용 \(percent(thresholds.coreActionDropMax)))")
                    } else if drop > thresholds.coreActionDropMax / 2 {
                        yellow.append("핵심 행동률 \(percent(before)) → \(percent(now)) (\(percent(drop)) 떨어짐)")
                    } else {
                        green.append("핵심 행동률 유지 (\(percent(now)))")
                    }
                } else {
                    green.append("핵심 행동률 \(percent(now))")
                }
            }

            // 설치당 크래시 보고
            if let previous, previousEnough,
               let now = latest.crashDensity, let before = previous.crashDensity,
               latest.crashReports >= 2, now > before * 1.5 {
                yellow.append("설치당 크래시 보고가 늘었다 (\(previous.crashReports)건 → \(latest.crashReports)건)")
            }
        }

        if previous == nil {
            yellow.append("견줄 앞 버전이 최근 \(windowDays)일에 없다")
        } else if let previous, let bugsNow = latest.bugFeedback, bugsNow >= 2, bugsNow > (previous.bugFeedback ?? 0) {
            yellow.append("버그 피드백 \(previous.bugFeedback ?? 0)건 → \(bugsNow)건")
        }

        if !red.isEmpty { return Verdict(level: .red, reasons: red + yellow) }
        if !yellow.isEmpty { return Verdict(level: .yellow, reasons: yellow) }
        return Verdict(level: .green, reasons: [green.joined(separator: " · ")])
    }

    static func percent(_ ratio: Double) -> String {
        // 문턱이 99% 근처라, 90% 위는 소수 한 자리까지 적어야 문턱과 견줄 수 있다.
        let value = ratio * 100
        let needsDecimal = (value >= 90 && value < 100) || (value > 0 && value < 10)
        if needsDecimal, value.rounded() != value {
            // 내림이다. 99.96% 를 반올림해 "100.0%" 로 적으면 한 대도 안 죽은 것처럼 읽힌다.
            return String(format: "%.1f%%", (value * 10).rounded(.down) / 10)
        }
        return "\(Int(value.rounded()))%"
    }
}

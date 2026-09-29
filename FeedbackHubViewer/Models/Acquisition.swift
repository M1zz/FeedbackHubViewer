//
//  Acquisition.swift
//  FeedbackHubViewer
//
//  유입 경로 지도와, 그 지도로 내리는 판정.
//
//  지도 원본은 각 앱 리포의 `docs/engineering/acquisition.json` 이다(사람이 읽는 그림은
//  같은 리포의 `docs/acquisition.html`). `scripts/sync-stats-specs.sh` 가 여기 `Specs/`
//  로 복사해 온다.
//
//  화면은 지도를 늘어놓지 않는다. 퍼널을 세 구역으로 잘라 **앞에서부터** 어디가 새는지
//  가린다 — 앱 구역(받은 사람이 쓰나), 가게 앞(페이지를 본 사람이 받나), 홍보(보기는
//  하나). 앞 구역이 새는데 노출을 늘리면 새는 양동이에 물을 붓는 셈이라 이 차례다.
//  판정은 `AcquisitionDiagnosis.make` 한 곳에서 하고 뷰는 그리기만 한다.
//

import Foundation

// MARK: - 지도

struct AcquisitionMap: Decodable {
    let acquisitionVersion: Int
    let appId: String
    let appName: String?
    let asOf: String?
    let mapURL: URL?
    var appZone: AppZone?
    var storefront: Storefront?
    var channels: [Channel] = []
    var nextSteps: [NextStep] = []

    static let supportedVersion = 1

    struct AppZone: Decodable {
        /// usage-spec 의 사다리 · 퍼널 제목. 그 마지막 칸이 "가치를 받은 설치"다.
        var activation: String?
        /// 사다리 마지막 칸이 이 아래면 앱 구역이 샌다.
        var activationFloor: Double?
        /// 결제 문 앞에 선 설치를 세는 이벤트.
        var paywallEvent: String?
        /// 페이월을 본 설치가 전체 설치의 이 비율 아래면 결제 문이 거의 안 열린다.
        var paywallFloor: Double?
    }

    struct Storefront: Decodable {
        /// 제품 페이지 조회 대비 첫 다운로드가 이 아래면 가게 앞이 샌다.
        var conversionFloor: Double?
        var note: String?
    }

    struct Channel: Decodable, Identifiable {
        let name: String
        var group: String?
        var lands: Lands = .unknown
        var measure: Measure = .none
        var status: Status = .active
        var note: String?
        var id: String { name }

        enum Lands: String, Decodable {
            case search, browse, appReferrer, webReferrer, campaign, unknown
        }
        enum Measure: String, Decodable {
            case separate, mixed, none
        }
        enum Status: String, Decodable {
            case active, planned, unused
        }

        enum CodingKeys: String, CodingKey { case name, group, lands, measure, status, note }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            group = try c.decodeIfPresent(String.self, forKey: .group)
            lands = try c.decodeIfPresent(Lands.self, forKey: .lands) ?? .unknown
            measure = try c.decodeIfPresent(Measure.self, forKey: .measure) ?? .none
            status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .active
            note = try c.decodeIfPresent(String.self, forKey: .note)
        }
    }

    struct NextStep: Decodable, Identifiable {
        let zone: Zone
        let title: String
        var detail: String?
        var done: Bool?
        var id: String { title }
    }

    enum Zone: String, Decodable, CaseIterable {
        case app, storefront, promotion, measurement

        var title: String {
            switch self {
            case .app: return "앱 구역"
            case .storefront: return "가게 앞"
            case .promotion: return "홍보"
            case .measurement: return "재는 법"
            }
        }
        var question: String {
            switch self {
            case .app: return "받은 사람이 쓰고 사나"
            case .storefront: return "페이지를 본 사람이 받나"
            case .promotion: return "사람들이 보기는 하나"
            case .measurement: return "어느 길로 왔는지 아나"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case acquisitionVersion, appId, appName, asOf, mapURL, appZone, storefront, channels, nextSteps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acquisitionVersion = try c.decode(Int.self, forKey: .acquisitionVersion)
        appId = try c.decode(String.self, forKey: .appId)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
        mapURL = try c.decodeIfPresent(URL.self, forKey: .mapURL)
        appZone = try c.decodeIfPresent(AppZone.self, forKey: .appZone)
        storefront = try c.decodeIfPresent(Storefront.self, forKey: .storefront)
        channels = try c.decodeIfPresent([Channel].self, forKey: .channels) ?? []
        nextSteps = try c.decodeIfPresent([NextStep].self, forKey: .nextSteps) ?? []
    }

    var activeChannels: [Channel] { channels.filter { $0.status == .active } }
}

// MARK: - 목록

/// 번들에 든 유입 지도 전부. 파일 이름이 `*.acquisition.json` 인 것만 읽는다.
enum AcquisitionCatalog {
    static func map(for projectKey: String) -> AcquisitionMap? {
        loaded.maps.first { $0.appId == projectKey } ?? loaded.maps.first { $0.appName == projectKey }
    }

    static var all: [AcquisitionMap] { loaded.maps }

    /// 읽다가 깨진 지도. 없는 것과 깨진 것은 할 일이 달라서 따로 말한다.
    static var failures: [ProjectStatsSpecCatalog.Failure] { loaded.failures }

    static let fileSuffix = ".acquisition.json"

    private static let loaded = load()

    private static func load() -> (maps: [AcquisitionMap], failures: [ProjectStatsSpecCatalog.Failure]) {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(fileSuffix) }
        var maps: [AcquisitionMap] = []
        var failures: [ProjectStatsSpecCatalog.Failure] = []
        for url in urls {
            do {
                let map = try JSONDecoder().decode(AcquisitionMap.self, from: Data(contentsOf: url))
                guard map.acquisitionVersion == AcquisitionMap.supportedVersion else {
                    failures.append(.init(file: url.lastPathComponent,
                                          reason: "이 뷰어가 모르는 acquisitionVersion \(map.acquisitionVersion)입니다."))
                    continue
                }
                maps.append(map)
            } catch {
                failures.append(.init(file: url.lastPathComponent, reason: String(describing: error)))
            }
        }
        return (maps, failures)
    }
}

// MARK: - 판정

/// 한 앱의 유입을 한 줄로. **숫자를 늘어놓지 않고 결론을 먼저** 준다.
struct AcquisitionDiagnosis {

    enum State: Int, Comparable {
        /// 이 구역이 샌다 — 지금 손댈 곳.
        case leaking
        /// 선보다 낮진 않지만 목표에도 못 미친다.
        case watch
        /// 괜찮다.
        case healthy
        /// 모른다. 괜찮다는 뜻이 아니다.
        case unknown

        static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }
    }

    struct Reading: Identifiable {
        let zone: AcquisitionMap.Zone
        let state: State
        /// 이 구역을 대표하는 숫자 하나. 모르면 nil.
        let figure: String?
        /// 그 숫자가 무슨 뜻인지 한 문장.
        let meaning: String
        var id: AcquisitionMap.Zone { zone }
    }

    let readings: [Reading]
    /// 앞에서부터 처음 새는 구역. 없으면 nil.
    let leak: AcquisitionMap.Zone?
    /// 맨 위 한 줄.
    let headline: String
    let headlineState: State
    /// 지금 할 일 하나 — 새는 구역의 첫 할 일, 없으면 재는 법의 첫 할 일.
    let action: AcquisitionMap.NextStep?
    /// 받는 사람이 어디서 오나, 한 문장.
    let sourceMix: String?
    /// 유입 추세. ASC 리포트가 있어야 안다.
    let inflow: Inflow?
    /// 검색 처방. 메타데이터와 순위가 있어야 나온다.
    let aso: ASOPrescription?
    /// 판단하려면 넣어야 할 것.
    let missing: [MissingInput]

    // MARK: 입력

    /// 앱 구역 사다리에서 읽은 것.
    struct Ladder {
        let label: String
        /// 마지막 칸 / 첫 칸.
        let reached: Double
        /// 가장 많이 새는 칸과 그 칸의 통과율.
        let worstStep: String?
        let worstPass: Double?
        let base: Int
    }

    struct Paywall {
        let installs: Int
        let total: Int
    }

    struct Store {
        let impressions: Int
        let pageViews: Int
        let firstDownloads: Int
        let days: Int
        /// 원문 소스 이름 → 첫 다운로드.
        let downloadsBySource: [String: Int]
        /// 원문 소스 이름 → 노출.
        var impressionsBySource: [String: Int] = [:]
        /// 원문 소스 이름 → 페이지 조회.
        var pageViewsBySource: [String: Int] = [:]
        /// 날짜(yyyy-MM-dd) → 첫 다운로드.
        var dailyDownloads: [String: Int] = [:]
    }

    /// 판단에 필요한데 아직 없는 입력. 뷰가 종류마다 바로 누를 단추를 단다.
    struct MissingInput: Identifiable {
        enum Kind: String {
            case ascKey, analyticsRequest, analyticsPending, metadata
            case storeLink, noKeywords, untrackedTerms, staleRanks, ladder
        }
        let kind: Kind
        let title: String
        let why: String
        var terms: [String] = []
        var id: String { kind.rawValue }
    }

    /// 유입이 느는지 주는지. 첫 다운로드 최근 7일과 그 앞 7일.
    struct Inflow {
        let last7: Int
        let previous7: Int
        var perDay: Double { Double(last7) / 7 }
        var change: Double? { previous7 > 0 ? Double(last7 - previous7) / Double(previous7) : nil }
        var isFalling: Bool { (change ?? 0) <= -0.2 }
        var isStalled: Bool { last7 < 7 }
    }

    // MARK: 계산

    static func make(map: AcquisitionMap, ladder: Ladder?, paywall: Paywall?, store: Store?,
                     aso: ASOPrescription? = nil, missing: [MissingInput] = []) -> AcquisitionDiagnosis {
        var readings: [Reading] = []
        let inflow = store.flatMap(inflow(of:))

        // 1. 앱 구역 — 받은 사람이 가치를 받나, 그리고 결제 문 앞에 서나.
        readings.append(appReading(map: map, ladder: ladder, paywall: paywall))

        // 2. 가게 앞 — 페이지를 본 사람이 받나.
        readings.append(storefrontReading(map: map, store: store))

        // 3. 홍보 — 보기는 하나. 절대 기준이 없어서 앞 구역이 괜찮을 때만 의심한다.
        let frontOK = readings.allSatisfy { $0.state == .healthy || $0.state == .watch }
        readings.append(promotionReading(store: store, frontOK: frontOK, inflow: inflow, aso: aso))

        // 4. 재는 법 — 새는 곳과 별개로, 어느 길이 효과가 있었는지 알 수 있나.
        readings.append(measurementReading(map: map))

        let order: [AcquisitionMap.Zone] = [.app, .storefront, .promotion]
        let leak = order.first { zone in readings.first { $0.zone == zone }?.state == .leaking }

        let known = readings.filter { order.contains($0.zone) && $0.state != .unknown }.count
        var headline: String
        let headlineState: State
        if let leak, let reading = readings.first(where: { $0.zone == leak }) {
            headline = "\(leak.title)이 샙니다. \(reading.meaning)"
            headlineState = .leaking
        } else if known == 0, let first = missing.first {
            headline = "판단할 재료가 없습니다. \(first.title)부터 해 주세요."
            headlineState = .unknown
        } else if readings.filter({ order.contains($0.zone) }).contains(where: { $0.state == .unknown }) {
            let unknown = readings.filter { order.contains($0.zone) && $0.state == .unknown }.map(\.zone.title)
            headline = "뚜렷하게 새는 곳은 없지만 \(unknown.joined(separator: " · "))은 아직 모릅니다."
            headlineState = .unknown
        } else {
            headline = "세 구역 모두 선 위에 있습니다. 이제 노출을 늘릴 차례입니다."
            headlineState = .healthy
        }
        if let inflow, inflow.isFalling, let change = inflow.change {
            headline = "유입이 지난주보다 \(percent(-change)) 줄었습니다. " + headline
        }

        let pending = map.nextSteps.filter { $0.done != true }
        var action = leak.flatMap { zone in pending.first { $0.zone == zone } }
        // 검색으로 들어오는 길이 새는 구역이면, 지도의 일반 할 일보다 계산한 처방이 먼저다.
        if leak == .storefront || leak == .promotion || (leak == nil && inflow?.isFalling == true),
           let aso, let title = aso.headline {
            action = .init(zone: .promotion, title: title,
                           detail: "지금 필드에서 안 잡히는 단어를 이미 순위가 있거나 경쟁 앱들이 쓰는 말로 바꿉니다. 아래 '검색 처방'에서 바로 고칠 수 있어요.")
        }
        if action == nil, known == 0, let first = missing.first {
            action = .init(zone: .measurement, title: first.title, detail: first.why)
        }
        if action == nil {
            action = pending.first { $0.zone == .measurement } ?? pending.first
        }

        return AcquisitionDiagnosis(readings: readings, leak: leak, headline: headline,
                                    headlineState: headlineState, action: action,
                                    sourceMix: sourceMix(store: store),
                                    inflow: inflow, aso: aso, missing: missing)
    }

    private static func appReading(map: AcquisitionMap, ladder: Ladder?, paywall: Paywall?) -> Reading {
        let floor = map.appZone?.activationFloor
        let paywallFloor = map.appZone?.paywallFloor ?? 0.05

        if let ladder, ladder.base > 0 {
            let where_ = ladder.worstStep.map { step in
                " 제일 크게 새는 칸은 \"\(step)\"" + (ladder.worstPass.map { "(앞 칸의 \(percent($0))만 넘어옴)" } ?? "") + "입니다."
            } ?? ""
            if let floor, ladder.reached < floor {
                return Reading(zone: .app, state: .leaking, figure: percent(ladder.reached),
                               meaning: "받은 설치 중 \(percent(ladder.reached))만 \"\(ladder.label)\" 끝까지 갑니다. 이 앱이 정한 하한 \(percent(floor)) 아래예요." + where_)
            }
            if let paywall, paywall.total > 0 {
                let seen = Double(paywall.installs) / Double(paywall.total)
                if seen < paywallFloor {
                    return Reading(zone: .app, state: .leaking, figure: percent(seen),
                                   meaning: "쓰는 사람은 있지만 결제 문 앞에 선 설치가 \(percent(seen))(\(paywall.installs)대)뿐입니다. 결제 설계 문제예요.")
                }
            }
            return Reading(zone: .app, state: floor == nil ? .watch : .healthy, figure: percent(ladder.reached),
                           meaning: "받은 설치 중 \(percent(ladder.reached))가 \"\(ladder.label)\" 끝까지 갑니다.")
        }

        if let paywall, paywall.total > 0 {
            let seen = Double(paywall.installs) / Double(paywall.total)
            if seen < paywallFloor {
                return Reading(zone: .app, state: .leaking, figure: percent(seen),
                               meaning: "결제 문 앞에 선 설치가 \(percent(seen))(\(paywall.installs)대)뿐입니다.")
            }
        }
        let why = map.appZone?.activation == nil
            ? "지도에 앱 구역 사다리가 없습니다."
            : "사다리 \"\(map.appZone?.activation ?? "")\"의 값을 보낸 설치가 아직 없습니다."
        return Reading(zone: .app, state: .unknown, figure: nil, meaning: why)
    }

    private static func storefrontReading(map: AcquisitionMap, store: Store?) -> Reading {
        guard let store, store.pageViews > 0 else {
            return Reading(zone: .storefront, state: .unknown, figure: nil,
                           meaning: store == nil
                           ? "App Store Connect 노출 리포트가 아직 없습니다."
                           : "최근 \(store?.days ?? 30)일 제품 페이지 조회가 0입니다.")
        }
        let conversion = Double(store.firstDownloads) / Double(store.pageViews)
        let text = "제품 페이지를 본 사람 중 \(percent(conversion))가 받습니다"
        guard let floor = map.storefront?.conversionFloor else {
            return Reading(zone: .storefront, state: .watch, figure: percent(conversion), meaning: text + ". 견줄 선이 없어 판정은 미룹니다.")
        }
        if conversion < floor {
            return Reading(zone: .storefront, state: .leaking, figure: percent(conversion),
                           meaning: text + ". 선 \(percent(floor)) 아래라 스크린샷 첫 장 · 부제 · 리뷰 수를 먼저 봅니다.")
        }
        return Reading(zone: .storefront, state: .healthy, figure: percent(conversion), meaning: text + ".")
    }

    private static func promotionReading(store: Store?, frontOK: Bool, inflow: Inflow?,
                                         aso: ASOPrescription?) -> Reading {
        guard let store, store.impressions > 0 else {
            return Reading(zone: .promotion, state: .unknown, figure: nil,
                           meaning: "노출 수를 아직 못 받았습니다.")
        }
        let perDay = Double(store.impressions) / Double(max(store.days, 1))
        let figure = "하루 \(AppFormat.count(Int(perDay.rounded())))"
        var text = "하루 \(AppFormat.count(Int(perDay.rounded())))명이 스토어에서 봅니다."

        // 검색이 노출의 대부분인데 잘 잡히는 검색어가 적으면 홍보보다 ASO 가 먼저다.
        let searchImpressions = store.impressionsBySource["App Store search"] ?? 0
        let searchShare = Double(searchImpressions) / Double(store.impressions)
        let fewTop = (aso?.topTen.count ?? 0) < 3
        if let inflow {
            text += " 첫 다운로드는 하루 \(String(format: "%.1f", inflow.perDay))건"
            if let change = inflow.change {
                text += change >= 0 ? "(지난주 대비 ▲\(percent(change)))" : "(지난주 대비 ▼\(percent(-change)))"
            }
            text += "."
        }
        if searchShare >= 0.5, fewTop, let aso {
            text += " 노출의 \(percent(searchShare))가 검색인데 상위 10에 드는 검색어가 \(aso.topTen.count)개뿐이라 키워드부터 고칩니다."
            return Reading(zone: .promotion, state: .leaking, figure: figure, meaning: text)
        }
        if inflow?.isFalling == true || inflow?.isStalled == true {
            text += frontOK ? " 앞 구역이 괜찮으니 노출이 병목입니다." : " 다만 앞 구역부터 고쳐야 늘린 노출이 남습니다."
            return Reading(zone: .promotion, state: frontOK ? .leaking : .watch, figure: figure, meaning: text)
        }
        if frontOK {
            return Reading(zone: .promotion, state: .leaking, figure: figure,
                           meaning: text + " 앞 구역이 괜찮으니 이제 노출이 병목입니다.")
        }
        return Reading(zone: .promotion, state: .watch, figure: figure,
                       meaning: text + " 앞 구역이 새는 동안 노출을 늘려도 새는 양동이에 붓는 셈이에요.")
    }

    private static func inflow(of store: Store) -> Inflow? {
        guard !store.dailyDownloads.isEmpty else { return nil }
        let days = store.dailyDownloads.keys.sorted()
        guard let latest = days.last else { return nil }
        // 리포트는 하루 이틀 늦게 오므로 "오늘"이 아니라 마지막으로 온 날을 기준으로 자른다.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let end = f.date(from: latest) else { return nil }
        func sum(_ from: Int, _ to: Int) -> Int {
            (from..<to).reduce(0) { total, offset in
                let day = f.string(from: end.addingTimeInterval(-Double(offset) * 86_400))
                return total + (store.dailyDownloads[day] ?? 0)
            }
        }
        return Inflow(last7: sum(0, 7), previous7: sum(7, 14))
    }

    private static func measurementReading(map: AcquisitionMap) -> Reading {
        let active = map.activeChannels
        guard !active.isEmpty else {
            return Reading(zone: .measurement, state: .unknown, figure: nil, meaning: "지도에 쓰는 길이 없습니다.")
        }
        let separate = active.filter { $0.measure == .separate }.count
        let blind = active.filter { $0.measure == .none }.map(\.name)
        var text = "쓰는 길 \(active.count)개 중 따로 세는 길은 \(separate)개입니다."
        if !blind.isEmpty { text += " \(blind.joined(separator: " · "))은 아예 못 셉니다." }
        text += " 어느 글이 효과가 있었는지는 날짜로 짐작하는 수밖에 없어요."
        let share = Double(separate) / Double(active.count)
        return Reading(zone: .measurement, state: share < 0.5 ? .leaking : .healthy,
                       figure: "\(separate)/\(active.count)", meaning: separate == active.count
                       ? "쓰는 길 \(active.count)개를 모두 따로 셉니다." : text)
    }

    private static func sourceMix(store: Store?) -> String? {
        guard let store else { return nil }
        let total = store.downloadsBySource.values.reduce(0, +)
        guard total > 0, let top = store.downloadsBySource.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(top.value) / Double(total)
        let meaning: String
        switch top.key {
        case "App Store search": meaning = "이름이나 키워드로 찾아온 사람입니다. 말로 들은 사람도 여기 섞여요"
        case "App Store browse": meaning = "스토어가 보여 줘서 온 사람입니다"
        case "Web referrer": meaning = "글이나 웹 페이지를 보고 온 사람입니다"
        case "App referrer": meaning = "다른 앱(메신저 · SNS)에서 링크를 누른 사람입니다"
        default: meaning = "어디서 왔는지 모르는 사람입니다"
        }
        return "첫 다운로드의 \(percent(share))가 \(StoreFunnel.label(forSource: top.key))에서 옵니다. \(meaning)."
    }

    static func percent(_ ratio: Double) -> String {
        let scaled = ratio * 100
        return scaled < 10 ? String(format: "%.1f%%", scaled) : String(format: "%.0f%%", scaled.rounded())
    }
}

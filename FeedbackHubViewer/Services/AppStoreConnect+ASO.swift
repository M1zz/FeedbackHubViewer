//
//  AppStoreConnect+ASO.swift
//  FeedbackHubViewer
//
//  ASO에 쓰는 App Store Connect 요청 — 스토어 메타데이터(이름 · 부제 · 키워드 ·
//  프로모션 텍스트)를 읽고 쓰는 것과, App Store 노출 · 다운로드 리포트를 받는 것.
//
//  메타데이터는 두 벌이 있을 수 있다. 지금 스토어에 나가 있는 것(검색이 지금 읽는
//  것)과, 다음 버전으로 준비 중인 것(고칠 수 있는 것). 대조는 앞의 것으로 하고,
//  고치는 것은 뒤의 것에 한다. 프로모션 텍스트만은 나가 있는 버전에서도 바로 고쳐진다.
//
//  노출 리포트를 받는 일(요청 · 인스턴스 · 날짜마다 한 벌)은 공통 층이 한다
//  (`AppStoreConnect+AnalyticsReports.swift`). 여기는 그 행을 퍼널로 읽기만 한다.
//

import Foundation

// MARK: - 메타데이터 모델

/// 한 앱의 스토어 메타데이터 — 나가 있는 것과, 고칠 수 있는 것.
struct StoreMetadata {
    /// 지금 스토어에 나가 있는 버전과 앱 정보.
    let live: Edition
    /// 고칠 수 있는 버전 · 앱 정보. 없으면 새 버전을 만들어야 키워드 · 이름 · 부제를 고친다.
    let draft: Edition?

    struct Edition {
        let versionID: String?
        let versionString: String?
        let versionState: String?
        let appInfoID: String?
        let appInfoState: String?
        /// 로케일 → 값.
        let locales: [String: LocaleText]

        /// 키워드 · 프로모션 텍스트를 고칠 수 있는 버전인가.
        var isVersionEditable: Bool { versionState.map(StoreMetadata.editableStates.contains) ?? false }
        /// 이름 · 부제를 고칠 수 있는가.
        var isAppInfoEditable: Bool { appInfoState.map(StoreMetadata.editableStates.contains) ?? false }
    }

    /// 한 로케일의 글. 필드마다 그 필드가 사는 리소스의 id를 같이 든다 — 고칠 때 쓴다.
    struct LocaleText: Hashable {
        let locale: String
        var appInfoLocalizationID: String?
        var versionLocalizationID: String?
        var name = ""
        var subtitle = ""
        var keywords = ""
        var promotionalText = ""
    }

    static let editableStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "INVALID_BINARY"
    ]

    /// 필드마다 스토어가 받는 최대 글자 수.
    enum Limit {
        static let name = 30
        static let subtitle = 30
        static let keywords = 100
        static let promotionalText = 170
    }

    var locales: [String] { live.locales.keys.sorted() }
}

/// 고칠 것 한 로케일 치. nil인 필드는 안 건드린다.
struct MetadataEdit {
    let locale: String
    var name: String?
    var subtitle: String?
    var keywords: String?
    var promotionalText: String?

    var isEmpty: Bool { name == nil && subtitle == nil && keywords == nil && promotionalText == nil }
}

// MARK: - 노출 · 전환 모델

/// 최근 N일의 App Store 퍼널 — 경로별 노출 → 페이지 조회 → 첫 다운로드.
struct StoreFunnel {
    let days: Int
    /// 경로 이름(리포트 원문) → 수.
    let sources: [String: Counts]
    /// 날짜(yyyy-MM-dd) → 검색 노출 · 첫 다운로드. 추이 차트용.
    let daily: [String: Counts]
    /// 받은 리포트 인스턴스 수 — 0이면 아직 리포트가 안 만들어졌다.
    let instances: Int

    struct Counts {
        var impressions = 0
        var pageViews = 0
        var firstDownloads = 0

        /// 노출 대비 첫 다운로드.
        var conversion: Double? {
            impressions > 0 ? Double(firstDownloads) / Double(impressions) : nil
        }

        mutating func add(_ other: Counts) {
            impressions += other.impressions
            pageViews += other.pageViews
            firstDownloads += other.firstDownloads
        }
    }

    var total: Counts {
        sources.values.reduce(into: Counts()) { $0.add($1) }
    }

    /// 경로 원문을 사람 말로.
    static func label(forSource source: String) -> String {
        switch source {
        case "App Store search": return "App Store 검색"
        case "App Store browse": return "App Store 둘러보기"
        case "App referrer": return "다른 앱에서"
        case "Web referrer": return "웹에서"
        case "Unavailable": return "경로 모름"
        default: return source
        }
    }
}

// MARK: - 요청

extension AppStoreConnect {

    // MARK: 메타데이터

    func metadata(appID: String) async throws -> StoreMetadata {
        let infos = try await list("v1/apps/\(appID)/appInfos", ["fields[appInfos]": "state"])
        let versions = try await list("v1/apps/\(appID)/appStoreVersions", [
            "filter[platform]": "IOS",
            "fields[appStoreVersions]": "versionString,appVersionState,createdDate",
            "limit": "10"
        ])

        let liveStates: Set<String> = ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"]
        let sortedVersions = versions.data.sorted { ($0.string("createdDate") ?? "") > ($1.string("createdDate") ?? "") }
        let liveVersion = sortedVersions.first { liveStates.contains($0.string("appVersionState") ?? "") } ?? sortedVersions.first
        let draftVersion = sortedVersions.first { StoreMetadata.editableStates.contains($0.string("appVersionState") ?? "") }

        let liveInfo = infos.data.first { liveStates.contains($0.string("state") ?? "") } ?? infos.data.first
        let draftInfo = infos.data.first { StoreMetadata.editableStates.contains($0.string("state") ?? "") }

        let live = try await edition(version: liveVersion, info: liveInfo)
        var draft: StoreMetadata.Edition?
        if draftVersion != nil || draftInfo != nil {
            // 고칠 수 있는 쪽이 한 반쪽만 있으면(예: 버전만 새로 만듦) 나머지 반쪽은 나가 있는 것을 쓴다.
            draft = try await edition(version: draftVersion ?? liveVersion, info: draftInfo ?? liveInfo)
        }
        return StoreMetadata(live: live, draft: draft)
    }

    private func edition(version: ASCResource?, info: ASCResource?) async throws -> StoreMetadata.Edition {
        var locales: [String: StoreMetadata.LocaleText] = [:]
        if let info {
            let doc = try await list("v1/appInfos/\(info.id)/appInfoLocalizations", [
                "fields[appInfoLocalizations]": "locale,name,subtitle", "limit": "50"
            ])
            for item in doc.data {
                guard let locale = item.string("locale") else { continue }
                var text = locales[locale] ?? StoreMetadata.LocaleText(locale: locale)
                text.appInfoLocalizationID = item.id
                text.name = item.string("name") ?? ""
                text.subtitle = item.string("subtitle") ?? ""
                locales[locale] = text
            }
        }
        if let version {
            let doc = try await list("v1/appStoreVersions/\(version.id)/appStoreVersionLocalizations", [
                "fields[appStoreVersionLocalizations]": "locale,keywords,promotionalText", "limit": "50"
            ])
            for item in doc.data {
                guard let locale = item.string("locale") else { continue }
                var text = locales[locale] ?? StoreMetadata.LocaleText(locale: locale)
                text.versionLocalizationID = item.id
                text.keywords = item.string("keywords") ?? ""
                text.promotionalText = item.string("promotionalText") ?? ""
                locales[locale] = text
            }
        }
        return StoreMetadata.Edition(versionID: version?.id,
                                     versionString: version?.string("versionString"),
                                     versionState: version?.string("appVersionState"),
                                     appInfoID: info?.id,
                                     appInfoState: info?.string("state"),
                                     locales: locales)
    }

    /// 한 로케일을 고친다. 이름 · 부제는 앱 정보에, 키워드 · 프로모션 텍스트는 버전에 산다.
    func save(_ edit: MetadataEdit, appInfoLocalizationID: String?, versionLocalizationID: String?,
              promoVersionLocalizationID: String?) async throws {
        var info: [String: Any] = [:]
        if let name = edit.name { info["name"] = name }
        if let subtitle = edit.subtitle { info["subtitle"] = subtitle }
        if !info.isEmpty {
            guard let id = appInfoLocalizationID else { throw Failure.missing("고칠 수 있는 앱 정보") }
            _ = try await write("PATCH", "v1/appInfoLocalizations/\(id)", body: [
                "data": ["type": "appInfoLocalizations", "id": id, "attributes": info]
            ])
        }
        if let keywords = edit.keywords {
            guard let id = versionLocalizationID else { throw Failure.missing("고칠 수 있는 버전") }
            _ = try await write("PATCH", "v1/appStoreVersionLocalizations/\(id)", body: [
                "data": ["type": "appStoreVersionLocalizations", "id": id, "attributes": ["keywords": keywords]]
            ])
        }
        if let promo = edit.promotionalText {
            // 프로모션 텍스트는 나가 있는 버전에서도 바로 고쳐진다 — 심사 없이.
            guard let id = promoVersionLocalizationID ?? versionLocalizationID else { throw Failure.missing("버전") }
            _ = try await write("PATCH", "v1/appStoreVersionLocalizations/\(id)", body: [
                "data": ["type": "appStoreVersionLocalizations", "id": id, "attributes": ["promotionalText": promo]]
            ])
        }
    }

    // MARK: 노출 · 다운로드 퍼널

    /// 최근 `days`일의 퍼널 — 경로별 노출 → 페이지 조회 → 첫 다운로드. 행은 공통 층이
    /// 날짜마다 한 벌씩 모아 준다(`AppStoreConnect+AnalyticsReports.swift`).
    func funnel(requestID: String, appID: String, days: Int) async throws -> StoreFunnel {
        let engagement = try await analyticsRows(.engagementStandard, requestID: requestID, appID: appID, days: days)
        let downloads = try await analyticsRows(.downloadsStandard, requestID: requestID, appID: appID, days: days)

        var sources: [String: StoreFunnel.Counts] = [:]
        var daily: [String: StoreFunnel.Counts] = [:]
        func add(_ counts: StoreFunnel.Counts, source: String, date: String) {
            sources[source, default: .init()].add(counts)
            // 날짜별 추이는 검색 노출과 (모든 경로의) 첫 다운로드만 그린다.
            var day = counts
            if source != "App Store search" { day.impressions = 0; day.pageViews = 0 }
            daily[date, default: .init()].add(day)
        }

        for (date, rows) in engagement.byDate {
            for row in rows {
                let unique = Int(row["Unique Counts"] ?? "") ?? Int(row["Counts"] ?? "") ?? 0
                var counts = StoreFunnel.Counts()
                switch row["Event"] {
                case "Impression": counts.impressions = unique
                case "Page view": counts.pageViews = unique
                default: continue
                }
                add(counts, source: row["Source Type"] ?? "Unavailable", date: date)
            }
        }
        for (date, rows) in downloads.byDate {
            for row in rows where row["Download Type"] == "First-time download" {
                var counts = StoreFunnel.Counts()
                counts.firstDownloads = Int(row["Counts"] ?? "") ?? 0
                add(counts, source: row["Source Type"] ?? "Unavailable", date: date)
            }
        }
        return StoreFunnel(days: days, sources: sources, daily: daily,
                           instances: engagement.instances + downloads.instances)
    }
}

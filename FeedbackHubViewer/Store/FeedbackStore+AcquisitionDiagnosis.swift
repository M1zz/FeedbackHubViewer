//
//  FeedbackStore+AcquisitionDiagnosis.swift
//  FeedbackHubViewer
//
//  유입 판정의 입력 모으기 — 지도 · 사용 통계 · App Store Connect · 키워드 순위를 한데 모아 `AcquisitionDiagnosis` 로 넘긴다.
//

import Foundation

// MARK: - 입력 모으기

extension FeedbackStore {
    /// 지도 · 사용 통계 · App Store Connect · 키워드 순위를 한데 모아 판정한다.
    @MainActor
    func acquisitionDiagnosis(for project: String, map: AcquisitionMap,
                              connect: AppStoreConnectStore,
                              keywords: KeywordStore) -> AcquisitionDiagnosis {
        var missing: [AcquisitionDiagnosis.MissingInput] = []
        var storeInput: AcquisitionDiagnosis.Store?

        if !connect.isConfigured {
            missing.append(.init(kind: .ascKey, title: "App Store Connect 키 넣기",
                                 why: "노출 · 페이지 조회 · 첫 다운로드와 지금 키워드 필드를 여기서 읽어야 가게 앞과 홍보를 판정합니다."))
        } else {
            switch connect.funnels[project] {
            case .loaded(.noRequest)?:
                missing.append(.init(kind: .analyticsRequest, title: "App Store 분석 리포트 요청 만들기",
                                     why: "한 번만 하면 1~2일 뒤부터 하루치씩 쌓입니다. 이게 있어야 유입이 느는지 주는지 압니다."))
            case .loaded(.ready(let funnel))?:
                if funnel.instances == 0 {
                    missing.append(.init(kind: .analyticsPending, title: "리포트가 쌓이기를 기다리기",
                                         why: "요청은 있지만 아직 파일이 없습니다. 1~2일 걸립니다."))
                } else {
                    let total = funnel.total
                    storeInput = .init(impressions: total.impressions, pageViews: total.pageViews,
                                       firstDownloads: total.firstDownloads, days: funnel.days,
                                       downloadsBySource: funnel.sources.mapValues(\.firstDownloads),
                                       impressionsBySource: funnel.sources.mapValues(\.impressions),
                                       pageViewsBySource: funnel.sources.mapValues(\.pageViews),
                                       dailyDownloads: funnel.daily.mapValues(\.firstDownloads))
                }
            default:
                break
            }
            if case .failed(let message)? = connect.metadata[project] {
                missing.append(.init(kind: .metadata, title: "스토어 메타데이터 다시 읽기", why: message))
            }
        }

        // 검색 처방 ----------------------------------------------------------
        let country = keywords.countries.first ?? "kr"
        var aso: ASOPrescription?
        if keywords.storeApp(for: project) == nil {
            missing.append(.init(kind: .storeLink, title: "키워드 탭에서 이 앱을 App Store 와 잇기",
                                 why: "이어야 검색어마다 이 앱의 순위를 잴 수 있습니다."))
        } else {
            let standings = keywords.standings(for: project).filter { $0.keyword.country == country }
            if standings.isEmpty {
                missing.append(.init(kind: .noKeywords, title: "키워드 자동 찾기 돌리기",
                                     why: "추적하는 검색어가 없어 무엇을 빼고 넣을지 판단할 수 없습니다. 경쟁 앱 이름에서 후보를 뽑아 실제로 검색해 봅니다(30초쯤)."))
            } else {
                let latest = standings.compactMap(\.seenAt).max()
                if let latest, Date().timeIntervalSince(latest) > 7 * 86_400 {
                    let days = Int(Date().timeIntervalSince(latest) / 86_400)
                    missing.append(.init(kind: .staleRanks, title: "키워드 순위 다시 확인하기",
                                         why: "마지막으로 잰 지 \(days)일 됐습니다. 낡은 순위로 빼고 넣으면 틀립니다."))
                }
            }
            if let metadata = connect.metadata[project]?.value,
               let locale = MetadataAudit.locale(forStorefront: country, available: metadata.locales),
               let text = metadata.live.locales[locale] {
                let rankings = standings.map {
                    ASOPrescription.Ranking(term: $0.keyword.term, rank: $0.rank,
                                            unchecked: $0.rank == nil && $0.resultCount == 0)
                }
                let rivals = keywords.competitors(for: project).filter { $0.timesAbove > 0 }.map(\.app.name)
                let prescription = ASOPrescription.make(text: text, rankings: rankings, rivalNames: rivals)
                aso = prescription
                if !prescription.untracked.isEmpty {
                    missing.append(.init(kind: .untrackedTerms,
                                         title: "키워드 필드의 \(prescription.untracked.count)개 단어 순위 재기",
                                         why: "순위를 모르는 단어는 뺄지 남길지 판단하지 않았습니다.",
                                         terms: prescription.untracked))
                }
            }
        }

        if map.appZone?.activation != nil, acquisitionLadder(for: project, map: map) == nil {
            missing.append(.init(kind: .ladder, title: "앱 구역 사다리 값 받기",
                                 why: "지도가 가리키는 \"\(map.appZone?.activation ?? "")\" 칸을 보낸 설치가 아직 없습니다. 새 버전이 퍼지면 채워집니다."))
        }

        return AcquisitionDiagnosis.make(map: map,
                                         ladder: acquisitionLadder(for: project, map: map),
                                         paywall: acquisitionPaywall(for: project, map: map),
                                         store: storeInput, aso: aso, missing: missing)
    }
}

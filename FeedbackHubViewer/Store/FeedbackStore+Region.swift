//
//  FeedbackStore+Region.swift
//  FeedbackHubViewer
//
//  무리 고르개의 셋째 축 — 나라. 그리고 나라끼리 남는지를 나란히 놓은 비교.
//
//  왜 필요한가: 해외 유입은 대부분 코드 캠페인 며칠에 몰려 들어온다(대만 · 홍콩 ·
//  미국 · 중국). 들어온 수는 App Store 판매 리포트가 나라별로 말해 주지만, **들어온
//  사람이 남는지**는 거기 없다. 현지화에 품을 쓸지 정하려면 그 나라 사람이 다음 날,
//  일주일 뒤에도 오는지를 봐야 한다.
//
//  ── 나라는 어디서 오는가 ──
//
//  스냅샷의 `locale`이다(LeeoKit이 `Locale.current.identifier`를 보낸다). 이건
//  **기기의 지역 설정**이지 App Store 국가가 아니다. 대부분 같지만, 한국어 기기를
//  미국 계정으로 쓰는 사람처럼 어긋나는 경우가 있다. 지역 설정을 언어와 따로 바꾼
//  기기는 `@rg=twzzzz` 꼬리로 오고, `Locale.region`이 그것을 먼저 읽는다.
//
//  지역이 없는 locale("en")과 나라가 아닌 지역("419" 라틴아메리카, "001" 세계)은
//  어느 나라에도 넣지 않고 모름으로 센다 — 없는 나라를 지어내지 않는다.
//
//  스냅샷은 설치당 한 줄이고 최신으로 덮이므로, 여행 중에 지역을 바꾼 기기는
//  마지막 값의 나라로 잡힌다. 그 정도 흔들림은 이 질문에서 무시할 만하다.
//

import Foundation

extension FeedbackStore {

    // MARK: - 나라 코드

    /// locale 식별자에서 ISO 두 글자 나라 코드. 나라를 말하지 않으면 `nil`.
    nonisolated static func regionCode(_ locale: String) -> String? {
        guard let code = Locale(identifier: locale).region?.identifier,
              code.count == 2, code.allSatisfy(\.isLetter) else { return nil }
        return code.uppercased()
    }

    /// 화면에 적을 나라 이름. 한국어로, 모르는 코드는 코드 그대로.
    nonisolated static func regionName(_ code: String) -> String {
        Locale(identifier: "ko_KR").localizedString(forRegionCode: code) ?? code
    }

    // MARK: - 나라끼리 비교

    /// 한 나라의 한 줄.
    struct RegionRow: Identifiable {
        let code: String
        let installs: Int
        /// 코호트를 합친 1 · 7 · 30일 잔존(`Retention.pooled`).
        let pooled: [Retention.Checkpoint: Retention.Rate]

        var id: String { code }
        var name: String { FeedbackStore.regionName(code) }
    }

    /// 나라끼리 견줄 때 줄에 세우는 최소 설치 수. 이보다 적으면 한두 대가 옮겨도
    /// 순서가 뒤집혀서, 비교가 아니라 우연을 보여 준다.
    static let regionMinimumInstalls = 20
    /// 비교 줄의 최대 개수. 나머지는 고르개 메뉴에서 하나씩 볼 수 있다.
    static let regionComparisonLimit = 8

    /// 설치가 충분한 나라마다 잔존을 잰 것. 설치가 많은 나라부터.
    ///
    /// 나라마다 무리 고르개로 고른 것과 똑같은 계산(`retention(for:audience:)`)을 쓴다.
    /// 그래서 이 줄의 숫자와 그 나라를 골랐을 때 잔존 카드의 숫자가 언제나 같다.
    func regionComparison(for project: String?) -> [RegionRow] {
        let installs = audienceInstalls(for: project)
        return installs.regionOrder
            .filter { (installs.regions[$0]?.count ?? 0) >= Self.regionMinimumInstalls }
            .prefix(Self.regionComparisonLimit)
            .map { code in
                RegionRow(code: code,
                          installs: installs.regions[code]?.count ?? 0,
                          pooled: retention(for: project, audience: .region(code)).pooled)
            }
    }
}

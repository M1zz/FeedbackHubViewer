//
//  ActivityDefinition.swift
//  FeedbackHubViewer
//
//  앱마다 "얼마나 자주 쓰여야 하나"와 "무엇을 해야 썼다고 치나".
//
//  DAU · WAU · MAU 셋 중 무엇이 주 지표인지는 앱의 사용 주기가 정한다. 주간 회고 앱을
//  DAU 로 재면 잘 되는데도 실패처럼 보인다. 그리고 "활동"을 앱 실행으로 세면 알림만
//  열심히 보내도 숫자가 부푼다 — 핵심 가치 행동(할 일 완료, 기록 작성)으로 세야 한다.
//
//  어디서 정하나: 앱 리포의 스펙(`activity` 절)이 기본이고, 뷰어의 통계 화면에서
//  고르면 그것이 이긴다(이 기기에만 남는다). 정의를 바꾸면 추세 비교가 깨지므로
//  화면은 바꿀 때 그렇다고 알린다.
//

import Foundation

/// 제품이 원래 얼마나 자주 쓰여야 하나.
enum UsageCycle: String, Codable, CaseIterable, Identifiable {
    /// 투두 · 메신저 · 습관 앱.
    case daily
    /// 주간 회고 · 식단 계획 · 업무 리포트.
    case weekly
    /// 여행 · 세금 · 연휴 계획 — 필요할 때만.
    case occasional

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "매일"
        case .weekly: "매주"
        case .occasional: "가끔"
        }
    }

    /// 이 주기의 주 지표 이름.
    var metricName: String {
        switch self {
        case .daily: "DAU"
        case .weekly: "WAU"
        case .occasional: "MAU"
        }
    }

    var example: String {
        switch self {
        case .daily: "투두 · 메신저 · 습관처럼 매일 여는 앱"
        case .weekly: "주간 회고 · 식단 계획처럼 주 단위 루틴"
        case .occasional: "여행 · 세금처럼 필요할 때만 여는 앱"
        }
    }
}

struct ActivityDefinition: Codable, Equatable {
    /// nil == 아직 안 정함. 화면은 MAU 로 보이고 정하라고 권한다.
    var cycle: UsageCycle?
    /// 이 이벤트(슬라이스 앞부분) 중 하나라도 보낸 날만 "활동한 날"이다. 비면 아무
    /// 이벤트나(앱 실행 포함).
    var valueEvents: [String] = []

    enum CodingKeys: String, CodingKey { case cycle, valueEvents }

    init(cycle: UsageCycle? = nil, valueEvents: [String] = []) {
        self.cycle = cycle
        self.valueEvents = valueEvents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycle = try c.decodeIfPresent(UsageCycle.self, forKey: .cycle)
        valueEvents = try c.decodeIfPresent([String].self, forKey: .valueEvents) ?? []
    }

    var isEmpty: Bool { cycle == nil && valueEvents.isEmpty }
}

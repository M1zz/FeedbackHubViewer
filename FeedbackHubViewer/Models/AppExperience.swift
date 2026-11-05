//
//  AppExperience.swift
//  FeedbackHubViewer
//
//  앱마다 사용자에게 줘야 하는 경험과, 사용자가 이 앱과 함께 꿈꿀 수 있는 모습.
//
//  재료는 셋이다.
//   · 앱 번들의 `app-experience.json` — 꿈꾸는 모습 · 그날의 장면 · 줘야 할 경험 · 주면 안 되는 경험.
//     app-portfolio 에는 이 칸이 없어서 허브가 들고 있다(기존 자료를 근거로 쓴 초안).
//   · app-portfolio 앱 JSON 의 `vision` — 사람이 쓴 핵심 가치 · 경험 목표 · 디자인 원칙(앱 20개쯤)
//   · app-portfolio 의 showcase-content.json — 누구(페르소나)의 어떤 순간(장면)을 푸나
//

import Foundation

struct AppExperience: Decodable {
    let project: String
    /// 사용자가 이 앱과 함께 이룰 수 있는 모습 — 기능이 아니라 사람이 달라진 모습.
    let dream: String
    /// 그 모습의 하루 한 장면.
    let scene: String?
    /// 앱이 꼭 줘야 하는 경험.
    let promises: [String]
    /// 절대 주면 안 되는 경험.
    let avoid: [String]?
    /// app-portfolio 의 vision 이 다른 앱 내용이라 쓰지 않는다.
    let skipVision: Bool?
    /// app-portfolio 의 소개(showcase)가 지금 앱과 맞지 않아 쓰지 않는다.
    let skipShowcase: Bool?
    /// 왜 숨겼는지 — 화면에 그대로 적는다.
    let sourceNote: String?

    static let all: [String: AppExperience] = {
        guard let url = Bundle.main.url(forResource: "app-experience", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([AppExperience].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.project.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }()

    static func of(_ project: String) -> AppExperience? { all[project.lowercased()] }
}

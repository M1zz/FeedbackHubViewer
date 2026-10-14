//
//  EnvironmentBadge.swift
//  FeedbackHubViewer
//
//  Which CloudKit environment the running build reads — and making that
//  impossible to miss.
//
//  There is no in-app switch: CloudKit takes the environment from the
//  `com.apple.developer.icloud-container-environment` entitlement baked into
//  the binary, so it is chosen by picking a scheme (see README §2-1).
//
//  두 빌드를 한 기기에 같이 깔아 두고 오가며 보므로, 지금 어느 쪽 숫자를 보고 있는지가
//  작은 배지 하나에만 걸려 있으면 개발 데이터를 운영 숫자로 읽는 일이 생긴다. 그래서
//  개발 빌드는 화면 전체가 다르게 생겼다 — 강조색이 주황이고(`environmentTint()`),
//  맨 위에 띠가 붙는다(`DevelopmentBanner`). 운영 빌드는 평소 모습에 초록 배지만 단다.
//
//  어느 것도 가게(`FeedbackStore`)를 지켜보지 않는다. 환경은 빌드마다 고정이라 바뀔 일이
//  없고, 툴바 항목이 가게 변화마다 다시 그려지면 macOS 26 에서 툴바가 죽은 적이 있다
//  (`IdentityMenu` 참고).
//

import SwiftUI

extension CloudKitEnvironment {
    /// 배지 · 띠의 색. 개발은 주의(주황), 운영은 정상(초록).
    var tint: Color {
        switch self {
        case .development: .orange
        case .production: .green
        }
    }

    /// 앱 전체의 강조색. 운영은 손대지 않는다 — 평소 모습이 곧 "운영" 이라는 뜻이다.
    var appTint: Color? {
        switch self {
        case .development: .orange
        case .production: nil
        }
    }

    var koreanName: String {
        switch self {
        case .development: "개발"
        case .production: "운영"
        }
    }
}

struct EnvironmentBadge: View {
    private let environment = CloudKitEnvironment.current

    /// 개발은 꽉 찬 주황 — 운영의 옅은 초록과 멀리서도 다르게 보이게.
    private var isDevelopment: Bool { environment == .development }
    private var fill: Color { isDevelopment ? environment.tint : environment.tint.opacity(0.15) }
    private var ink: Color { isDevelopment ? .white : environment.tint }
    private var symbol: String { isDevelopment ? "hammer" : "checkmark.icloud" }

    var body: some View {
        Label(environment.shortLabel, systemImage: symbol)
            // 툴바 안에서는 Label 이 아이콘만 남기는데, 이 배지는 글자가 요점이다.
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            // 배지는 줄어들지 않는다. 좁은 헤더에서 먼저 짜부라져 "PROD" 가 한 글자씩
            // 세로로 쌓이던 것이 이것이었다.
            .lineLimit(1)
            .fixedSize()
            .background(fill, in: Capsule())
            .foregroundStyle(ink)
            .help("이 빌드는 CloudKit \(environment.displayName)(\(environment.koreanName)) 환경을 읽습니다")
            .accessibilityLabel("CloudKit \(environment.koreanName) 환경")
    }
}

/// 개발 빌드에서만 뜨는 한 줄짜리 띠. 운영 빌드에서는 아무것도 그리지 않는다.
/// 짧게 둔다 — 맥 사이드바는 좁고 아이폰은 탭마다 붙는다. 배지와 주황 강조색이 이미 같은
/// 말을 하고 있어서 띠는 "지금 개발 쪽" 이라는 것만 외치면 된다.
struct DevelopmentBanner: View {
    var body: some View {
        if CloudKitEnvironment.current == .development {
            Label("개발 환경 데이터", systemImage: "hammer.fill")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CloudKitEnvironment.development.tint, in: RoundedRectangle(cornerRadius: 8))
                .help("CloudKit Development 환경 — 테스트 빌드가 보낸 데이터입니다. 운영(Production) 숫자가 아닙니다.")
                .accessibilityLabel("개발 환경 데이터. 운영 숫자가 아닙니다.")
        }
    }
}

extension View {
    /// 개발 빌드면 앱 전체의 강조색을 주황으로. 단추 · 선택 · 탭 바가 모두 따라온다.
    @ViewBuilder
    func environmentTint() -> some View {
        if let tint = CloudKitEnvironment.current.appTint {
            self.tint(tint)
        } else {
            self
        }
    }
}

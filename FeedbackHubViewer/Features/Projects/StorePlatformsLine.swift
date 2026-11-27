//
//  StorePlatformsLine.swift
//  FeedbackHubViewer
//
//  앱 카드의 "무엇이 어디에 나갔나" — 플랫폼마다 판매 중인 버전과 그 뒤의 다음 버전.
//  "iOS 1.2.3 → 1.2.4 심사 대기" · "macOS 1.1.16" · "visionOS 첫 출시 전 · 1.0 준비 중".
//  재료는 App Store Connect 의 버전 목록(`StorePlatformRelease`). 워치 앱은 iOS 버전에 실려 나가서 따로 없다.
//

import SwiftUI

struct StorePlatformsLine: View {
    let releases: [StorePlatformRelease]

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 4) {
            ForEach(releases) { release in
                Label(release.line, systemImage: release.systemImage)
                    .font(.body)
                    .foregroundStyle(Self.tint(release))
                    .lineLimit(1)
                    .help(Self.help(release))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 판매 중이기만 하면 회색, 다음 버전이 길 위면 파랑, 막혔으면 빨강, 아직 한 번도 안 나갔으면 주황.
    static func tint(_ release: StorePlatformRelease) -> Color {
        if let next = release.next {
            if next.tone == .blocked { return .red }
            if release.live == nil { return .orange }
            return next.state == "PREPARE_FOR_SUBMISSION" ? .secondary : .blue
        }
        return .secondary
    }

    static func help(_ release: StorePlatformRelease) -> String {
        var parts = ["\(release.name): " + (release.live.map { "\($0) 판매 중" } ?? "아직 스토어에 안 나감")]
        if let next = release.next { parts.append("다음 버전 \(next.version) — \(next.stateLabel)") }
        return parts.joined(separator: "\n")
    }
}

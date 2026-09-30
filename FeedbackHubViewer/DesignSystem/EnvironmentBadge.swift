//
//  EnvironmentControls.swift
//  FeedbackHubViewer
//
//  Which CloudKit environment the running build reads.
//
//  There is no in-app switch: CloudKit takes the environment from the
//  `com.apple.developer.icloud-container-environment` entitlement baked into
//  the binary, so it is chosen by picking a scheme (see README §2-1). This is
//  purely a label, shown wherever the data's origin matters.
//

import SwiftUI

struct EnvironmentBadge: View {
    @EnvironmentObject private var store: FeedbackStore

    private var tint: Color {
        store.environment == .production ? .green : .orange
    }

    var body: some View {
        Label(store.environment.shortLabel, systemImage: "cloud")
            #if os(iOS)
            .font(.body.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            #else
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            #endif
            // 배지는 줄어들지 않는다. 좁은 헤더에서 먼저 짜부라져 "PROD" 가 한 글자씩
            // 세로로 쌓이던 것이 이것이었다.
            .lineLimit(1)
            .fixedSize()
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .help("이 빌드는 CloudKit \(store.environment.displayName) 환경을 읽습니다")
            .accessibilityLabel("CloudKit \(store.environment.displayName) 환경")
    }
}

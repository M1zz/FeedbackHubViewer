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
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .help("이 빌드는 CloudKit \(store.environment.displayName) 환경을 읽습니다")
            .accessibilityLabel("CloudKit \(store.environment.displayName) 환경")
    }
}

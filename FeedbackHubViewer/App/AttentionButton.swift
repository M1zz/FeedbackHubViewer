//
//  AttentionButton.swift
//  FeedbackHubViewer
//
//  툴바의 종. 새로 온 것이 몇 건인지 뱃지로 보이고, 누르면 할 일(손볼 것 + 알아 둘 것)로 간다.
//  예전엔 앱마다 무엇이 왔는지 따로 띄웠는데, 볼 것을 알려 주는 곳이 하나 더 느는 셈이었다. 무엇을 셀지는 설정의 "알림" 이 정하고(기본: 리뷰 · 피드백),
//  새 리뷰가 늘 맨 앞 — `AttentionKind` 의 순서.
//
//  수는 `FeedbackStore+Attention.swift` 에서 온다. 상태를 읽는 것은 이 뷰 안에서만 —
//  툴바 항목 자체가 상태에 따라 다시 만들어지면 맥에서 툴바가 깨진 적이 있다
//  (`IdentityMenu` 머리말).
//

import SwiftUI

struct AttentionButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore

    var body: some View {
        let total = store.attentionCount
        // 누르면 할 일로 — 볼 것을 모아 둔 곳은 거기 하나다(손볼 것 + 맨 위 "알아 둘 것").
        Button {
            if store.usesStackNavigation {
                store.phoneTab = .today
            } else {
                store.open(project: nil, section: .inbox)
            }
        } label: {
            // 수 뱃지가 있으니 종에 점은 따로 달지 않는다 — 둘이 겹쳐 보였다.
            Label("새 소식", systemImage: total > 0 ? "bell.fill" : "bell")
                .overlay(alignment: .topTrailing) {
                    if total > 0 {
                        Text(total > 99 ? "99+" : "\(total)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            // 단추의 동그라미 안에 들어오게 — 더 밀면 동그라미에 잘린다.
                            .offset(x: 5, y: -3)
                            .allowsHitTesting(false)
                    }
                }
        }
        .help(total > 0 ? "새로 온 것 \(total)건" : "새로 온 것이 없습니다")
        .accessibilityLabel(total > 0 ? "새 소식 \(total)건" : "새 소식 없음")
    }
}

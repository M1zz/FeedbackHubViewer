//
//  DetailFold.swift
//  FeedbackHubViewer
//
//  "자세히 보기" — 판정 아래에 접어 두는 나머지 카드들. 허브 화면은 미리 계산한
//  판정을 먼저 보이고, 그 판정을 만든 카드 · 원본은 여기 접는다. 처음에는 닫혀 있고,
//  화면마다 연 상태를 기억한다(`storageKey`).
//
//  DisclosureGroup 대신 단추를 쓰는 것은 안의 카드가 들여쓰기 없이 화면 폭을 그대로
//  쓰게 하려는 것이다. 접혀 있어도 안의 카드는 **그려 둔 채 높이만 0** 이다 — 카드마다
//  붙은 `.task` 가 접기 전과 똑같이 화면을 열 때 돌아, 펼치면 이미 받아 둔 것이 보인다.
//

import SwiftUI

struct DetailFold<Content: View>: View {
    /// 펼쳤는가. 화면마다 키가 달라, 바깥에서 같은 키의 `@AppStorage` 로 열 수도 있다
    /// (예: 유입의 "링크 보기" 단추가 접힌 링크 카드로 내려가기 전에 편다).
    @AppStorage private var isExpanded: Bool
    let title: String
    /// 닫혀 있을 때 단추 아래에 적는 한 줄 — 안에 무엇이 있는지.
    let summary: String?
    @ViewBuilder let content: Content

    init(storageKey: String,
         title: String = "자세히 보기",
         summary: String? = nil,
         @ViewBuilder content: () -> Content) {
        _isExpanded = AppStorage(wrappedValue: false, storageKey)
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isExpanded ? "\(title) 접기" : title)
                            .font(.headline)
                        if let summary, !isExpanded {
                            Text(summary)
                                .font(.hubCallout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Platform.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            content
                .padding(.top, isExpanded ? 14 : 0)
                .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
    }
}

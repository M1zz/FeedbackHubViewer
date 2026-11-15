//
//  BriefingCard.swift
//  FeedbackHubViewer
//
//  "오늘 볼 만한 것" 카드와 소식 아이콘 — 소식 칸과 할 일(오늘) 맨 위가 함께 쓴다.
//

import SwiftUI

struct BriefingCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @Environment(\.openURL) private var openURL
    let briefing: Briefing

    /// 오늘의 브리핑. 거르기와 상관없이 늘 같은 것 — 무엇을 고르든 "오늘 볼 것" 은 하나다.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(briefing.isEmpty ? "오늘은 볼 만한 게 없어요"
                                   : "오늘 볼 만한 것 \(briefing.lines.count + briefing.more)개",
                  systemImage: "newspaper")
                .font(.title3.weight(.semibold))
            if briefing.isEmpty {
                Text("지난 하루 동안 차트 · 링크 · 출시 · 기록 가운데 일부러 볼 만한 일은 없었어요. 일어난 일은 소식 칸에 그대로 쌓입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(briefing.lines) { line in
                Button { open(line) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        NewsIcon(project: line.project, kind: line.kind, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.currentWording(line.title, project: line.project))
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("→ \(line.action)")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if briefing.more > 0 {
                Text("외 \(briefing.more)개는 소식 칸에 있어요.")
                    .font(.hubCallout)
                    .foregroundStyle(.secondary)
            } else if !briefing.isEmpty {
                Text("그 밖에는 조용했어요.")
                    .font(.hubCallout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Platform.cardPadding)
        .cardSurface()
    }

    private func open(_ line: Briefing.Line) {
        if let url = line.url {
            openURL(url)
        } else {
            store.open(project: line.project, section: line.kind.section)
        }
    }

}

/// 앱 아이콘에, 오른쪽 아래 동그라미 하나 — 무슨 일인지(기호)와 좋은지 나쁜지(색).
struct NewsIcon: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    let project: String
    let kind: NewsKind
    let size: CGFloat

    var body: some View {
        let badge = size * 0.55
        return AppIcon(url: icons.url(for: project, keywords: keywords), size: size)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: badge * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: badge, height: badge)
                    .background(kind.tone.tint, in: Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .offset(x: badge * 0.3, y: badge * 0.3)
            }
            .padding(.trailing, badge * 0.3)
            .padding(.bottom, badge * 0.3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.displayName(for: project)) · \(kind.tone.label)")
    }

}

//
//  FeatureListView.swift
//  FeedbackHubViewer
//
//  앱의 첫 단계: 무엇을 보러 왔는가. 피드백 · 리뷰 · 진단 · 통계 … 를 "무엇을 알고 싶은가"
//  로 묶어 늘어놓고, 앱은 그 다음에 고른다(`AppListView`).
//
//  예전에는 앱을 먼저 고르고 그 안에서 열한 칸짜리 알약 줄을 옆으로 밀며 기능을 찾았다.
//  칸이 늘 때마다 줄이 길어져 무엇이 어디 있는지 읽히지 않았고, "진단이 온 앱이 어디냐"
//  같은 물음은 앱을 하나씩 열어 봐야 답이 나왔다. 기능을 먼저 고르면 그 기능의 숫자로 앱
//  목록이 서므로 그 물음이 목록 한 장으로 끝난다.
//
//  맥 · 아이패드의 사이드바다(고르면 옆 칸이 바뀐다). 아이폰은 같은 무리를 하단 탭으로
//  나눈다(`PhoneRootView`).
//

import SwiftUI

struct FeatureListView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    @EnvironmentObject private var design: DesignDocsStore
    @EnvironmentObject private var charts: ChartStore
    @EnvironmentObject private var news: NewsStore
    /// 본 뒤 바뀐 칸의 뱃지(`SectionChanges`).
    @ObservedObject private var changes = SectionChanges.shared
    /// 마케팅 칸의 "올렸나요?" 뱃지.
    @ObservedObject private var marketing = MarketingStore.shared
    /// 질문 찾기 칸의 새 질문 뱃지.
    @ObservedObject private var leadStore = LeadStore.shared

    var body: some View {
        let metrics = SectionMetrics(store: store, keywords: keywords, purchases: purchases, design: design, charts: charts, news: news)

        List {
            if CloudKitEnvironment.current == .development {
                Section {
                    DevelopmentBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }

            // 오류는 보여 줄 것이 하나도 없을 때만 자리를 차지한다. 캐시가 있으면 마지막 숫자가 그대로 선다.
            if let error = store.errorMessage, !store.hasContent {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            // 읽어서 사라지는 뱃지를 한 번에(`BadgeReset`). 할 일 · 올렸나요는 남는다.
            let readable = BadgeReset.readableCount(metrics)
            if readable > 0 {
                Section {
                    Button {
                        BadgeReset.markAllRead(metrics: metrics)
                    } label: {
                        Label("뱃지 모두 읽음 · \(AppFormat.count(readable))", systemImage: "checkmark.circle")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .help("안 읽은 피드백 · 새 리뷰 · 새 진단 · 새 소식 · 릴리즈 빨강 · 본 뒤 바뀐 것을 모두 읽음으로. 할 일 · 올렸나요는 남습니다")
                }
            }

            // 뱃지가 달린 칸은 맨 위 "확인할 것" 으로 올린다. 뱃지가 사라지면 제 무리의 제자리로.
            // 할 일은 이미 맨 위 한 줄이라 그대로 둔다.
            let flagged = Self.flagged(metrics)
            if !flagged.isEmpty {
                Section("확인할 것") {
                    ForEach(flagged) { section in
                        row(section, metrics: metrics)
                    }
                }
            }

            ForEach(FeedbackStore.ProjectSection.Group.allCases) { group in
                let sections = group.sections.filter { !flagged.contains($0) }
                if !sections.isEmpty {
                    Section {
                        ForEach(sections) { section in
                            row(section, metrics: metrics)
                        }
                    } header: {
                        // 할 일은 맨 위 한 줄이라 무리 이름이 없어도 읽힌다.
                        if group != .today { Text(group.rawValue) }
                    }
                }
            }
        }
        .animation(.default, value: Self.flagged(metrics))
        .hubSidebarListStyle()
        .modifier(SectionChangesBaseline(metrics: metrics))
        .navigationTitle("FeedbackHub")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EnvironmentBadge() }
        }
        #endif
    }

    /// 뱃지가 달린 칸 — 무리 차례 그대로.
    private static func flagged(_ metrics: SectionMetrics) -> [FeedbackStore.ProjectSection] {
        FeedbackStore.ProjectSection.Group.allCases
            .filter { $0 != .today }
            .flatMap(\.sections)
            .filter { metrics.badge($0, project: nil) != nil }
    }

    private func row(_ section: FeedbackStore.ProjectSection, metrics: SectionMetrics) -> some View {
        let isSelected = store.projectSection == section
        return Button { store.projectSection = section } label: {
            FeatureRow(section: section,
                       detail: metrics.label(section, project: nil),
                       badge: metrics.badge(section, project: nil),
                       isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if BadgeReset.readableCount(section, metrics: metrics) > 0 {
                Button {
                    BadgeReset.markRead(section, metrics: metrics)
                } label: {
                    Label("\(section.rawValue) 읽음으로 표시", systemImage: "checkmark.circle")
                }
            }
        }
        .listRowBackground(Rectangle().fill(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear)))
    }
}

/// 기능 한 줄: 아이콘 · 이름 · 전체 앱 기준 한마디 · 손볼 것 뱃지.
private struct FeatureRow: View {
    let section: FeedbackStore.ProjectSection
    let detail: String
    let badge: SectionMetrics.Badge?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.body)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let badge {
                CountBadge(count: badge.count, systemImage: badge.systemImage,
                           tint: badge.tint, name: badge.name)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

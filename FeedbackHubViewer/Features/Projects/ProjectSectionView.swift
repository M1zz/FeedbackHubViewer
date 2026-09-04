//
//  ProjectSectionView.swift
//  FeedbackHubViewer
//
//  One project's screen — the second level of the app. The project is chosen
//  first (sidebar on a Mac/iPad, the project list on a phone); 피드백 · 통계 ·
//  진단 · 키워드 are the things to look at inside it, switched by the buttons
//  at the top. They are peers of each other and never of the project, which is
//  what the old 개요/통계 top-level split got backwards.
//

import SwiftUI

struct ProjectSectionView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    /// nil == 전체 프로젝트.
    let project: String?
    /// The Mac's third column follows this; a phone pushes the detail instead.
    @Binding var selection: Feedback.ID?

    init(project: String?, selection: Binding<Feedback.ID?> = .constant(nil)) {
        self.project = project
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            // Fills whatever is left, so an empty section's placeholder can't
            // pull the segmented control down to the middle of the column.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Everything downstream reads the scope off the store, so the pushed
        // screen and the store can never disagree about which project this is.
        .task(id: project) { store.selectedProject = project }
        .navigationTitle(title)
        .hubNavigationSubtitle(subtitle)
    }

    private var title: String {
        guard let project else { return "전체 프로젝트" }
        return store.displayName(for: project)
    }

    // MARK: - Section switch

    /// Big labelled buttons rather than a segmented control: each one says
    /// what it is with an icon, a word and its count, and each is a comfortable
    /// target on a phone. A segmented control put the same choices in half the
    /// height and none of the meaning.
    private var sectionBar: some View {
        HStack(spacing: 6) {
            ForEach(FeedbackStore.ProjectSection.allCases) { section in
                sectionButton(section)
            }
        }
        .hubHeaderBar()
    }

    private func sectionButton(_ section: FeedbackStore.ProjectSection) -> some View {
        let isSelected = store.projectSection == section
        let count = count(for: section)
        return Button {
            store.projectSection = section
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: section.systemImage)
                        .font(.headline)
                    Text(section.rawValue)
                        .font(.headline)
                    // 안 읽은 피드백은 뱃지로 붙는다. 밑줄의 작은 글씨로 적으면
                    // "아직 안 본 게 있다"가 다른 숫자들 사이에 묻힌다.
                    if section == .feedback {
                        CountBadge(count: store.unreadCount(for: project),
                                   systemImage: "envelope.badge.fill",
                                   tint: .red, name: "안 읽은 피드백")
                    }
                }
                // 두 줄 모두 칸 너비를 제안받아야 한다. 이게 없으면 글자는 제
                // 이상적인 너비를 그대로 쓰고, 바깥 `frame`은 배경만 칸에 맞춰
                // 그린다 — 배경 밖으로 글자가 삐져나오고, 맨 끝 칸은 화면
                // 바깥으로 잘린다. "화면 양옆이 잘리는" 게 이것이었다.
                .frame(maxWidth: .infinity)
                Text(countLabel(for: section, count: count))
                    .font(.subheadline)
                    .opacity(isSelected ? 0.9 : 0.7)
                    .frame(maxWidth: .infinity)
            }
            .lineLimit(1)
            // 0.7에서 멈추면 좁은 아이폰에서 "App Store 검색"이 못 들어간다.
            // 줄 하나짜리 보조 문구라 조금 더 줄어도 읽힌다.
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            // 글자가 모서리에 닿지 않게. 배경 안쪽 여백이 없으면 딱 맞게
            // 들어가도 잘린 것처럼 보인다.
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(section.rawValue), \(countLabel(for: section, count: count))")
    }

    private func count(for section: FeedbackStore.ProjectSection) -> Int {
        switch section {
        case .feedback: return store.scopedFeedback.count
        case .stats: return store.usage(for: project).installs
        case .crashes: return store.crashSummary(for: project).total
        case .keywords: return keywords.standings(for: project).filter(\.isRanked).count
        }
    }

    /// The second line of each button — the number in words, not a bare digit.
    private func countLabel(for section: FeedbackStore.ProjectSection, count: Int) -> String {
        switch section {
        case .feedback:
            // 안 읽은 수는 위의 뱃지가 말한다 — 여기서 또 적으면 같은 사실이
            // 한 버튼에 두 번 있다.
            return "\(count)건"
        case .stats:
            return count > 0 ? "설치 \(count)대" : "사용 통계"
        case .crashes:
            return count > 0 ? "\(count)건" : "없음"
        case .keywords:
            let tracked = keywords.standings(for: project).count
            guard tracked > 0 else { return "App Store 검색" }
            // 전체 프로젝트 has no single app whose rank to read, so a "잡힘"
            // fraction there is a zero that means nothing. Count the terms.
            guard project != nil else { return "\(tracked)개 추적" }
            return "\(count)/\(tracked) 잡힘"
        }
    }

    /// "(지난주 대비 ▲12%)" — 견줄 것이 없으면 아무 말도 하지 않는다.
    private static func change(_ current: Int, _ previous: Int) -> String {
        guard previous > 0 else { return current > 0 ? " (이번 주 처음)" : "" }
        let ratio = Double(current - previous) / Double(previous)
        if current == previous { return " (지난주와 같음)" }
        let magnitude = abs(ratio)
        let amount = magnitude >= 10 ? String(format: "%.0f배", magnitude)
                                     : String(format: "%.0f%%", (magnitude * 100).rounded())
        return " (지난주 대비 \(amount) " + (current > previous ? "▲)" : "▼)")
    }

    @ViewBuilder
    private var content: some View {
        switch store.projectSection {
        case .feedback:
            FeedbackListView(selection: $selection)
        case .stats:
            StatisticsDashboard(project: project)
        case .crashes:
            CrashListView(project: project)
        case .keywords:
            KeywordsView(project: project)
        }
    }

    // MARK: - Subtitle

    private var subtitle: String {
        switch store.projectSection {
        case .feedback:
            let shown = store.filteredFeedback.count
            let total = store.scopedFeedback.count
            var text = shown == total ? "피드백 \(total)건" : "\(shown)건 표시 / 전체 \(total)건"
            // 남은 일이 몇 건인지가 이 화면의 요점이다 — 다 끝냈다는 사실도.
            if store.scopedPendingCount > 0 {
                text += " · 확인 필요 \(store.scopedPendingCount)건"
            } else if total > 0 {
                text += " · 모두 처리 완료"
            }
            return text
        case .stats:
            let usage = store.usage(for: project)
            guard usage.hasUsageData else {
                return "사용 통계 없음 · 피드백 \(store.scopedFeedback.count)건"
            }
            // 절대값 하나로는 열어 볼 이유가 안 된다. 설치 수는 규모라 그대로
            // 두고, 움직이는 두 값(사람·건수)은 지난주와 견준 결과를 붙인다.
            var text = "설치 \(AppFormat.count(usage.installs))대"
            text += " · 7일 사용자 \(usage.activeInstalls7)명\(Self.change(usage.activeInstalls7, usage.previousActiveInstalls7))"
            text += " · 7일 사용 \(AppFormat.count(usage.events7))건\(Self.change(usage.events7, usage.previousEvents7))"
            return text
        case .crashes:
            let summary = store.crashSummary(for: project)
            guard !summary.isEmpty else { return "올라온 진단 없음" }
            return "전체 \(summary.total)건 · 최근 7일 \(summary.last7Days)건"
        case .keywords:
            let standings = keywords.standings(for: project)
            guard !standings.isEmpty else { return "추적 중인 키워드 없음" }
            guard project != nil else { return "키워드 \(standings.count)개 추적 중 · 프로젝트를 골라 순위를 봅니다" }
            let ranked = standings.filter(\.isRanked)
            let best = ranked.compactMap(\.rank).min()
            var text = "키워드 \(standings.count)개 · \(ranked.count)개 잡힘"
            if let best { text += " · 최고 \(best)위" }
            return text
        }
    }
}

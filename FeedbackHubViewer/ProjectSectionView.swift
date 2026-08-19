//
//  ProjectSectionView.swift
//  FeedbackHubViewer
//
//  One project's screen — the second level of the app. The project is chosen
//  first (sidebar on a Mac/iPad, the project list on a phone); 피드백 · 통계 ·
//  진단 are the three things to look at inside it, switched by the segmented
//  control at the top. They are peers of each other and never of the project,
//  which is what the old 개요/통계 top-level split got backwards.
//

import SwiftUI

struct ProjectSectionView: View {
    @EnvironmentObject private var store: FeedbackStore
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

    /// Three big labelled buttons rather than a segmented control: each one
    /// says what it is with an icon, a word and its count, and each is a
    /// comfortable target on a phone. A segmented control put the same three
    /// choices in half the height and none of the meaning.
    private var sectionBar: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackStore.ProjectSection.allCases) { section in
                sectionButton(section)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
                }
                Text(countLabel(for: section, count: count))
                    .font(.subheadline)
                    .opacity(isSelected ? 0.9 : 0.7)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
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
        }
    }

    /// The second line of each button — the number in words, not a bare digit.
    private func countLabel(for section: FeedbackStore.ProjectSection, count: Int) -> String {
        switch section {
        case .feedback:
            let unread = store.unreadCount(for: project)
            return unread > 0 ? "\(count)건 · 안 읽음 \(unread)" : "\(count)건"
        case .stats:
            return count > 0 ? "설치 \(count)곳" : "사용 통계"
        case .crashes:
            return count > 0 ? "\(count)건" : "없음"
        }
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
        }
    }

    // MARK: - Subtitle

    private var subtitle: String {
        switch store.projectSection {
        case .feedback:
            let shown = store.filteredFeedback.count
            let total = store.scopedFeedback.count
            let hidden = store.showHandled ? 0 : store.handledCount(for: project)
            var text = shown == total ? "피드백 \(total)건" : "\(shown)건 표시 / 전체 \(total)건"
            if hidden > 0 { text += " · 확인 \(hidden)건 숨김" }
            return text
        case .stats:
            let usage = store.usage(for: project)
            guard usage.hasUsageData else {
                return "사용 통계 없음 · 피드백 \(store.scopedFeedback.count)건"
            }
            return "설치 \(usage.installs) · 7일 활성 \(usage.active7) · 이벤트 \(usage.totalEvents)"
        case .crashes:
            let summary = store.crashSummary(for: project)
            guard !summary.isEmpty else { return "올라온 진단 없음" }
            return "전체 \(summary.total)건 · 최근 7일 \(summary.last7Days)건"
        }
    }
}

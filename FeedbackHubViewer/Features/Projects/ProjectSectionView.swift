//
//  ProjectSectionView.swift
//  FeedbackHubViewer
//
//  One project's screen — the second level of the app. The project is chosen
//  first (sidebar on a Mac/iPad, the project list on a phone); 피드백 · 통계 ·
//  릴리즈 · 진단 · 키워드 are the things to look at inside it, switched by the buttons
//  at the top. They are peers of each other and never of the project, which is
//  what the old 개요/통계 top-level split got backwards.
//

import SwiftUI

struct ProjectSectionView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var purchases: AppStoreConnectStore
    /// 섹션 칸을 몇 줄로 접을지가 여기에 달렸다.
    @Environment(\.dynamicTypeSize) private var typeSize
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

    /// 한 줄짜리 알약 버튼. 넘치면 옆으로 민다.
    ///
    /// 예전에는 아이콘 · 이름 · 건수 두 줄짜리 큰 버튼을 격자로 깔았다. 뜻은 잘 보였지만
    /// 아이폰에서는 여섯 칸이 두 줄로 접혀 화면 윗부분을 통째로 먹었고, 정작 봐야 할
    /// 목록이 그만큼 밀려 내려갔다. 이제는 이름과 건수를 한 줄에 붙이고, 칸이 모자라면
    /// 줄을 늘리는 대신 옆으로 넘긴다.
    ///
    /// `ScrollView` 라서 `HStack` 이 화면을 밀어내던 옛 문제(칸들의 이상적인 너비 합이
    /// 화면보다 넓어져 양옆이 잘리던 것)는 생기지 않는다 — 스크롤 뷰는 받은 너비만 쓴다.
    private var sectionBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FeedbackStore.ProjectSection.allCases) { section in
                        sectionButton(section).id(section)
                    }
                }
            }
            // 다른 화면에서 링크로 들어와 끝쪽 탭이 골라졌을 때도 보이게.
            .onAppear { proxy.scrollTo(store.projectSection, anchor: .center) }
            .onChange(of: store.projectSection) { _, section in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(section, anchor: .center) }
            }
        }
        .hubHeaderBar(verticalPadding: 8)
    }

    private func sectionButton(_ section: FeedbackStore.ProjectSection) -> some View {
        let isSelected = store.projectSection == section
        let count = count(for: section)
        let unread = section == .feedback ? store.unreadCount(for: project) : 0
        return Button {
            store.projectSection = section
        } label: {
            HStack(spacing: 5) {
                // 안 읽은 피드백은 뱃지가 아이콘 자리를 대신한다. 둘 다 두면 같은
                // 칸에 표시가 두 개라 눈이 어디로 갈지 모른다.
                if unread > 0 {
                    CountBadge(count: unread, systemImage: "envelope.badge.fill",
                               tint: .red, name: "안 읽은 피드백")
                } else if !typeSize.isAccessibilitySize {
                    Image(systemName: section.systemImage)
                        .font(.subheadline)
                }
                Text(section.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text(countLabel(for: section, count: count))
                    .font(.caption)
                    .opacity(isSelected ? 0.85 : 0.6)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                        in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(section.rawValue), \(countLabel(for: section, count: count))")
    }

    private func count(for section: FeedbackStore.ProjectSection) -> Int {
        switch section {
        case .feedback: return store.scopedFeedback.count
        case .stats: return store.usage(for: project).installs
        // 빨강인 앱 수. 한 앱이면 0 아니면 1.
        case .release: return releaseRedCount
        case .crashes: return store.crashSummary(for: project).total
        case .keywords: return keywords.standings(for: project).filter(\.isRanked).count
        case .purchases: return project.flatMap { purchases.products(for: $0)?.count } ?? 0
        }
    }

    /// 한 앱이면 그 앱이 빨강일 때 1, 전체면 빨강인 앱 수.
    private var releaseRedCount: Int {
        let keys = project.map { [$0] } ?? store.projectCounts.map(\.key)
        return keys.filter { store.releaseLevel(for: $0) == .red }.count
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
        case .release:
            guard let project else {
                return count > 0 ? "빨강 \(count)개" : "빨강 없음"
            }
            return store.releaseLevel(for: project)?.label ?? "판정 없음"
        case .crashes:
            return count > 0 ? "\(count)건" : "없음"
        case .keywords:
            let tracked = keywords.standings(for: project).count
            guard tracked > 0 else { return "App Store 검색" }
            // 전체 프로젝트 has no single app whose rank to read, so a "잡힘"
            // fraction there is a zero that means nothing. Count the terms.
            guard project != nil else { return "\(tracked)개 추적" }
            return "\(count)/\(tracked) 잡힘"
        case .purchases:
            guard purchases.isConfigured else { return "연결 안 됨" }
            return count > 0 ? "상품 \(count)개" : "App Store Connect"
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
        case .release:
            ReleaseHealthView(project: project)
        case .crashes:
            CrashListView(project: project)
        case .keywords:
            KeywordsView(project: project)
        case .purchases:
            InAppPurchasesView(project: project)
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
        case .release:
            guard let project else {
                let levels = store.projectCounts.compactMap { store.releaseLevel(for: $0.key) }
                guard !levels.isEmpty else { return "판정할 수 있는 앱 없음" }
                let red = levels.filter { $0 == .red }.count
                let yellow = levels.filter { $0 == .yellow }.count
                return "앱 \(levels.count)개 판정 · 빨강 \(red) · 노랑 \(yellow)"
            }
            guard let report = store.releaseHealth(for: project) else {
                return "최근 \(ReleaseHealth.windowDays)일에 버전을 가를 사용 이벤트 없음"
            }
            var text = "최신 \(report.latest.version)"
            if let previous = report.previous { text += " · 앞 버전 \(previous.version)" }
            return text + " · \(report.verdict.level.label)"
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
        case .purchases:
            guard purchases.isConfigured else { return "App Store Connect 키를 넣으면 상품과 판매가 나옵니다" }
            guard let project else { return "앱별 최근 \(AppStoreConnectStore.salesDays)일 판매 순위" }
            guard let products = purchases.products(for: project) else { return "App Store Connect 상품" }
            return "상품 \(products.count)개 · 판매 중 \(products.filter(\.isOnSale).count)개"
        }
    }
}

//
//  NewsView.swift
//  FeedbackHubViewer
//
//  "소식" — 맨 위는 오늘의 브리핑(지난 하루 중 볼 만한 것만, 그래서 무엇을 할지까지),
//  그 아래는 일어난 일 전부의 기록. 숫자가 아니라 사건이다(`AppNews.swift`).
//
//  위에서 종류(경고 · 스토어 · 사람들 · 이정표)와 앱을 고른다. 한 줄을 누르면
//  바깥 링크가 있으면 그 글을, 없으면 그 앱의 해당 칸을 연다. 화면을 연 순간 전에 찾은
//  것까지 읽은 것으로 치고, 그때 새로 온 것에는 점을 남겨 둔다.
//

import SwiftUI

struct NewsView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var news: NewsStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    @Environment(\.openURL) private var openURL

    @State private var category: NewsCategory?
    @State private var project: String?
    /// 화면을 열었을 때의 읽음 시각. 이보다 뒤에 찾은 것에 점을 찍는다.
    @State private var readMark: Date?
    /// 최근 `NewsStore.recentDays` 일보다 오래된 기록까지 펼쳤나.
    @State private var showsOlder = false
    /// 펼친 하루의 "그 밖에".
    @State private var expanded: Set<String> = []

    var body: some View {
        let shown = news.items.filter {
            (category == nil || $0.kind.category == category) && (project == nil || $0.project == project)
        }
        Group {
            if news.items.isEmpty {
                VStack(spacing: 0) {
                    BriefingCard(briefing: news.briefing())
                        .padding(16)
                    emptyState
                }
            } else if shown.isEmpty {
                ContentUnavailableView("고른 조건에 맞는 소식이 없습니다", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                list(shown)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .onAppear {
            readMark = news.lastReadAt
            news.collect()
            news.markAllRead()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 소식이 없습니다", systemImage: "newspaper")
        } description: {
            Text("처음에는 지금까지 있던 것을 기준으로만 잡고, 그 뒤로 일어나는 일부터 쌓입니다. 차트에 들거나, 새 사이트가 링크를 걸거나, 새 버전이 스토어에 나오면 기록에 한 줄씩 생기고, 그중 볼 만한 것은 아침 9시 브리핑으로 전해요.")
        }
    }

    // MARK: 브리핑

    // MARK: 거르기

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("종류", selection: $category) {
                Text("전체").tag(NewsCategory?.none)
                ForEach(NewsCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                Picker("앱", selection: $project) {
                    Text("모든 앱").tag(String?.none)
                    ForEach(appsWithNews, id: \.self) { key in
                        Text(store.displayName(for: key)).tag(Optional(key))
                    }
                }
            } label: {
                Label(project.map { store.displayName(for: $0) } ?? "모든 앱",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
        }
        .hubHeaderBar(verticalPadding: 8)
    }

    private var appsWithNews: [String] {
        Array(Set(news.items.map(\.project))).sorted { store.displayName(for: $0) < store.displayName(for: $1) }
    }

    // MARK: 목록

    /// 하루 안에서 같은 앱 · 같은 종류를 한 줄로 합친 것.
    private struct NewsGroup: Identifiable {
        let id: String
        let items: [NewsItem]
        var first: NewsItem { items[0] }
        var count: Int { items.count }
    }

    /// 하루의 기록을 볼 만한 줄과 조용한 줄(브리핑에 오르지 않는 종류)로 나눈다.
    private func groups(_ items: [NewsItem]) -> (main: [NewsGroup], quiet: [NewsGroup]) {
        let grouped = Dictionary(grouping: items) { "\($0.project)|\($0.kind.rawValue)" }
        let all = grouped.map { key, value in
            NewsGroup(id: key + "|" + (value.first.map { NewsDetector.day($0.foundAt) } ?? ""),
                  items: value.sorted { $0.date > $1.date })
        }
        .sorted {
            let (a, b) = ($0.first.kind.category.rank, $1.first.kind.category.rank)
            return a == b ? $0.first.foundAt > $1.first.foundAt : a < b
        }
        return (all.filter { $0.first.kind.briefingRank != nil }, all.filter { $0.first.kind.briefingRank == nil })
    }

    private func list(_ items: [NewsItem]) -> some View {
        let cutoff = news.recentCutoff
        let olderCount = items.filter { $0.foundAt <= cutoff }.count
        let visible = showsOlder ? items : items.filter { $0.foundAt > cutoff }
        let days = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.foundAt) }
        return List {
            Section {
                BriefingCard(briefing: news.briefing())
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                let split = groups(days[day] ?? [])
                Section(Self.dayTitle(day)) {
                    ForEach(split.main) { group in
                        groupRow(group)
                    }
                    if !split.quiet.isEmpty {
                        quietRow(split.quiet, day: day)
                    }
                }
            }
            if olderCount > 0 {
                Section {
                    Button(showsOlder ? "지난 소식 접기"
                                      : "\(NewsStore.recentDays)일 전 소식 \(AppFormat.count(olderCount))개 보기") {
                        showsOlder.toggle()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// 한 줄 — 아이콘과 제목, 오른쪽에 언제 일인지. 제목에 앱 이름이 들어 있어 따로 적지 않는다.
    private func groupRow(_ group: NewsGroup) -> some View {
        Button { open(group.first) } label: {
            HStack(alignment: .center, spacing: 10) {
                newsIcon(project: group.first.project, kind: group.first.kind, size: 32)
                Text(title(group))
                    .font(.body)
                    .foregroundStyle(group.first.kind.tone == .bad ? Color.red : Color.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isNew(group) {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        .accessibilityLabel("새 소식")
                }
                Text(AppFormat.relative(group.first.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 브리핑에 오르지 않는 일(심사 시작 · 차트에서 빠짐 · 새 나라 설치)은 하루에 한 줄로 접는다.
    @ViewBuilder
    private func quietRow(_ quiet: [NewsGroup], day: Date) -> some View {
        let id = "quiet|" + NewsDetector.day(day)
        let isOpen = expanded.contains(id)
        let total = quiet.reduce(0) { $0 + $1.count }
        Button {
            if isOpen { expanded.remove(id) } else { expanded.insert(id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                Text("그 밖에 \(AppFormat.count(total))건")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if isOpen {
            ForEach(quiet) { group in
                groupRow(group)
            }
        }
    }

    private func newsIcon(project: String, kind: NewsKind, size: CGFloat) -> some View {
        NewsIcon(project: project, kind: kind, size: size)
    }

    private func title(_ group: NewsGroup) -> String {
        guard group.count > 1 else { return store.currentWording(group.first.title, project: group.first.project) }
        return Briefing.mergedTitle(group.first.kind, app: store.displayName(for: group.first.project), count: group.count)
    }

    private func isNew(_ group: NewsGroup) -> Bool {
        guard let readMark else { return false }
        return group.items.contains { $0.foundAt > readMark }
    }

    private func open(_ item: NewsItem) {
        if let url = item.url {
            openURL(url)
        } else {
            store.open(project: item.project, section: item.kind.section)
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInYesterday(day) { return "어제" }
        return day.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}

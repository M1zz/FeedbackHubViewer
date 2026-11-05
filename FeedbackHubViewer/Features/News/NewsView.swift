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
    @Environment(\.openURL) private var openURL

    @State private var category: NewsCategory?
    @State private var project: String?
    /// 화면을 열었을 때의 읽음 시각. 이보다 뒤에 찾은 것에 점을 찍는다.
    @State private var readMark: Date?

    var body: some View {
        let shown = news.items.filter {
            (category == nil || $0.kind.category == category) && (project == nil || $0.project == project)
        }
        Group {
            if news.items.isEmpty {
                VStack(spacing: 0) {
                    briefingCard(news.briefing())
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

    /// 오늘의 브리핑. 거르기와 상관없이 늘 같은 것 — 무엇을 고르든 "오늘 볼 것" 은 하나다.
    private func briefingCard(_ briefing: Briefing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(briefing.isEmpty ? "오늘은 볼 만한 게 없어요"
                                   : "오늘 볼 만한 것 \(briefing.lines.count + briefing.more)개",
                  systemImage: "newspaper")
                .font(.title3.weight(.semibold))
            if briefing.isEmpty {
                Text("지난 하루 동안 차트 · 링크 · 출시 · 기록 가운데 일부러 볼 만한 일은 없었어요. 일어난 일은 아래 기록에 그대로 쌓입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(briefing.lines.enumerated()), id: \.element.id) { index, line in
                Button { open(line) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(line.kind.category.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.title)
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
                Text("외 \(briefing.more)개는 아래 기록에 있어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !briefing.isEmpty {
                Text("그 밖에는 조용했어요.")
                    .font(.callout)
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

    private func list(_ items: [NewsItem]) -> some View {
        let days = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.foundAt) }
        return List {
            Section {
                briefingCard(news.briefing())
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section("기록 · " + Self.dayTitle(day)) {
                    ForEach(days[day] ?? []) { item in
                        Button { open(item) } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ item: NewsItem) -> some View {
        let tint = item.kind.category.tint
        let isNew = readMark.map { item.foundAt > $0 } ?? false
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.displayName(for: item.project))
                    Text("·")
                    Text(item.kind.category.rawValue)
                    Spacer(minLength: 4)
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(item.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = item.url {
                    Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            if isNew {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityLabel("새 소식")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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

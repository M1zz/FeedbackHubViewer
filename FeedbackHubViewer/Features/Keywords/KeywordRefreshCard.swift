//
//  KeywordRefreshCard.swift
//  FeedbackHubViewer
//
//  키워드 칸을 다시 짤 때가 됐나 — 그리고 됐으면 Claude 에게 넘길 지시문.
//
//  앱 하나를 볼 때는 칸마다 "바꾼 지 며칠, 그동안 순위가 어떻게 됐나" 를, 전체 앱을 볼 때는
//  다시 짤 때가 된 앱 목록을 보여 준다. 두 주(`KeywordField.settleDays`)가 안 됐으면 버튼을
//  흐리게 두고 이유를 말한다 — 자리 잡기 전에 또 바꾸면 바꾼 효과를 영영 못 본다. 그래도
//  누를 수는 있다. 판단은 사람이 한다.
//

import SwiftUI

struct KeywordRefreshCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var charts: ChartStore
    let project: String

    var body: some View {
        let states = keywords.refreshStates(for: project)
        Card(title: "키워드 다시 짜기", systemImage: "arrow.triangle.2.circlepath") {
            if states.isEmpty {
                Text("스토어에 걸린 키워드 칸을 아직 읽지 못했습니다. App Store Connect 키가 있으면 하루 한 번 읽어, 칸의 말을 저절로 추적하고 바뀐 날을 적습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let settled = states.allSatisfy(\.isSettled)
                let waiting = states.contains(where: \.awaitingRelease) && !states.contains(where: \.isDue)
                Text(waiting ? "새로 짠 키워드가 출시를 기다려요 — 레포에는 있고 스토어에는 아직 옛 말이에요"
                             : headline(states, settled: settled))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(settled ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if waiting {
                    Text("다음 배포가 심사를 통과하면 스토어 칸이 바뀌고, 그날부터 다시 두 주를 잽니다. 지금은 할 일이 없어요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RepoFolderNote()
                if settled && !waiting {
                    // 할 일은 이것 하나 — 순위를 읽고 판단할 필요는 없다. 그건 Claude 가 한다.
                    Text("할 일: 아래 단추로 글을 복사해 이 앱 리포에서 연 Claude 에 붙여넣으세요. 순위를 근거로 키워드 줄을 다시 짜서 커밋하고, 스토어에는 다음 배포 때 올라갑니다.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let copy = CopyButton(text: KeywordRefreshPrompt.make([promptApp(project, states: states)]),
                                      title: "Claude에게 맡길 글 복사")
                if settled && !waiting { copy.buttonStyle(.borderedProminent) } else { copy.buttonStyle(.bordered) }
                DisclosureGroup("나라마다 지금 순위") {
                    ForEach(states) { state in stateRow(state) }
                }
                .font(.body)
            }
        }
    }

    private func headline(_ states: [KeywordRefreshState], settled: Bool) -> String {
        let days = states.map(\.days).min() ?? 0
        if settled { return "다시 짤 때예요 — 칸을 바꾼 지 \(days)일 지났어요" }
        return "아직 순위가 자리 잡는 중이에요 (\(days)일째 · \(KeywordField.settleDays)일부터 권해요)"
    }

    private func stateRow(_ state: KeywordRefreshState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("\(ChartStorefronts.flag(state.country)) \(state.locale)")
                    .font(.headline)
                Text(state.changedAt.map { "\($0.formatted(.dateTime.month().day())) 바뀜" } ?? "바뀐 날 모름")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if state.awaitingRelease {
                    Tag(text: SectionMetrics.keywordWaitingAction, isCompact: true)
                }
            }
            Text(summary(state))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summary(_ state: KeywordRefreshState) -> String {
        var parts = ["\(state.terms.count)개 중 200위 안 \(state.ranked)개", "10위 안 \(state.topTen)개"]
        if state.changedAt != nil {
            parts.append("바꾼 뒤 오름 \(state.rose) · 내림 \(state.fell)")
        } else {
            parts.append("\(state.days)일째 그대로")
        }
        return parts.joined(separator: " · ")
    }

    private func promptApp(_ project: String, states: [KeywordRefreshState]) -> KeywordRefreshPrompt.App {
        Self.promptApp(project, states: states, store: store, keywords: keywords, charts: charts)
    }

    static func promptApp(_ project: String, states: [KeywordRefreshState], store: FeedbackStore,
                          keywords: KeywordStore, charts: ChartStore) -> KeywordRefreshPrompt.App {
        let trackId = keywords.trackId(for: project)
        return KeywordRefreshPrompt.App(name: store.displayName(for: project), project: project, trackId: trackId,
                                        isMac: charts.app(trackId)?.platform == .mac,
                                        states: states, competitors: keywords.competitors(for: project))
    }
}

/// 전체 앱을 볼 때 — 다시 짤 때가 된 앱들과, 한꺼번에 맡길 지시문.
struct KeywordRefreshOverviewCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var charts: ChartStore
    @State private var copied = false

    var body: some View {
        let projects = store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject && !store.isExcluded($0) }
        let due = keywords.refreshDue(projects: projects)
        let watched = projects.filter { !keywords.refreshStates(for: $0, withRanks: false).isEmpty }
        let waiting = keywords.awaitingRelease(projects: projects)
        Card(title: "키워드 다시 짜기", systemImage: "arrow.triangle.2.circlepath") {
            if watched.isEmpty {
                Text("스토어에 걸린 키워드 칸을 아직 읽지 못했습니다. App Store Connect 키가 있으면 하루 한 번 모든 앱의 칸을 읽습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if due.isEmpty {
                Text(waiting.isEmpty
                     ? "다시 짤 앱이 없어요 — 칸을 지켜보는 앱 \(watched.count)개 모두 바꾼 지 \(KeywordField.settleDays)일이 안 됐어요."
                     : "다시 짤 앱이 없어요 — 새로 짠 키워드가 출시를 기다리는 앱 \(waiting.count)개: " + waiting.map(store.displayName(for:)).joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RepoFolderNote()
            } else {
                Text("다시 짤 때가 된 앱 \(due.count)개")
                    .font(.title3.weight(.semibold))
                if !waiting.isEmpty {
                    Text("새로 짠 키워드가 출시를 기다리는 앱 \(waiting.count)개는 뺐어요: " + waiting.map(store.displayName(for:)).joined(separator: ", "))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RepoFolderNote()
                Text("할 일: 아래 단추로 한꺼번에 맡기거나, 앱을 눌러 하나씩 맡기세요. 순위는 Claude 가 읽고 판단합니다.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(due, id: \.project) { entry in
                    Button {
                        store.open(project: entry.project, section: .keywords)
                    } label: {
                        HStack {
                            Text(store.displayName(for: entry.project))
                            Spacer(minLength: 8)
                            Text("\(entry.days)일째")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    // 글은 누를 때 짓는다 — 앱마다 모든 검색어의 순위를 훑어 그릴 때마다 지으면 무겁다.
                    Button {
                        Platform.copyToPasteboard(KeywordRefreshPrompt.make(due.map { entry in
                            KeywordRefreshCard.promptApp(entry.project,
                                                         states: keywords.refreshStates(for: entry.project),
                                                         store: store, keywords: keywords, charts: charts)
                        }))
                        copied = true
                    } label: {
                        Label(copied ? "복사됨" : "\(due.count)개 한꺼번에 맡길 글 복사",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("~/Documents/workspace/Auto 에서 연 Claude 에 붙여넣으면 앱마다 레포를 찾아 키워드 줄을 고칩니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 레포 폴더를 아직 안 골랐으면 고르게 하는 한 줄. 골라야 "출시 기다림" 을 가린다.
struct RepoFolderNote: View {
    @EnvironmentObject private var keywords: KeywordStore

    var body: some View {
        #if os(macOS)
        if keywords.repoFolder == nil {
            HStack(spacing: 8) {
                Button("레포 폴더 연결") { keywords.chooseRepoFolder() }
                    .buttonStyle(.bordered)
                Text("workspace/Auto 를 한 번 고르면, 레포에서 이미 다시 짠 앱은 \"출시 기다림\" 으로 따로 보여요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #endif
    }
}

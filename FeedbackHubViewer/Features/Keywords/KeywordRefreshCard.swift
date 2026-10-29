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
                Text(headline(states, settled: settled))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(settled ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(states) { state in stateRow(state) }
                HStack(spacing: 8) {
                    CopyButton(text: KeywordRefreshPrompt.make([promptApp(project, states: states)]),
                               title: "Claude에게 맡길 글 복사")
                        .buttonStyle(.bordered)
                        .opacity(settled ? 1 : 0.6)
                    Text("앱 리포에서 연 Claude 에 붙여넣으면 순위를 근거로 키워드 줄을 다시 짜서 커밋합니다. 스토어에는 다음 배포 때 올라갑니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    var body: some View {
        let projects = store.allProjectKeys.filter { $0 != Feedback.unclassifiedProject && !store.hiddenProjects.contains($0) }
        let due = keywords.refreshDue(projects: projects)
        let watched = projects.filter { !keywords.refreshStates(for: $0).isEmpty }
        Card(title: "키워드 다시 짜기", systemImage: "arrow.triangle.2.circlepath") {
            if watched.isEmpty {
                Text("스토어에 걸린 키워드 칸을 아직 읽지 못했습니다. App Store Connect 키가 있으면 하루 한 번 모든 앱의 칸을 읽습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if due.isEmpty {
                Text("다시 짤 앱이 없어요 — 칸을 지켜보는 앱 \(watched.count)개 모두 바꾼 지 \(KeywordField.settleDays)일이 안 됐어요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("다시 짤 때가 된 앱 \(due.count)개")
                    .font(.title3.weight(.semibold))
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
                    CopyButton(text: KeywordRefreshPrompt.make(due.map { entry in
                        KeywordRefreshCard.promptApp(entry.project,
                                                     states: keywords.refreshStates(for: entry.project),
                                                     store: store, keywords: keywords, charts: charts)
                    }), title: "\(due.count)개 한꺼번에 맡길 글 복사")
                        .buttonStyle(.bordered)
                    Text("~/Documents/workspace/Auto 에서 연 Claude 에 붙여넣으면 앱마다 레포를 찾아 키워드 줄을 고칩니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

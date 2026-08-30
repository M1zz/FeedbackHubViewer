//
//  SidebarView.swift
//  FeedbackHubViewer
//
//  The left column: the project list, and nothing else. Projects are the top
//  level of the app — 피드백 · 통계 · 진단 all live *inside* the project that is
//  picked here (see `ProjectSectionView`). Summary numbers, filters and
//  settings used to share this list; they now sit on the screen they belong to.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: FeedbackStore
    /// Only for the app icons — the store links it resolves on launch are what
    /// turns a bundle id into a picture (see `AppIcon`).
    @EnvironmentObject private var keywords: KeywordStore

    var body: some View {
        // One pass for the whole list: each row's numbers and its sparkline
        // come out of the same map the ordering uses.
        let traffic = store.trafficByProject

        return List {
            Section("프로젝트") {
                ProjectRow(name: "전체 프로젝트",
                           systemImage: "square.grid.3x3",
                           tint: .purple,
                           count: store.allFeedback.count,
                           unread: store.unreadCount,
                           crashes7: store.crashSummary(for: nil).last7Days,
                           traffic: store.overallTraffic,
                           isSelected: store.selectedProject == nil) {
                    store.selectedProject = nil
                }

                ForEach(store.projectCounts, id: \.key) { entry in
                    ProjectRow(name: store.displayName(for: entry.key),
                               iconURL: keywords.storeApp(for: entry.key)?.iconURL,
                               systemImage: entry.key == Feedback.unclassifiedProject
                                   ? "questionmark.folder" : "app.dashed",
                               tint: entry.key == Feedback.unclassifiedProject ? .secondary : .accentColor,
                               count: entry.count,
                               unread: store.unreadCount(for: entry.key),
                               crashes7: store.crashSummary(for: entry.key).last7Days,
                               traffic: traffic[entry.key] ?? .none,
                               isSelected: store.selectedProject == entry.key) {
                        store.selectedProject = entry.key
                    }
                    .contextMenu {
                        Button {
                            store.markAllRead(project: entry.key)
                        } label: {
                            Label("모두 읽음으로 표시", systemImage: "envelope.open")
                        }
                        Button {
                            store.hideProject(entry.key)
                        } label: {
                            Label("이 프로젝트 숨기기", systemImage: "eye.slash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            store.hideProject(entry.key)
                        } label: {
                            Label("숨기기", systemImage: "eye.slash")
                        }
                        .tint(.gray)
                    }
                }
            }

            if !store.hiddenProjectEntries.isEmpty {
                Section {
                    ForEach(store.hiddenProjectEntries, id: \.key) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.displayName)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(entry.records)")
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                            Button("다시 보기") { store.showProject(entry.key) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        .font(.callout)
                    }
                    if store.hiddenProjectEntries.count > 1 {
                        Button {
                            store.showAllProjects()
                        } label: {
                            Label("모두 다시 보기", systemImage: "eye")
                                .font(.callout)
                        }
                    }
                } header: {
                    Text("숨긴 프로젝트")
                } footer: {
                    Text("이 기기에서만 가려집니다. 허브의 레코드는 그대로 남아 있고, 다시 보기를 누르면 즉시 돌아옵니다.")
                        .font(.caption)
                }
            }

            Section {
                HStack {
                    Label("CloudKit 환경", systemImage: "cloud")
                    Spacer()
                    EnvironmentBadge()
                }
                .font(.callout)
                if let type = store.resolvedRecordType {
                    HStack {
                        Label("레코드 타입", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text(type).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .hubSidebarListStyle()
    }
}

/// A selectable project row. Two lines, plain words: a row of coloured badges
/// says "3" twice and leaves you to guess which 3 is which.
private struct ProjectRow: View {
    let name: String
    /// The App Store icon, when this project is an app the store knows.
    var iconURL: URL? = nil
    let systemImage: String
    let tint: Color
    let count: Int
    let unread: Int
    let crashes7: Int
    /// This week's usage — what the list is ordered by, and the 14-day shape
    /// behind it.
    var traffic: FeedbackStore.Traffic = .none
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIcon(url: iconURL, symbol: systemImage,
                        tint: isSelected ? Color.accentColor : tint, size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    // 목록이 7일 사용량 순이라 그 숫자는 늘 보이고, 손봐야 할 것
                    // (안 읽음·진단)은 그 옆에 빨갛게 붙는다.
                    HStack(spacing: 6) {
                        if traffic.events7 > 0 {
                            Text("7일 사용 \(traffic.events7)건")
                                .foregroundStyle(.secondary)
                        }
                        if unread > 0 {
                            Text("안 읽음 \(unread)")
                                .foregroundStyle(.red)
                        }
                        if crashes7 > 0 {
                            Text("진단 \(crashes7)")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(count)건")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if traffic.totalEvents > 0 {
                        // The same 14-day shape the phone cards draw: how much
                        // this app is actually being used, at a glance.
                        Sparkline(points: traffic.sparkline)
                            .frame(width: 58, height: 18)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(name), 피드백 \(count)건, 안 읽음 \(unread)건")
    }

}

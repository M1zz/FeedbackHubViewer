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
                           capacity: store.carryingCapacity(for: nil, period: .week),
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
                               capacity: store.carryingCapacity(for: entry.key, period: .week),
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
    /// 주간 성장 상한. 못 재면 nil이고, 그때는 그 조각만 빠진다.
    var capacity: CarryingCapacity? = nil
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
                    // 목록이 7일 사용량 순이긴 하지만, 줄에 적는 것은 그 절대값이
                    // 아니라 **지난주와 견준 결과**다. "7일 사용 5,000건"은 열어 볼
                    // 이유가 못 되고 "지난주보다 12% 줄었다"는 이유가 된다.
                    HStack(spacing: 6) {
                        if let change = weekChangeText {
                            Text(change)
                                .foregroundStyle(changeTint)
                        }
                        // 변화 옆에 위치 하나 — 지금 자리가 이 앱의 평형에서 몇 %인가.
                        // 오르내림만으로는 "더 자랄 자리가 있는가"에 답하지 못한다.
                        if let fill = capacity?.fill {
                            // 넘어선 것을 "248%"로 적으면 좋은 소식처럼 읽힌다 —
                            // 지금의 유입·이탈로는 못 떠받치는 수라는 뜻인데.
                            Text(fill > 1 ? "상한 넘어섬" : "상한의 \(Int((fill * 100).rounded()))%")
                                .foregroundStyle(fill > 1 ? .orange : .secondary)
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
                    // 안 읽은 피드백은 숫자가 아니라 뱃지다 — 옆의 "30건"과 같은
                    // 활자로 적으면 읽을 것과 구경할 것이 같은 무게로 보인다.
                    if unread > 0 {
                        CountBadge(count: unread, systemImage: "envelope.badge.fill",
                                   tint: .red, name: "안 읽은 피드백")
                    } else {
                        Text("\(count)건")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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
        .accessibilityLabel(accessibilityText)
    }

    /// 지난주와 견준 사용량 한 마디. 견줄 것이 없으면 아무 말도 하지 않는다 —
    /// 0에서 0으로 간 것을 "±0%"로 적으면 있지도 않은 안정을 말하게 된다.
    private var weekChangeText: String? {
        let change = traffic.weekChange
        if change.isEmpty { return nil }
        guard let ratio = change.ratio else { return "이번 주 처음 \(change.current)건" }
        let magnitude = abs(ratio)
        let amount = magnitude >= 10 ? String(format: "%.0f배", magnitude)
                                     : String(format: "%.0f%%", (magnitude * 100).rounded())
        if change.delta == 0 { return "지난주와 같음" }
        return "지난주보다 \(amount) " + (change.delta > 0 ? "▲" : "▼")
    }

    private var changeTint: Color {
        let delta = traffic.weekChange.delta
        return delta == 0 ? .secondary : (delta > 0 ? .green : .red)
    }

    private var accessibilityText: String {
        var parts = ["\(name)"]
        if let change = weekChangeText { parts.append(change.replacingOccurrences(of: "▲", with: "늘어남")
                                                            .replacingOccurrences(of: "▼", with: "줄어듦")) }
        if let fill = capacity?.fill, let ceiling = capacity?.capacity {
            parts.append("성장 상한 \(Int(ceiling.rounded()))명 중 \(Int((fill * 100).rounded()))퍼센트")
        }
        parts.append("피드백 \(count)건")
        if unread > 0 { parts.append("안 읽음 \(unread)건") }
        if crashes7 > 0 { parts.append("최근 7일 진단 \(crashes7)건") }
        return parts.joined(separator: ", ")
    }
}

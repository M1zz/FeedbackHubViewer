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
    /// 릴리즈 건강이 빨강인 앱을 위로. 끄면 MAU 순 그대로다.
    @AppStorage("releaseRedFirst") private var redFirst = false

    var body: some View {
        // One pass for the whole list: each row's numbers and its sparkline
        // come out of the same map the ordering uses.
        let traffic = store.trafficByProject

        return List {
            Section {
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

                ForEach(redFirst ? store.redFirst(store.projectCounts, key: { $0.key }) : store.projectCounts,
                        id: \.key) { entry in
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
                               release: store.releaseLevel(for: entry.key),
                               cycle: store.usageCycle(for: entry.key),
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
            } header: {
                HStack {
                    Text("프로젝트")
                    Spacer()
                    RedFirstToggle(isOn: $redFirst)
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
    /// 최신 버전의 릴리즈 건강. 잴 수 없으면 nil 이고 점이 안 뜬다.
    var release: ReleaseHealth.Level? = nil
    /// 이 앱의 사용 주기. 오른쪽 숫자가 그 주기의 지표가 된다(안 정했으면 MAU).
    var cycle: UsageCycle? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIcon(url: iconURL, symbol: systemImage,
                        tint: isSelected ? Color.accentColor : tint, size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.body)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        ReleaseDot(level: release)
                    }
                    // 둘째 줄은 "열어 볼 이유"만 적는다. 지난주 대비 증감은 뺐다 — 줄마다
                    // 붙으니 오히려 읽을 것이 묻혔다. 증감은 앱 화면에서 본다.
                    HStack(spacing: 6) {
                        // 지금 자리가 이 앱의 평형(상한)에서 몇 %인가.
                        if let fill = capacity?.fill {
                            // 넘어선 것은 좋은 소식이 아니다. 지금의 유입 · 이탈로는 못
                            // 떠받치는 수라 앞으로 내려간다. "상한 넘어섬"은 자꾸 좋게
                            // 읽혀서, 무슨 일이 일어날지를 그대로 적는다.
                            Text(fill > 1 ? "줄어들 흐름" : "상한의 \(Int((fill * 100).rounded()))%")
                                .foregroundStyle(fill > 1 ? .orange : .secondary)
                                .help(fill > 1
                                      ? "지금 활동 사용자가 지금의 유입과 이탈로 지킬 수 있는 수(상한)보다 많습니다. 최근에 몰린 사람이 빠지면서 상한 쪽으로 줄어듭니다."
                                      : "지금의 유입과 이탈이 이어지면 활동 사용자가 멈추는 자리(상한)의 몇 %까지 왔는가.")
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
                    // 목록이 MAU 순이라 그 숫자가 이 자리에 선다. 안 읽은 피드백은
                    // 숫자가 아니라 뱃지다 — 같은 활자로 적으면 읽을 것과 구경할 것이
                    // 같은 무게로 보인다.
                    HStack(spacing: 6) {
                        if unread > 0 {
                            CountBadge(count: unread, systemImage: "envelope.badge.fill",
                                       tint: .red, name: "안 읽은 피드백")
                        }
                        if traffic.hasUsageData {
                            Text("\(mainMetric.name) \(AppFormat.count(mainMetric.value))")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(mainMetric.value > 0 ? .primary : .secondary)
                                .help("\(cycle.map { "\($0.label) 쓰는 앱이라 \($0.metricName)" } ?? "사용 주기를 안 정해 MAU")를 보입니다(통계 → 습관 카드에서 정함). 목록은 MAU 순 — MAU \(traffic.mau)명, 7일 \(traffic.activeInstalls7)명, 어제 DAU \(traffic.dauYesterday)명.")
                        } else if unread == 0 {
                            Text("\(count)건")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
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

    /// 사용 주기에 맞는 지표 — 매일 DAU(어제), 매주 WAU(7일), 가끔 · 안 정함 MAU.
    private var mainMetric: (name: String, value: Int) {
        switch cycle {
        case .daily: ("DAU", traffic.dauYesterday)
        case .weekly: ("WAU", traffic.activeInstalls7)
        case .occasional, nil: ("MAU", traffic.mau)
        }
    }

    private var accessibilityText: String {
        var parts = ["\(name)"]
        if traffic.hasUsageData { parts.append("\(mainMetric.name) \(mainMetric.value)명") }
        if let fill = capacity?.fill, let ceiling = capacity?.capacity {
            parts.append(fill > 1
                         ? "성장 상한 \(Int(ceiling.rounded()))명보다 많아 줄어들 흐름"
                         : "성장 상한 \(Int(ceiling.rounded()))명 중 \(Int((fill * 100).rounded()))퍼센트")
        }
        parts.append("피드백 \(count)건")
        if unread > 0 { parts.append("안 읽음 \(unread)건") }
        if crashes7 > 0 { parts.append("최근 7일 진단 \(crashes7)건") }
        if let release { parts.append("릴리즈 건강 \(release.label)") }
        return parts.joined(separator: ", ")
    }
}

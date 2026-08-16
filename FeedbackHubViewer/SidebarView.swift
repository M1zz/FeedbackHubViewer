//
//  SidebarView.swift
//  FeedbackHubViewer
//
//  The left column: summary statistics and filters (version, minimum rating).
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: FeedbackStore
    #if os(iOS)
    // On iOS this view is presented as a sheet, so picking a project should
    // close it and reveal the filtered content underneath.
    @Environment(\.dismiss) private var dismiss
    #endif

    /// Close the sheet on iOS; a no-op in the macOS sidebar.
    private func dismissIfPresented() {
        #if os(iOS)
        dismiss()
        #endif
    }

    var body: some View {
        List {
            Section(store.selectedProject == nil ? "요약 (전체)" : "요약 · \(store.displayName(for: store.selectedProject!))") {
                let stats = store.stats
                HStack {
                    Label("CloudKit 환경", systemImage: "cloud")
                    Spacer()
                    EnvironmentBadge()
                }
                .font(.callout)
                StatRow(title: store.selectedProject == nil ? "전체 피드백" : "이 프로젝트",
                        value: "\(stats.total)건", systemImage: "tray.full")
                StatRow(title: "프로젝트 수", value: "\(store.availableProjects.count)개", systemImage: "square.grid.2x2")
                if let avg = stats.averageRating {
                    StatRow(title: "평균 별점",
                            value: String(format: "%.2f / 5", avg),
                            systemImage: "star.fill")
                }
                StatRow(title: "최근 7일", value: "\(stats.last7Days)건", systemImage: "clock")
                HStack {
                    Label("안 읽음", systemImage: "envelope.badge")
                    Spacer()
                    if store.scopedUnreadCount > 0 {
                        UnreadBadge(count: store.scopedUnreadCount)
                    } else {
                        Text("0건").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
                if store.scopedUnreadCount > 0 {
                    Button {
                        store.markAllRead(project: store.selectedProject)
                    } label: {
                        Label(store.selectedProject == nil ? "모두 읽음으로 표시" : "이 프로젝트 모두 읽음으로 표시",
                              systemImage: "envelope.open")
                            .font(.callout)
                    }
                }
                if let type = store.resolvedRecordType {
                    StatRow(title: "레코드 타입", value: type, systemImage: "square.stack.3d.up")
                }
            }

            if !store.projectCounts.isEmpty {
                Section("프로젝트") {
                    ProjectRow(name: "전체 프로젝트",
                               count: store.allFeedback.count,
                               isSelected: store.selectedProject == nil) {
                        store.selectedProject = nil
                        dismissIfPresented()
                    }
                    ForEach(store.projectCounts, id: \.key) { entry in
                        ProjectRow(name: store.displayName(for: entry.key),
                                   count: entry.count,
                                   isSelected: store.selectedProject == entry.key) {
                            store.selectedProject = (store.selectedProject == entry.key) ? nil : entry.key
                            dismissIfPresented()
                        }
                        .contextMenu {
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

            if store.stats.averageRating != nil {
                Section("별점 분포") {
                    RatingDistributionView(counts: store.stats.ratingCounts,
                                           total: store.stats.total)
                }
            }

            Section("필터") {
                Picker("앱 버전", selection: $store.selectedVersion) {
                    Text("전체 버전").tag(String?.none)
                    ForEach(store.availableVersions, id: \.self) { version in
                        Text("v\(version)").tag(String?.some(version))
                    }
                }

                Picker("최소 별점", selection: $store.minimumRating) {
                    Text("전체").tag(0)
                    ForEach((1...5).reversed(), id: \.self) { r in
                        Text("\(r)점 이상").tag(r)
                    }
                }

                if store.selectedProject != nil || store.selectedVersion != nil || store.minimumRating > 0 || !store.searchText.isEmpty {
                    Button {
                        store.selectedProject = nil
                        store.selectedVersion = nil
                        store.minimumRating = 0
                        store.searchText = ""
                    } label: {
                        Label("필터 초기화", systemImage: "xmark.circle")
                    }
                }
            }

            if !store.stats.versionCounts.isEmpty {
                Section("버전별 건수") {
                    ForEach(store.stats.versionCounts.prefix(12), id: \.version) { entry in
                        HStack {
                            Text("v\(entry.version)")
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .hubSidebarListStyle()
    }
}

/// A selectable project row in the sidebar: name on the left, feedback count
/// on the right, a checkmark when it is the active filter.
private struct ProjectRow: View {
    let name: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 12))
                Text(name)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StatRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private struct RatingDistributionView: View {
    let counts: [(rating: Int, count: Int)]
    let total: Int

    private var maxCount: Int { max(counts.map(\.count).max() ?? 1, 1) }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(counts, id: \.rating) { entry in
                HStack(spacing: 8) {
                    HStack(spacing: 1) {
                        Text("\(entry.rating)")
                            .font(.caption.monospacedDigit())
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                    .frame(width: 24, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(2, geo.size.width * CGFloat(entry.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 10)

                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

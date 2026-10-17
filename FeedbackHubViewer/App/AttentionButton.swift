//
//  AttentionButton.swift
//  FeedbackHubViewer
//
//  툴바의 종. 새로 온 것이 몇 건인지 뱃지로 보이고, 누르면 앱마다 무엇이 왔는지 나와서
//  그 탭으로 바로 간다. 무엇을 셀지는 설정의 "알림" 이 정하고(기본: 리뷰 · 피드백),
//  새 리뷰가 늘 맨 앞 — `AttentionKind` 의 순서.
//
//  수는 `FeedbackStore+Attention.swift` 에서 온다. 상태를 읽는 것은 이 뷰 안에서만 —
//  툴바 항목 자체가 상태에 따라 다시 만들어지면 맥에서 툴바가 깨진 적이 있다
//  (`IdentityMenu` 머리말).
//

import SwiftUI

struct AttentionButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    @State private var isOpen = false

    var body: some View {
        let total = store.attentionCount
        Button {
            isOpen.toggle()
        } label: {
            Label("새 소식", systemImage: total > 0 ? "bell.badge.fill" : "bell")
                .symbolRenderingMode(total > 0 ? .multicolor : .monochrome)
                .overlay(alignment: .topTrailing) {
                    if total > 0 {
                        Text(total > 99 ? "99+" : "\(total)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .offset(x: 8, y: -6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .help(total > 0 ? "새로 온 것 \(total)건" : "새로 온 것이 없습니다")
        .accessibilityLabel(total > 0 ? "새 소식 \(total)건" : "새 소식 없음")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            AttentionList { project, section in
                isOpen = false
                store.open(project: project, section: section)
            }
            .environmentObject(store)
            .environmentObject(connect)
            #if os(iOS)
            // 아이폰에서도 시트가 아니라 종 밑에 작게.
            .presentationCompactAdaptation(.popover)
            #endif
        }
    }
}

/// 앱마다 새로 온 것. 한 줄을 누르면 그 앱의 해당 탭으로.
private struct AttentionList: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    let open: (String, FeedbackStore.ProjectSection) -> Void

    private struct Entry: Identifiable {
        let project: String
        /// 우선순위 순(리뷰 → 피드백 → 진단), 0건은 뺀 것.
        let counts: [(kind: AttentionKind, count: Int)]
        var id: String { project }
        func count(_ kind: AttentionKind) -> Int { counts.first { $0.kind == kind }?.count ?? 0 }
    }

    private func count(_ kind: AttentionKind, in project: String) -> Int {
        switch kind {
        case .review: connect.newReviewCount(for: project)
        case .feedback: store.unreadCount(for: project)
        case .crash: store.newCrashCount(for: project)
        }
    }

    private static func section(for kind: AttentionKind) -> FeedbackStore.ProjectSection {
        switch kind {
        case .review: .reviews
        case .feedback: .feedback
        case .crash: .crashes
        }
    }

    var body: some View {
        let kinds = AttentionKind.allCases.filter(store.showsBadge)
        let entries = store.projectCounts.map(\.key)
            .map { project in
                Entry(project: project,
                      counts: kinds.map { ($0, count($0, in: project)) }.filter { $0.count > 0 })
            }
            .filter { !$0.counts.isEmpty }
            // 새 리뷰가 많은 앱이 먼저, 같으면 피드백, 그다음 진단.
            .sorted { a, b in
                for kind in kinds where a.count(kind) != b.count(kind) {
                    return a.count(kind) > b.count(kind)
                }
                return false
            }
        let checkable = kinds.filter { $0 != .feedback }

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("새로 온 것")
                    .font(.headline)
                Spacer()
                if !entries.isEmpty, !checkable.isEmpty {
                    Button("\(checkable.map(\.name).joined(separator: " · ")) 모두 확인") {
                        if checkable.contains(.review) { connect.markReviewsViewed(bundleID: nil) }
                        if checkable.contains(.crash) { store.markCrashesViewed(project: nil) }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
            .padding(12)
            Divider()

            if entries.isEmpty {
                Text(kinds.isEmpty ? "설정 → 알림에서 뱃지로 볼 것을 고를 수 있습니다."
                                   : "새로 온 \(kinds.map(\.name).joined(separator: " · "))가 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(minWidth: 300, idealWidth: 340)
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.displayName(for: entry.project))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(entry.counts, id: \.kind) { item in
                    chip(item.count, item.kind.name, item.kind.systemImage) {
                        open(entry.project, Self.section(for: item.kind))
                    }
                }
            }
        }
    }

    private func chip(_ count: Int, _ name: String, _ systemImage: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("새 \(name) \(count)", systemImage: systemImage)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("새 \(name) \(count)건, 열기")
    }
}

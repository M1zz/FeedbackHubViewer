//
//  ContentView.swift
//  FeedbackHubViewer
//
//  Three-column layout: filters + stats on the left, the feedback list in the
//  middle, the selected item's detail on the right.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FeedbackStore
    @State private var selection: Feedback.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } content: {
            FeedbackListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
        } detail: {
            detailColumn
        }
        .navigationTitle("Feedback Hub")
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selection, let feedback = store.allFeedback.first(where: { $0.id == id }) {
            FeedbackDetailView(feedback: feedback)
        } else {
            ContentUnavailableView(
                "피드백을 선택하세요",
                systemImage: "text.bubble",
                description: Text("왼쪽 목록에서 항목을 선택하면 전체 내용이 여기에 표시됩니다.")
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if let updated = store.lastUpdated {
                Text("업데이트: \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $store.autoRefresh) {
                Label("자동 갱신", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("1분마다 자동으로 새로고침합니다")
            .toggleStyle(.button)

            Button {
                Task { await store.load() }
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
            .help("지금 새로고침 (⌘R)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(FeedbackStore())
        .frame(width: 1000, height: 620)
}

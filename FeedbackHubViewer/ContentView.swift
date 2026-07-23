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
            Group {
                switch store.viewMode {
                case .overview:
                    ProjectOverviewView()
                case .stats:
                    StatisticsView()
                case .list:
                    FeedbackListView(selection: $selection)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 640)
        } detail: {
            detailColumn
        }
        .navigationTitle("Feedback Hub")
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selection, let feedback = store.allFeedback.first(where: { $0.id == id }) {
            FeedbackDetailView(feedback: feedback,
                               projectLabel: store.displayName(for: feedback.projectKey))
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
        ToolbarItem(placement: .principal) {
            Picker("보기", selection: $store.viewMode) {
                ForEach(FeedbackStore.ViewMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("프로젝트 개요와 피드백 목록 전환")
        }
        ToolbarItem(placement: .primaryAction) {
            IdentityMenu(userRecordName: store.userRecordName)
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

/// A toolbar menu that shows this account's CloudKit user record name and lets
/// the developer copy it — the value to register in an admin Security Role so
/// the account can read feedback that World is not permitted to read.
private struct IdentityMenu: View {
    let userRecordName: String?

    var body: some View {
        Menu {
            if let name = userRecordName, !name.isEmpty {
                Section("내 CloudKit User Record Name") {
                    Text(name)
                }
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(name, forType: .string)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                Text("CloudKit Console → Security Roles의 admin 역할에 이 값을 등록하고 피드백 레코드 타입에 read 권한을 준 뒤 Production으로 배포하세요.")
            } else {
                Text("iCloud 계정을 확인할 수 없습니다. 이 Mac에 iCloud 로그인이 되어 있는지 확인하세요.")
            }
        } label: {
            Label("내 계정 ID", systemImage: "person.crop.circle.badge.questionmark")
        }
        .help("Security Role 등록에 쓸 내 CloudKit User Record Name")
    }
}

#Preview {
    ContentView()
        .environmentObject(FeedbackStore())
        .frame(width: 1000, height: 620)
}

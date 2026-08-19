//
//  PhoneRootView.swift
//  FeedbackHubViewer
//
//  The iPhone layout. The hierarchy is the same as on a Mac, only stacked:
//  프로젝트 목록 → 그 프로젝트의 피드백 · 통계 · 진단 → 피드백 상세. There is no
//  tab bar any more; tabs made 통계 a peer of the project list, which put the
//  same screens at two different levels of the app.
//

#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        NavigationStack(path: $store.path) {
            ProjectListView()
                .navigationDestination(for: FeedbackStore.ProjectRoute.self) { route in
                    ProjectSectionView(project: route.project)
                        .task {
                            store.selectedProject = route.project
                            if let section = route.section { store.projectSection = section }
                        }
                        .modifier(HubToolbar())
                }
                .navigationDestination(for: Feedback.self) { feedback in
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                }
                .modifier(HubToolbar())
        }
        // Cross-screen links push here rather than re-scoping a column.
        .task { store.usesStackNavigation = true }
    }
}

/// Navigation-bar items shared by every screen in the stack: refresh and an
/// overflow menu, plus pull-to-refresh.
private struct HubToolbar: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.load() }
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $store.autoRefresh) {
                            Label("자동 갱신 (1분)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Toggle(isOn: $store.notificationsEnabled) {
                            Label("새 피드백·진단 알림", systemImage: "bell.badge")
                        }
                        if store.notificationsEnabled && !store.notificationsAuthorized {
                            Section {
                                Text("시스템 설정에서 이 앱의 알림을 허용해야 알림이 표시됩니다.")
                            }
                        }
                        if let updated = store.lastUpdated {
                            Section {
                                Text("업데이트: \(AppFormat.time(updated))")
                            }
                        }
                        Section {
                            IdentityMenu()
                        }
                    } label: {
                        Label("더 보기", systemImage: "ellipsis.circle")
                    }
                }
            }
            .refreshable { await store.load() }
    }
}

#Preview {
    PhoneRootView()
        .environmentObject(FeedbackStore())
}
#endif

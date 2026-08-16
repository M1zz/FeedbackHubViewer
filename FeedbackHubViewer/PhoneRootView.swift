//
//  PhoneRootView.swift
//  FeedbackHubViewer
//
//  The iOS / iPadOS layout. A three-column split view doesn't fit a phone, so
//  the two panes become tabs — 개요 / 통계 — each in its own navigation stack.
//  The feedback list and the per-project dashboard are pushed on top of them.
//  The sidebar (요약 + 필터) moves into a sheet, and the feedback detail is
//  pushed instead of shown in a third column.
//

#if os(iOS)
import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var store: FeedbackStore

    var body: some View {
        TabView(selection: $store.viewMode) {
            NavigationStack(path: $store.listPath) {
                ProjectOverviewView()
                    .modifier(HubDestinations())
                    .modifier(HubToolbar())
            }
            .tabItem { Label(FeedbackStore.ViewMode.overview.rawValue,
                             systemImage: FeedbackStore.ViewMode.overview.systemImage) }
            .badge(store.unreadCount)
            .tag(FeedbackStore.ViewMode.overview)

            NavigationStack(path: $store.statsPath) {
                StatisticsView()
                    .modifier(HubDestinations())
                    .modifier(HubToolbar())
            }
            .tabItem { Label(FeedbackStore.ViewMode.stats.rawValue,
                             systemImage: FeedbackStore.ViewMode.stats.systemImage) }
            .tag(FeedbackStore.ViewMode.stats)
        }
    }
}

/// Everything the two stacks can push. Registered on both roots so a route
/// opened from 개요 and the same route opened from 통계 land on the same
/// screen, with the app scoped to the project the route names.
private struct HubDestinations: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: FeedbackStore.ListRoute.self) { route in
                FeedbackListView(selection: .constant(nil))
                    .task { store.selectedProject = route.project }
                    .modifier(HubToolbar())
            }
            .navigationDestination(for: FeedbackStore.StatsRoute.self) { route in
                StatisticsDashboard(project: route.project)
                    .task { store.selectedProject = route.project }
                    .modifier(HubToolbar())
            }
            .navigationDestination(for: FeedbackStore.CrashRoute.self) { route in
                CrashListView(project: route.project)
                    .modifier(HubToolbar())
            }
            .navigationDestination(for: Feedback.self) { feedback in
                FeedbackDetailView(feedback: feedback,
                                   projectLabel: store.displayName(for: feedback.projectKey))
            }
    }
}

/// Navigation-bar items shared by every tab: filters on the left, refresh and
/// an overflow menu on the right, plus pull-to-refresh.
private struct HubToolbar: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore
    @State private var showsFilters = false

    private var hasActiveFilters: Bool {
        store.selectedProject != nil
            || store.selectedVersion != nil
            || store.minimumRating > 0
            || !store.searchText.isEmpty
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsFilters = true
                    } label: {
                        Label("요약과 필터",
                              systemImage: hasActiveFilters
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.load() }
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $store.autoRefresh) {
                            Label("자동 갱신 (1분)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Toggle(isOn: $store.notificationsEnabled) {
                            Label("새 피드백·진단 알림", systemImage: "bell.badge")
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
            .sheet(isPresented: $showsFilters) {
                NavigationStack {
                    SidebarView()
                        .navigationTitle("요약 · 필터")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("완료") { showsFilters = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }
}

#Preview {
    PhoneRootView()
        .environmentObject(FeedbackStore())
}
#endif

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
                        .hubToolbar()
                }
                .navigationDestination(for: Feedback.self) { feedback in
                    FeedbackDetailView(feedback: feedback,
                                       projectLabel: store.displayName(for: feedback.projectKey))
                }
                .hubToolbar()
        }
        // Cross-screen links push here rather than re-scoping a column.
        .task { store.usesStackNavigation = true }
    }
}

#Preview {
    PhoneRootView()
        .environmentObject(FeedbackStore())
}
#endif

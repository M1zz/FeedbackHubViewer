//
//  DesignDocsView.swift
//  FeedbackHubViewer
//
//  프로젝트 화면의 "설계" 칸. 앱 리포의 `docs/product/process/` 에 있는 HTML 을
//  목록으로 보여 주고 "열기"로 기본 브라우저에서 연다. 폴더는 `DesignDocsStore` 가
//  지켜보고 있어서, 새 장을 넣거나 고치면 이 목록이 알아서 바뀐다.
//

import SwiftUI

struct DesignDocsView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore
    /// nil == 전체 프로젝트.
    let project: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !DesignDocsStore.isSupported {
                    message("설계 문서는 앱 리포가 있는 맥에서만 열 수 있습니다.", systemImage: "desktopcomputer")
                } else if design.workspace == nil {
                    chooseCard
                } else if let project, !design.hasRepo(for: project) {
                    DesignCanvasCard(project: project)
                } else {
                    if let project {
                        DesignCanvasCard(project: project)
                    } else {
                        DesignCanvasRollCall()
                    }
                    list
                }
                if let problem = design.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: TaskKey(project: project, workspace: design.workspace)) {
            design.watch(project: project)
        }
    }

    private struct TaskKey: Hashable {
        let project: String?
        let workspace: URL?
    }

    // MARK: - States

    private var chooseCard: some View {
        Card(title: "폴더를 한 번 골라 주세요", systemImage: "folder.badge.questionmark") {
            Text("앱 리포들이 들어 있는 workspace/code 폴더를 고르면, 각 리포의 \(DesignDocsStore.folder) 를 지켜보다가 새 설계 문서를 여기 띄웁니다.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("폴더 고르기") { design.chooseWorkspace() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var list: some View {
        let docs = design.docs(for: project)
        if docs.isEmpty {
            Card(title: "아직 설계 문서가 없습니다", systemImage: "doc.richtext") {
                Text("리포의 \(DesignDocsStore.folder) 에 HTML 을 넣으면 바로 여기 나옵니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let project {
                    Button("폴더 보기") { design.revealFolder(for: project) }
                }
            }
        } else {
            ForEach(docs) { doc in
                row(doc)
            }
            Button("다른 폴더 고르기") { design.chooseWorkspace() }
                .font(.body)
                .buttonStyle(.borderless)
        }
    }

    private func row(_ doc: DesignDocsStore.Doc) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title)
                    .font(.headline)
                Text(subtitle(doc))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("열기") { design.open(doc) }
                .buttonStyle(.borderedProminent)
        }
        .padding(Platform.cardPadding)
        .cardSurface()
        .contextMenu {
            Button("Finder 에서 보기") { design.revealFolder(for: doc.project) }
        }
    }

    private func subtitle(_ doc: DesignDocsStore.Doc) -> String {
        var text = doc.url.lastPathComponent + " · " + AppFormat.relative(doc.modified) + " 고침"
        if project == nil { text = store.displayName(for: doc.project) + " · " + text }
        return text
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Platform.cardPadding)
            .cardSurface()
    }
}

//
//  DesignCanvasViews.swift
//  FeedbackHubViewer
//
//  앱마다 하나씩 있어야 하는 설계 캔버스(`design-canvas.html`)로 가는 길.
//  툴바의 i 단추는 지금 보는 앱의 캔버스를 바로 열고, 없으면 없다고 - 그리고
//  만들어야 한다고 - 말한다. 설계 칸 맨 위에도 같은 판정이 뜬다.
//

import SwiftUI

/// 툴바의 i 단추. 캔버스가 있으면 누르자마자 열고, 아니면 까닭과 할 일을 띄운다.
/// 전체 프로젝트에서는 앱마다 있는지 없는지를 한눈에 보여 준다.
struct DesignCanvasButton: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore
    @State private var isShowing = false

    var body: some View {
        Button {
            if let project = store.selectedProject,
               case .ready(let url) = design.canvasState(for: project) {
                design.openCanvas(url)
            } else {
                isShowing.toggle()
            }
        } label: {
            Label("설계 캔버스", systemImage: "info.circle")
                .imageScale(.large)
        }
        .help("이 앱의 설계 캔버스를 엽니다")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let project = store.selectedProject {
                        DesignCanvasCard(project: project)
                    } else {
                        DesignCanvasRollCall()
                    }
                }
                .padding(Platform.cardPadding)
            }
            .frame(width: 420)
            .frame(maxHeight: 520)
            .environmentObject(store)
            .environmentObject(design)
        }
    }
}

/// 한 앱의 캔버스 판정 한 장.
struct DesignCanvasCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore
    let project: String

    var body: some View {
        switch design.canvasState(for: project) {
        case .ready(let url):
            Card(title: "설계 캔버스", systemImage: "info.circle") {
                Text("\(store.displayName(for: project))의 문제 정의 · 리서치 · 페르소나 · 저니맵 · 솔루션 · 결산.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("설계 캔버스 열기") { design.openCanvas(url) }
                    .buttonStyle(.borderedProminent)
            }
        case .missing:
            Card(title: "설계 캔버스가 없습니다", systemImage: "exclamationmark.triangle") {
                Text("모든 앱에는 설계 캔버스가 있어야 합니다. \(store.displayName(for: project))에는 아직 없으니 만들어야 합니다.")
                    .font(.body)
                Text("리포의 \(DesignDocsStore.folder)/\(DesignDocsStore.canvasFile) 로 저장하면 바로 여기서 열립니다. 문제 정의 · 리서치 · 페르소나 · 유저 저니맵 · 솔루션 · 문제 결산 순서로, ClipKeyboard 의 캔버스를 본보기로 삼으세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("폴더 보기") { design.revealFolder(for: project) }
            }
        case .noRepo:
            Card(title: "설계 캔버스를 찾을 수 없습니다", systemImage: "questionmark.folder") {
                Text("모든 앱에는 설계 캔버스가 있어야 하는데, \(store.displayName(for: project))의 리포 위치를 몰라서 있는지조차 볼 수 없습니다.")
                    .font(.body)
                Text("DesignDocsStore.repos 에 \"\(project)\" 와 리포 폴더 이름을 한 줄 더하고, 캔버스가 없다면 \(DesignDocsStore.folder)/\(DesignDocsStore.canvasFile) 로 만들어야 합니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .noWorkspace:
            Card(title: "폴더를 한 번 골라 주세요", systemImage: "folder.badge.questionmark") {
                Text("앱 리포들이 들어 있는 workspace/code 폴더를 고르면 설계 캔버스를 찾아 엽니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("폴더 고르기") { design.chooseWorkspace() }
                    .buttonStyle(.borderedProminent)
            }
        case .unsupported:
            Card(title: "맥에서 엽니다", systemImage: "desktopcomputer") {
                Text("설계 캔버스는 앱 리포가 있는 맥에서만 열 수 있습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 전체 프로젝트: 앱마다 캔버스가 있는지. 없는 앱이 먼저 온다.
struct DesignCanvasRollCall: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore

    var body: some View {
        if !DesignDocsStore.isSupported {
            DesignCanvasCard(project: "")
        } else if design.workspace == nil {
            Card(title: "폴더를 한 번 골라 주세요", systemImage: "folder.badge.questionmark") {
                Text("앱 리포들이 들어 있는 workspace/code 폴더를 고르면 앱마다 설계 캔버스가 있는지 봅니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("폴더 고르기") { design.chooseWorkspace() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            let rows = self.rows
            let lacking = rows.filter { $0.url == nil }.count
            Card(title: "설계 캔버스", systemImage: "info.circle") {
                Text(lacking == 0
                     ? "모든 앱에 설계 캔버스가 있습니다."
                     : "모든 앱에는 설계 캔버스가 있어야 합니다. \(lacking)개 앱에 없으니 만들어야 합니다.")
                    .font(.body)
                    .foregroundStyle(lacking == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                ForEach(rows, id: \.project) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.url == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(row.url == nil ? .orange : .green)
                        Text(store.displayName(for: row.project))
                            .font(.body)
                        Spacer(minLength: 8)
                        if let url = row.url {
                            Button("열기") { design.openCanvas(url) }
                        } else {
                            Text(row.reason)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var rows: [(project: String, url: URL?, reason: String)] {
        let all: [(project: String, url: URL?, reason: String)] = store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject }
            .map { project in
                switch design.canvasState(for: project) {
                case .ready(let url): return (project, url, "")
                case .missing: return (project, nil, "만들어야 함")
                case .noRepo: return (project, nil, "리포 모름")
                case .noWorkspace, .unsupported: return (project, nil, "")
                }
            }
        return all.filter { $0.url == nil } + all.filter { $0.url != nil }
    }
}

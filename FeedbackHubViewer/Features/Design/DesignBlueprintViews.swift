//
//  DesignBlueprintViews.swift
//  FeedbackHubViewer
//
//  화면 설계도 - 앱의 화면마다 지금 모습과 바꿀 모습(펼친 세로 · 가로)을 나란히
//  놓은 대응표. 원본은 claude.ai 아티팩트이고, 사본이 두 군데 있다.
//
//  1. 앱 리포의 `docs/product/process/screen-blueprint.html` - 맥에서 폴더를 골랐으면
//     이것이 이긴다. 리포에서 고치면 바로 그 판이 열린다.
//  2. 이 앱 안의 `Blueprints/blueprint-<프로젝트 키>.html` - 폰 · 패드, 폴더를 안 고른 맥.
//     스크린샷까지 HTML 안에 넣은 한 장짜리라 오프라인에서도 열린다.
//  3. 둘 다 없으면 아티팩트 주소.
//
//  새 설계도를 만들면 리포에 넣고, 이 앱의 Blueprints 에도 복사하고, `webURLs` 에 한 줄.
//

import SwiftUI
import WebKit

enum DesignBlueprints {
    /// 리포 안 `DesignDocsStore.folder` 에서의 파일 이름.
    static let fileName = "screen-blueprint.html"

    /// 허브의 프로젝트 키 → 원본 아티팩트.
    static let webURLs: [String: URL] = [
        "com.Ysoup.TokenMemo": URL(string: "https://claude.ai/artifact/DHGoM3DCmFQzzURDjHWCKL")!,
        "com.xa.toki": URL(string: "https://claude.ai/artifact/YK6y7kcPf3hTAWLHD2dtTK")!,
        "com.example.ScheduleDensityApp": URL(string: "https://claude.ai/artifact/N4LnKoVDVo8rPtAHQQfphT")!,
        "com.Ysoup.LeaveWise": URL(string: "https://claude.ai/artifact/K6qv6q4fJwivvimcBBhrcA")!,
    ]

    enum Source {
        case repo(URL)
        case bundled(URL)
        case web(URL)

        var url: URL {
            switch self {
            case .repo(let url), .bundled(let url), .web(let url): url
            }
        }

        var label: String {
            switch self {
            case .repo: "리포 파일"
            case .bundled: "앱에 든 사본"
            case .web: "아티팩트(웹)"
            }
        }
    }

    static func bundledURL(for project: String) -> URL? {
        Bundle.main.url(forResource: "blueprint-\(project)", withExtension: "html")
    }

    /// 열 판. nil 이면 이 앱에는 설계도가 없다.
    @MainActor
    static func source(for project: String, design: DesignDocsStore) -> Source? {
        if let folder = design.folderURL(for: project) {
            let file = folder.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: file.path) { return .repo(file) }
        }
        if let url = bundledURL(for: project) { return .bundled(url) }
        if let url = webURLs[project] { return .web(url) }
        return nil
    }
}

/// 설계도를 여는 단추. 맥은 파일을 기본 브라우저로, 폰 · 패드는 앱 안 시트로 연다.
struct BlueprintOpenButton: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let source: DesignBlueprints.Source
    var prominent = false
    @State private var showing: URL?

    var body: some View {
        Group {
            if prominent {
                Button(title, action: open).buttonStyle(.borderedProminent)
            } else {
                Button(title, action: open)
            }
        }
        .sheet(item: $showing) { url in
            BlueprintSheet(url: url)
        }
    }

    private func open() {
        switch source {
        case .web(let url):
            openURL(url)
        case .repo(let url), .bundled(let url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            showing = url
            #endif
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// 한 앱의 화면 설계도 판정 한 장.
struct DesignBlueprintCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore
    let project: String

    var body: some View {
        if let source = DesignBlueprints.source(for: project, design: design) {
            Card(title: "화면 설계도 있음", systemImage: "checkmark.circle.fill") {
                Text("\(store.displayName(for: project))의 화면마다 지금 모습과 펼친 세로 · 가로 시안을 나란히 놓은 대응표. \(source.label)로 엽니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                BlueprintOpenButton(title: "화면 설계도 열기", source: source, prominent: true)
            }
        } else {
            Card(title: "화면 설계도 없음", systemImage: "xmark.circle") {
                Text("\(store.displayName(for: project))에는 아직 화면 설계도가 없습니다.")
                    .font(.body)
                Text("만들면 리포의 \(DesignDocsStore.folder)/\(DesignBlueprints.fileName) 로 저장하고, 이 앱의 Blueprints 폴더에도 blueprint-\(project).html 로 복사하세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// 전체 프로젝트: 앱마다 화면 설계도가 있는지. 있는 앱이 먼저 온다.
struct DesignBlueprintRollCall: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var design: DesignDocsStore

    private struct Row {
        let project: String
        let source: DesignBlueprints.Source?
    }

    var body: some View {
        let rows = self.rows
        let made = rows.filter { $0.source != nil }.count
        Card(title: "화면 설계도", systemImage: "rectangle.split.2x1") {
            Text("\(rows.count)개 앱 중 \(made)개에 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.project) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.source == nil ? "xmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(row.source == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                    Text(store.displayName(for: row.project))
                        .font(.body)
                    Spacer(minLength: 8)
                    if let source = row.source {
                        Text(source.label)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        BlueprintOpenButton(title: "열기", source: source)
                    } else {
                        Text("없음")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var rows: [Row] {
        let all: [Row] = store.allProjectKeys
            .filter { $0 != Feedback.unclassifiedProject }
            .map { Row(project: $0, source: DesignBlueprints.source(for: $0, design: design)) }
        return all.filter { $0.source != nil } + all.filter { $0.source == nil }
    }
}

/// 폰 · 패드에서 앱에 든 설계도를 띄우는 시트.
private struct BlueprintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            BlueprintWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("화면 설계도")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
    }
}

#if os(iOS)
private struct BlueprintWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#else
private struct BlueprintWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif

//
//  DesignDocsStore.swift
//  FeedbackHubViewer
//
//  앱을 왜 이렇게 만들었는가 - 문제 정의 · 페르소나 · 저니맵 · 솔루션 도출 - 를 적은
//  HTML 은 숫자가 아니라서 허브(CloudKit)에 없다. 각 앱 리포의 `docs/product/process/`
//  에 한 장씩 산다. 이 스토어는 그 폴더를 지켜보다가 새 장이 생기거나 고쳐지면 목록을
//  다시 읽고, "열기"를 누르면 기본 브라우저로 연다.
//
//  맥만 된다. 리포는 이 맥의 디스크에 있고, 폰에는 없다.
//
//  샌드박스라서 `~/Documents/workspace/code` 를 마음대로 읽지 못한다. 처음 한 번 그
//  폴더를 고르게 하고(`NSOpenPanel`), 그 허락을 보안 범위 북마크로 남겨 다음 실행에도
//  다시 묻지 않는다.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class DesignDocsStore: ObservableObject {

    /// HTML 한 장.
    struct Doc: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        /// `<title>` 이 있으면 그것, 없으면 파일 이름.
        let title: String
        let modified: Date
        /// 어느 프로젝트(허브의 프로젝트 키)의 것인가.
        let project: String
    }

    /// 리포 안에서 설계 문서가 사는 자리. 앱 리포 쪽 README 가 이 경로를 가리킨다
    /// (ClipKeyboard 의 `docs/product/process/README.md`). 바꾸면 양쪽을 같이.
    static let folder = "docs/product/process"

    /// 허브의 프로젝트 키 → `workspace/code/` 아래 리포 폴더 이름.
    /// 스펙의 `appName` 은 사람이 읽는 이름이라(두번알림) 폴더 이름으로 못 쓴다.
    static let repos: [String: String] = [
        "com.Ysoup.TokenMemo": "ClipKeyboard",
        "com.xa.toki": "Rereminder",
    ]

    /// 고른 `workspace/code` 폴더. nil 이면 아직 안 골랐다.
    @Published private(set) var workspace: URL?
    /// 프로젝트 키별 문서, 최근에 고친 것이 먼저.
    @Published private(set) var docs: [String: [Doc]] = [:]
    /// 폴더를 못 열었을 때의 까닭.
    @Published private(set) var problem: String?

    private static let bookmarkKey = "designDocs.workspaceBookmark"
    private var watchers: [URL: DispatchSourceFileSystemObject] = [:]
    private var watchedProjects: [String] = []

    init() {
        restoreWorkspace()
    }

    static var isSupported: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func hasRepo(for project: String) -> Bool { Self.repos[project] != nil }

    func folderURL(for project: String) -> URL? {
        guard let workspace, let repo = Self.repos[project] else { return nil }
        return workspace.appendingPathComponent(repo).appendingPathComponent(Self.folder)
    }

    // MARK: - Design canvas

    /// 앱마다 한 장씩 있어야 하는 설계 캔버스(문제 정의 · 리서치 · 페르소나 · 저니맵 ·
    /// 솔루션 · 결산). 다른 HTML 은 있어도 그만이지만 이 장은 빠지면 안 된다.
    static let canvasFile = "design-canvas.html"

    enum CanvasState {
        /// 폰 · 패드. 리포가 이 기기에 없다.
        case unsupported
        /// `workspace/code` 폴더를 아직 안 골랐다.
        case noWorkspace
        /// 이 앱의 리포 폴더를 모른다(`repos` 에 없음).
        case noRepo
        /// 리포는 아는데 캔버스가 없다 - 만들어야 한다.
        case missing(folder: URL)
        case ready(URL)
    }

    /// 지켜보는 목록과 따로, 누를 때마다 디스크를 직접 본다. 툴바 단추는 설계 칸을
    /// 연 적이 없어도 맞는 답을 내야 해서.
    func canvasState(for project: String) -> CanvasState {
        guard Self.isSupported else { return .unsupported }
        guard workspace != nil else { return .noWorkspace }
        guard let folder = folderURL(for: project) else { return .noRepo }
        let file = folder.appendingPathComponent(Self.canvasFile)
        return FileManager.default.fileExists(atPath: file.path) ? .ready(file) : .missing(folder: folder)
    }

    func openCanvas(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    func docs(for project: String?) -> [Doc] {
        guard let project else {
            return docs.values.flatMap { $0 }.sorted { $0.modified > $1.modified }
        }
        return docs[project] ?? []
    }

    // MARK: - Watching

    /// 이 프로젝트들의 폴더를 지켜본다. nil 은 전체 프로젝트, 곧 리포를 아는 앱 전부.
    func watch(project: String?) {
        let projects = project.map { [$0] } ?? Array(Self.repos.keys)
        watchedProjects = projects.filter { Self.repos[$0] != nil }
        rescan()
    }

    /// 목록을 다시 읽고, 지켜볼 폴더를 다시 건다. 폴더가 아직 없으면 가장 가까운
    /// 있는 조상을 지켜본다 - 그래야 폴더가 처음 생기는 순간도 잡는다.
    func rescan() {
        stopWatching()
        var next: [String: [Doc]] = [:]
        for project in watchedProjects {
            guard let folder = folderURL(for: project) else { continue }
            next[project] = Self.scan(folder, project: project)
            if let target = Self.nearestExisting(folder) { startWatching(target) }
        }
        docs = next
    }

    private func startWatching(_ url: URL) {
        guard watchers[url] == nil else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            // 저장 한 번에 이벤트가 여러 개 온다. 다 읽은 뒤에 한 번만 다시 본다.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.rescan()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[url] = source
    }

    private func stopWatching() {
        watchers.values.forEach { $0.cancel() }
        watchers.removeAll()
    }

    private static func nearestExisting(_ url: URL) -> URL? {
        var current = url
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: current.path) { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private static func scan(_ folder: URL, project: String) -> [Doc] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return files
            .filter { ["html", "htm"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
                return Doc(url: url, title: title(of: url), modified: modified, project: project)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// 앞쪽 8KB 에서 `<title>` 을 찾는다. 아티팩트에서 옮긴 장은 `<body>` 안에 두기도 해서
    /// 머리에만 있다고 가정하지 않는다.
    private static func title(of url: URL) -> String {
        let fallback = url.deletingPathExtension().lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fallback }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192),
              let head = String(data: data, encoding: .utf8) ?? String(data: data.dropLast(3), encoding: .utf8),
              let open = head.range(of: "<title>", options: .caseInsensitive),
              let close = head.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<head.endIndex)
        else { return fallback }
        let title = head[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }

    // MARK: - Opening

    func open(_ doc: Doc) {
        #if os(macOS)
        NSWorkspace.shared.open(doc.url)
        #endif
    }

    func revealFolder(for project: String) {
        #if os(macOS)
        guard let folder = folderURL(for: project), let target = Self.nearestExisting(folder) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        #endif
    }

    // MARK: - Workspace permission

    /// `workspace/code` 폴더를 고르게 한다. 고른 허락은 북마크로 남는다.
    func chooseWorkspace() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 지켜보기"
        panel.message = "앱 리포들이 들어 있는 workspace/code 폴더를 고르세요."
        // 샌드박스 안의 홈은 컨테이너라, 진짜 홈을 따로 구한다.
        if let pw = getpwuid(getuid()) {
            let home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            panel.directoryURL = home.appendingPathComponent("Documents/workspace/code")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            restoreWorkspace()
            rescan()
        } catch {
            problem = "폴더 허락을 남기지 못했습니다: \(error.localizedDescription)"
            print("❌ [DesignDocsStore.chooseWorkspace] \(error)")
        }
        #endif
    }

    func forgetWorkspace() {
        workspace?.stopAccessingSecurityScopedResource()
        workspace = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        stopWatching()
        docs = [:]
    }

    private func restoreWorkspace() {
        #if os(macOS)
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                problem = "\(url.path) 를 열 수 없습니다. 폴더를 다시 골라 주세요."
                return
            }
            workspace?.stopAccessingSecurityScopedResource()
            workspace = url
            problem = nil
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                         includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
        } catch {
            problem = "남겨 둔 폴더 허락을 읽지 못했습니다. 폴더를 다시 골라 주세요."
            print("❌ [DesignDocsStore.restoreWorkspace] \(error)")
        }
        #endif
    }
}

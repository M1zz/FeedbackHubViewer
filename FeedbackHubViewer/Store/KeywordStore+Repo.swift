//
//  KeywordStore+Repo.swift
//  FeedbackHubViewer
//
//  레포에서 새로 짠 키워드가 스토어에 나가기를 기다리는 중인가.
//
//  "다시 짤 때" 는 스토어에 나가 있는 칸만 보고 판정한다. 그런데 키워드는 레포의 `APPSTORE.md`
//  에서 고치고 다음 배포 · 심사 통과 때 스토어에 나간다. 그 사이 칸은 옛 말 그대로라, 이미 다시
//  짠 앱에도 "다시 짤 때" 가 계속 붙었다. 레포의 키워드 줄을 읽어 스토어 칸과 다르면
//  "출시 기다림" 으로 가른다.
//
//  맥만 된다. 레포는 이 맥의 디스크에 있고, 샌드박스라 `workspace/Auto` 폴더를 한 번 골라
//  받은 허락(보안 범위 북마크)으로 읽는다.
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// `APPSTORE.md` 를 읽는 규칙. 파일 형식은 DeployBar 가 정한다(CLAUDE.md "릴리즈 노트 작성 규칙").
enum RepoKeywords {

    static func key(project: String, locale: String) -> String { "\(project.lowercased())|\(locale)" }

    /// 레포 폴더 → 그 레포의 로케일별 키워드 줄. 번들 id 는 Xcode 프로젝트 · project.yml 에서 찾는다.
    /// 반환: `key(project:locale:)` → 말들. 한 레포가 여러 번들(위젯 등)을 가지면 모두 같은 줄을 가리킨다.
    static func scan(_ root: URL, projects: [String]) -> [String: [String]] {
        let fm = FileManager.default
        let wanted = Dictionary(projects.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var result: [String: [String]] = [:]
        let repos = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for repo in repos {
            let storeFile = repo.appendingPathComponent("APPSTORE.md")
            guard let text = try? String(contentsOf: storeFile, encoding: .utf8) else { continue }
            let bundles = bundleIDs(in: repo).compactMap { wanted[$0.lowercased()] }
            guard !bundles.isEmpty else { continue }
            for (locale, field) in keywordLines(text) {
                let terms = KeywordField.terms(in: field)
                for project in bundles { result[key(project: project, locale: locale)] = terms }
            }
        }
        return result
    }

    /// 레포 맨 위와 한 단계 아래의 Xcode 프로젝트 · project.yml 에 적힌 번들 id.
    private static func bundleIDs(in repo: URL) -> Set<String> {
        let fm = FileManager.default
        var files: [URL] = []
        let levels = [repo] + ((try? fm.contentsOfDirectory(at: repo, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { !$0.pathExtension.hasSuffix("proj") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? [])
        for dir in levels {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            files += items.filter { $0.pathExtension == "xcodeproj" }.map { $0.appendingPathComponent("project.pbxproj") }
            files += items.filter { $0.lastPathComponent == "project.yml" }
        }
        var ids = Set<String>()
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for match in text.matches(of: #/PRODUCT_BUNDLE_IDENTIFIER\s*[=:]\s*"?([A-Za-z0-9.\-]+)"?/#) {
                ids.insert(String(match.1))
            }
        }
        return ids
    }

    /// `## <로케일>` 절마다 `### 키워드` 아래 첫 줄. 절 제목은 `ko` 도 `한국어 (ko)` 도 쓰여서
    /// 괄호 안의 코드가 있으면 그것을 쓴다. `en` 처럼 지역 없이 쓴 것은 `localeAliases` 로 넓힌다.
    static func keywordLines(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var locale: String?
        var inKeywords = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                locale = code(of: String(line.dropFirst(3)))
                inKeywords = false
            } else if line.hasPrefix("#") {
                inKeywords = line.hasPrefix("### ") && (line.contains("키워드") || line.lowercased().contains("keyword"))
            } else if inKeywords, let locale, !line.isEmpty, !line.hasPrefix("```") {
                for alias in localeAliases(locale) where result[alias] == nil { result[alias] = line }
                inKeywords = false
            }
        }
        return result
    }

    private static func code(of heading: String) -> String {
        if let open = heading.lastIndex(of: "("), let close = heading.lastIndex(of: ")"), open < close {
            return String(heading[heading.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        }
        return heading.trimmingCharacters(in: .whitespaces)
    }

    /// DeployBar 가 지역 없는 코드를 받아 주는 스토어 로케일. 지역을 적은 절이 따로 있으면 그쪽이 먼저다
    /// (`keywordLines` 는 먼저 채운 값을 두지 않고, 정확한 코드는 늘 자기 자신으로도 채운다).
    private static func localeAliases(_ locale: String) -> [String] {
        let regional = ["en": "en-US", "es": "es-MX", "fr": "fr-FR", "de": "de-DE", "nl": "nl-NL", "pt": "pt-BR"]
        return [locale] + (regional[locale].map { [$0] } ?? [])
    }
}

extension KeywordStore {

    private static let repoBookmarkKey = "keywords.repoFolderBookmark"

    /// 레포에 적힌 이 칸의 말. 레포를 못 읽었거나 그 로케일 줄이 없으면 nil.
    func repoTerms(project: String, locale: String) -> [String]? {
        repoKeywords[RepoKeywords.key(project: project, locale: locale)]
    }

    /// 앱을 켤 때 — 남겨 둔 허락으로 폴더를 열고 읽는다. 앱으로 돌아올 때마다 다시 읽는다
    /// (Claude 가 레포에서 키워드를 고쳐 커밋하는 동안 허브는 켜져 있다).
    func startRepoKeywords() {
        #if os(macOS)
        restoreRepoFolder()
        reloadRepoKeywords()
        repoActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadRepoKeywords() }
        }
        #endif
    }

    func reloadRepoKeywords() {
        guard let folder = repoFolder else { return }
        let projects = Array(Set(fieldLog.keys.compactMap { $0.split(separator: "|").first.map(String.init) }))
        Task.detached(priority: .utility) {
            let found = RepoKeywords.scan(folder, projects: projects)
            let tests = DeviceTestReport.load(from: folder)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.repoKeywords != found { self.repoKeywords = found }
                if self.deviceTests != tests { self.deviceTests = tests }
            }
        }
    }

    /// `workspace/Auto` 폴더를 고르게 한다. 고른 허락은 북마크로 남는다.
    func chooseRepoFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 읽기"
        panel.message = "앱 레포들이 들어 있는 workspace/Auto 폴더를 고르세요. 각 레포의 APPSTORE.md 키워드 줄만 읽습니다."
        // 샌드박스 안의 홈은 컨테이너라, 진짜 홈을 따로 구한다.
        if let pw = getpwuid(getuid()) {
            let home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            panel.directoryURL = home.appendingPathComponent("Documents/workspace/Auto")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.repoBookmarkKey)
            restoreRepoFolder()
            reloadRepoKeywords()
        } catch {
            print("❌ [KeywordStore.chooseRepoFolder] \(error)")
        }
        #endif
    }

    private func restoreRepoFolder() {
        #if os(macOS)
        guard let data = UserDefaults.standard.data(forKey: Self.repoBookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            print("⚠️ [KeywordStore.restoreRepoFolder] 남겨 둔 폴더 허락을 열지 못했습니다")
            return
        }
        repoFolder?.stopAccessingSecurityScopedResource()
        repoFolder = url
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.repoBookmarkKey)
        }
        #endif
    }
}

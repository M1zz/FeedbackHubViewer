//
//  PortfolioStore.swift
//  FeedbackHubViewer
//
//  app-portfolio 의 앱 JSON 을 읽는다 — 서비스 숙성도의 홍보 칸과 사람이 적어 둔 홍보 기록,
//  가격 · 수익 모델, 그리고 scripts/paywalls.json 의 앱별 페이월.
//
//  맥에서 `workspace/code` 폴더를 골라 두었으면(설계 칸이 쓰는 것) 그 안의 app-portfolio 를 바로
//  읽는다 — 아직 푸시하지 않은 재측정도 보인다. 아니면(아이폰도) 공개 GitHub 의 main 을 읽는다.
//  받은 것은 파일로 남겨, 다음 실행은 네트워크 없이 먼저 그린다.
//

import Foundation

@MainActor
final class PortfolioStore: ObservableObject {
    static let shared = PortfolioStore()

    enum Source: String, Codable {
        case local = "이 맥의 app-portfolio"
        case github = "GitHub app-portfolio(main)"
    }

    private struct Snapshot: Codable {
        var files: [String: Data]
        /// scripts/paywalls.json. 옛 캐시에는 없다.
        var paywalls: Data?
        /// scripts/showcase-content.json — 앱마다 문제 · 페르소나 · 장면 · 해결.
        var showcase: Data?
        var source: Source
        var loadedAt: Date
    }

    private struct PaywallFile: Decodable {
        let apps: [String: PaywallInfo]
    }

    private struct ShowcaseFile: Decodable {
        let apps: [String: Showcase]
    }

    /// 공개 사이트에 쓰는 앱 소개 — 누구의 어떤 순간을 푸는 앱인가.
    struct Showcase: Decodable {
        let tagline: String?
        let problem: String?
        let stakeholders: String?
        let persona: String?
        let context: String?
        let solution: String?
        let hook: String?
        let highlight: String?
    }

    /// 번들 ID(소문자) → 앱.
    @Published private(set) var apps: [String: PortfolioApp] = [:]
    /// 번들 ID(소문자) → 앱 JSON 파일 이름(확장자 없이). paywalls.json 의 키가 이것이다.
    private var slugs: [String: String] = [:]
    /// 파일 이름 → 페이월.
    @Published private(set) var paywalls: [String: PaywallInfo] = [:]
    /// 파일 이름 → 앱 소개.
    @Published private(set) var showcases: [String: Showcase] = [:]
    @Published private(set) var source: Source?
    @Published private(set) var loadedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var problem: String?

    private static let cacheName = "portfolio-apps"
    private static let appsPath = "app-portfolio/projects/PortfolioCEO/PortfolioCEO/Data/apps"
    private static let paywallsPath = "app-portfolio/scripts/paywalls.json"
    private static let showcasePath = "app-portfolio/scripts/showcase-content.json"
    private static let showcaseURL = URL(string:
        "https://raw.githubusercontent.com/M1zz/app-portfolio/main/scripts/showcase-content.json")!
    private static let paywallsURL = URL(string:
        "https://raw.githubusercontent.com/M1zz/app-portfolio/main/scripts/paywalls.json")!
    private static let listingURL = URL(string:
        "https://api.github.com/repos/M1zz/app-portfolio/contents/projects/PortfolioCEO/PortfolioCEO/Data/apps")!
    /// GitHub 은 이만큼 지나야 다시 묻는다(이름 없는 요청은 시간당 60번까지).
    private static let refreshInterval: TimeInterval = 6 * 60 * 60

    private init() {
        if let snapshot = CacheFile.read(Snapshot.self, at: CacheFile.url(Self.cacheName)) {
            apply(snapshot)
        }
    }

    /// 허브 프로젝트 키로 — 대소문자를 가리지 않는다(com.ysoup.… / com.Ysoup.…).
    func app(for project: String) -> PortfolioApp? {
        apps[project.lowercased()]
    }

    func paywall(for project: String) -> PaywallInfo? {
        slugs[project.lowercased()].flatMap { paywalls[$0] }
    }

    func showcase(for project: String) -> Showcase? {
        slugs[project.lowercased()].flatMap { showcases[$0] }
    }

    /// 묵었거나 `force` 면 다시 읽는다. `workspace` 는 맥에서 고른 code 폴더.
    func load(workspace: URL?, force: Bool = false) async {
        guard !isLoading else { return }
        // 페이월이 비어 있으면(그것을 읽기 전의 캐시) 묵지 않았어도 다시 읽는다.
        if !force, !paywalls.isEmpty, !showcases.isEmpty, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.refreshInterval,
           source == .local || workspace == nil { return }
        isLoading = true
        problem = nil
        defer { isLoading = false }

        if let workspace, let files = Self.readLocal(workspace) {
            let paywalls = try? Data(contentsOf: workspace.appendingPathComponent(Self.paywallsPath))
            let showcase = try? Data(contentsOf: workspace.appendingPathComponent(Self.showcasePath))
            commit(Snapshot(files: files, paywalls: paywalls, showcase: showcase, source: .local, loadedAt: Date()))
            return
        }
        do {
            let files = try await Self.readGitHub()
            let paywalls = try? await URLSession.shared.data(from: Self.paywallsURL).0
            let showcase = try? await URLSession.shared.data(from: Self.showcaseURL).0
            commit(Snapshot(files: files, paywalls: paywalls, showcase: showcase, source: .github, loadedAt: Date()))
        } catch {
            problem = "app-portfolio 를 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func commit(_ snapshot: Snapshot) {
        apply(snapshot)
        CacheFile.write(snapshot, to: CacheFile.url(Self.cacheName))
    }

    private func apply(_ snapshot: Snapshot) {
        var next: [String: PortfolioApp] = [:]
        var nextSlugs: [String: String] = [:]
        let decoder = JSONDecoder()
        for (name, data) in snapshot.files {
            guard let app = try? decoder.decode(PortfolioApp.self, from: data),
                  let bundleId = app.bundleId?.lowercased(), !bundleId.isEmpty else { continue }
            next[bundleId] = app
            nextSlugs[bundleId] = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
        }
        apps = next
        slugs = nextSlugs
        paywalls = snapshot.paywalls.flatMap { try? decoder.decode(PaywallFile.self, from: $0).apps } ?? [:]
        showcases = snapshot.showcase.flatMap { try? decoder.decode(ShowcaseFile.self, from: $0).apps } ?? [:]
        source = snapshot.source
        loadedAt = snapshot.loadedAt
    }

    private static func readLocal(_ workspace: URL) -> [String: Data]? {
        let folder = workspace.appendingPathComponent(appsPath, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        var files: [String: Data] = [:]
        for name in names where name.hasSuffix(".json") {
            files[name] = try? Data(contentsOf: folder.appendingPathComponent(name))
        }
        return files.isEmpty ? nil : files
    }

    private struct Entry: Decodable {
        let name: String
        let download_url: String?
    }

    private static func readGitHub() async throws -> [String: Data] {
        var request = URLRequest(url: listingURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub HTTP \(http.statusCode)"])
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
            .filter { $0.name.hasSuffix(".json") }
        return try await withThrowingTaskGroup(of: (String, Data?).self) { group in
            for entry in entries {
                guard let link = entry.download_url, let url = URL(string: link) else { continue }
                group.addTask { (entry.name, try? await URLSession.shared.data(from: url).0) }
            }
            var files: [String: Data] = [:]
            for try await (name, data) in group { files[name] = data }
            return files
        }
    }
}

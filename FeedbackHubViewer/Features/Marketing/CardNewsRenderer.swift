//
//  CardNewsRenderer.swift
//  FeedbackHubViewer
//
//  카드뉴스의 장들을 그대로 올릴 수 있는 그림(1080×1350, 인스타그램 세로)으로.
//
//  글만 받아 두면 결국 디자인 툴을 열어 한 장씩 옮겨 적어야 한다. 그 손을 덜려고 이 앱이 직접
//  그린다 — 앱 아이콘 · 이름 · 장 번호가 들어간 단정한 틀 하나. 더 꾸미고 싶으면 이 그림을
//  바탕으로 고치면 된다.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 카드뉴스 색 묶음.
struct CardNewsTheme: Identifiable {
    let id: Int
    let name: String
    let background: [Color]
    let ink: Color
    let accent: Color

    static let all: [CardNewsTheme] = [
        .init(id: 0, name: "밤하늘", background: [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.18, green: 0.14, blue: 0.38)],
              ink: .white, accent: Color(red: 1.0, green: 0.78, blue: 0.35)),
        .init(id: 1, name: "종이", background: [Color(red: 0.98, green: 0.96, blue: 0.91), Color(red: 0.94, green: 0.90, blue: 0.82)],
              ink: Color(red: 0.13, green: 0.12, blue: 0.11), accent: Color(red: 0.86, green: 0.30, blue: 0.20)),
        .init(id: 2, name: "민트", background: [Color(red: 0.84, green: 0.96, blue: 0.92), Color(red: 0.62, green: 0.88, blue: 0.82)],
              ink: Color(red: 0.05, green: 0.20, blue: 0.18), accent: Color(red: 0.05, green: 0.45, blue: 0.40)),
        .init(id: 3, name: "코랄", background: [Color(red: 1.0, green: 0.55, blue: 0.45), Color(red: 0.93, green: 0.33, blue: 0.40)],
              ink: .white, accent: Color(red: 1.0, green: 0.95, blue: 0.80)),
    ]

    static func of(_ item: MarketingItem) -> CardNewsTheme { all[min(max(item.theme ?? 0, 0), all.count - 1)] }
}

/// 한 장. 화면의 미리보기와 내보내는 그림이 같은 뷰다 — 미리보기는 줄여서 보일 뿐.
struct CardNewsSlideView: View {
    let slide: MarketingItem.Slide
    let index: Int
    let total: Int
    let appName: String
    let theme: CardNewsTheme
    var icon: CGImage? = nil
    /// 영어 카드 — 마지막 장의 검색 안내도 영어로.
    var english = false

    static let size = CGSize(width: 1080, height: 1350)

    /// 한글은 글자 사이 어디서나 줄이 바뀌어 "30초" 가 "30 / 초" 로 갈린다. 낱말 안의 글자
    /// 사이에 줄바꿈 금지 문자(U+2060)를 넣어 띄어쓰기에서만 바뀌게 한다.
    static func keepingWords(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.split(separator: " ", omittingEmptySubsequences: false)
                .map { $0.map(String.init).joined(separator: "\u{2060}") }
                .joined(separator: " ")
        }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                if let icon {
                    Image(decorative: icon, scale: 1)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(appName)
                    .font(.system(size: 34, weight: .semibold))
                Spacer()
                Text("\(index + 1) / \(total)")
                    .font(.system(size: 30, weight: .medium).monospacedDigit())
                    .opacity(0.7)
            }
            Spacer(minLength: 40)
            Rectangle()
                .fill(theme.accent)
                .frame(width: 96, height: 10)
                .padding(.bottom, 44)
            Text(Self.keepingWords(slide.headline))
                .font(.system(size: index == 0 ? 96 : 80, weight: .heavy))
                .lineSpacing(8)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
            if !slide.text.isEmpty {
                Text(Self.keepingWords(slide.text))
                    .font(.system(size: 44, weight: .regular))
                    .lineSpacing(14)
                    .minimumScaleFactor(0.5)
                    .opacity(0.9)
                    .padding(.top, 40)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 40)
            if index == total - 1 {
                Text(english ? "Search \"\(appName)\" on the App Store" : "App Store 에서 \"\(appName)\" 검색")
                    .font(.system(size: 36, weight: .bold))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 18)
                    .background(theme.accent.opacity(0.9), in: Capsule())
                    .foregroundStyle(theme.background.first ?? .black)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(90)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// 장들을 PNG 파일로. 임시 폴더에 쓰고 그 주소들을 돌려준다 — 공유 · 폴더 저장이 그걸 쓴다.
@MainActor
enum CardNewsExport {
    static func render(_ item: MarketingItem, appName: String, icon: CGImage?, english: Bool = false) async -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cardnews-\(item.id.uuidString)-\(english ? "en" : "ko")", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let theme = CardNewsTheme.of(item)
        var urls: [URL] = []
        for (index, slide) in item.slides.enumerated() {
            let renderer = ImageRenderer(content: CardNewsSlideView(slide: slide.localized(english: english), index: index,
                                                                    total: item.slides.count, appName: appName,
                                                                    theme: theme, icon: icon, english: english))
            renderer.scale = 1
            guard let image = renderer.cgImage else { continue }
            let url = folder.appendingPathComponent(String(format: "%@-%02d.png", english ? "en" : "ko", index + 1))
            if write(image, to: url) { urls.append(url) }
        }
        return urls
    }

    private static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

}

/// 앱 아이콘 주소. 키워드 칸이 이어 둔 스토어 앱이 있으면 그 아이콘, 없으면
/// 번들 ID 로 App Store 에 한 번 물어 본다 — 맥 전용 앱은 키워드 칸의 검색(iOS 앱만)에 안
/// 잡혀서 아이콘이 비었다.
@MainActor
final class StoreIcons: ObservableObject {
    static let shared = StoreIcons()

    @Published private var found: [String: URL] = [:]
    private var asked: Set<String> = []
    private var images: [URL: CGImage] = [:]

    func url(for project: String, keywords: KeywordStore) -> URL? {
        keywords.storeApp(for: project)?.iconURL ?? found[project]
    }

    /// 모르는 앱의 아이콘 주소를 묻는다. 한 번 물은 앱은 이번 실행에서 다시 묻지 않는다.
    func resolve(_ projects: [String], keywords: KeywordStore) async {
        let missing = Set(projects).filter { url(for: $0, keywords: keywords) == nil && !asked.contains($0) }
        guard !missing.isEmpty else { return }
        asked.formUnion(missing)
        for country in ["kr", "us"] {
            let left = missing.filter { found[$0] == nil }
            guard !left.isEmpty else { break }
            var components = URLComponents(string: "https://itunes.apple.com/lookup")!
            components.queryItems = [URLQueryItem(name: "bundleId", value: left.sorted().joined(separator: ",")),
                                     URLQueryItem(name: "country", value: country)]
            guard let url = components.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = object["results"] as? [[String: Any]] else { continue }
            for result in results {
                guard let bundleId = result["bundleId"] as? String,
                      let icon = (result["artworkUrl512"] ?? result["artworkUrl100"]) as? String,
                      let iconURL = URL(string: icon) else { continue }
                // 허브의 키와 대소문자가 다를 수 있다(com.ysoup.… / com.Ysoup.…).
                if let key = left.first(where: { $0.caseInsensitiveCompare(bundleId) == .orderedSame }) {
                    found[key] = iconURL
                }
            }
        }
    }

    /// 카드뉴스에 넣을 아이콘 그림.
    func image(for project: String, keywords: KeywordStore) async -> CGImage? {
        await resolve([project], keywords: keywords)
        guard let url = url(for: project, keywords: keywords) else { return nil }
        if let cached = images[url] { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[url] = image
        return image
    }
}

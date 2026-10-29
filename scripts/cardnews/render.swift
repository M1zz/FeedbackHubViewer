import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct MarketingItem {
    struct Slide: Decodable, Identifiable, Hashable {
        var id = UUID()
        var headline: String
        var text: String
        var headlineEn: String? = nil
        var textEn: String? = nil
        var screen: String? = nil
        var anchor: String? = nil
        enum CodingKeys: String, CodingKey { case headline, text, headlineEn, textEn, screen, anchor }
        func localized(english: Bool) -> Slide { self }
    }
    var theme: Int?
}
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
            if let screen = slide.screen.flatMap({ NSImage(contentsOfFile: $0) }) {
                Spacer(minLength: 0).frame(height: 56)
                Rectangle().fill(theme.accent).frame(width: 80, height: 8).padding(.bottom, 30)
                Text(Self.keepingWords(slide.headline))
                    .font(.system(size: 66, weight: .heavy))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                if !slide.text.isEmpty {
                    Text(Self.keepingWords(slide.text))
                        .font(.system(size: 36))
                        .lineSpacing(10)
                        .opacity(0.9)
                        .padding(.top, 22)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0).frame(height: 44)
                GeometryReader { geo in
                    let width: CGFloat = 760
                    Image(nsImage: screen)
                        .resizable()
                        .frame(width: width, height: width * screen.size.height / screen.size.width)
                        .frame(width: width, height: geo.size.height, alignment: slide.anchor == "top" ? .top : .bottom)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(theme.ink.opacity(0.25), lineWidth: 6))
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, -40)
            } else {
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

struct Entry: Decodable { let id: String; let title: String; let theme: Int?; let slides: [MarketingItem.Slide]? }

@MainActor func run() async {
    let args = CommandLine.arguments
    let e = try! JSONDecoder().decode(Entry.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let iconData = try! Data(contentsOf: URL(string: args[3])!)
    let src = CGImageSourceCreateWithData(iconData as CFData, nil)!
    let icon = CGImageSourceCreateImageAtIndex(src, 0, nil)
    let item = MarketingItem(theme: e.theme)
    let slides = e.slides ?? []
    for (i, s) in slides.enumerated() {
        let r = ImageRenderer(content: CardNewsSlideView(slide: s, index: i, total: slides.count, appName: args[4],
                                                         theme: CardNewsTheme.of(item), icon: icon))
        r.scale = 1
        let url = URL(fileURLWithPath: args[5]).appendingPathComponent(String(format: "ko-%02d.png", i + 1))
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, r.cgImage!, nil)
        CGImageDestinationFinalize(d)
        print(url.path)
    }
}
@main struct Main { static func main() async { await run() } }

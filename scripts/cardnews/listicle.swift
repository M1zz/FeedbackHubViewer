// 목록형 카드뉴스 (앱 여러 개 묶음). 사용법은 README.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// 목록형 카드뉴스: 표지(아이콘 한 줄 + 아래 큰 글씨) → 앱마다 한 장(실제 화면 + 아래 글씨) → 마지막 장(검색 안내).
struct App: Decodable { let name: String; let icon: String; let screen: String; let headline: String; let text: String; var anchor: String? }
struct Deck: Decodable { let cover: String; let apps: [App]; let outro: String }

let W: CGFloat = 1080, H: CGFloat = 1350
let bg = Color(red: 0.07, green: 0.07, blue: 0.075)

func words(_ t: String) -> String {
    t.components(separatedBy: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: false)
        .map { $0.map(String.init).joined(separator: "\u{2060}") }.joined(separator: " ") }.joined(separator: "\n")
}
func img(_ p: String) -> NSImage { NSImage(contentsOfFile: p)! }

struct Dots: View {
    let index: Int, total: Int
    var body: some View {
        HStack(spacing: 14) { ForEach(0..<total, id: \.self) { i in Circle().fill(.white.opacity(i == index ? 1 : 0.35)).frame(width: 14, height: 14) } }
            .frame(maxWidth: .infinity)
    }
}

struct Cover: View {
    let deck: Deck, total: Int
    var body: some View {
        ZStack(alignment: .topLeading) {
            bg
            HStack(spacing: 44) {
                ForEach(deck.apps.indices, id: \.self) { i in
                    Image(nsImage: img(deck.apps[i].icon)).resizable()
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 58, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                }
            }
            .fixedSize().frame(width: W, height: 250).offset(y: 430)  // 가운데 두고 양옆이 잘려 더 있어 보이게
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text(words(deck.cover)).font(.system(size: 92, weight: .heavy)).lineSpacing(10).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 90)
                Dots(index: 0, total: total)
            }.padding(.horizontal, 90).padding(.bottom, 56)
        }.frame(width: W, height: H).clipped()
    }
}

struct AppSlide: View {
    let app: App, index: Int, total: Int
    var body: some View {
        let shot = img(app.screen)
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let w: CGFloat = 600
                Image(nsImage: shot).resizable()
                    .frame(width: w, height: w * shot.size.height / shot.size.width)
                    .frame(width: w, height: geo.size.height, alignment: app.anchor == "bottom" ? .bottom : .top)
                    .clipped()
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 64, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 64, style: .continuous))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 64, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 64, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 5))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 700).padding(.top, 70)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 2)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 20) {
                    Image(nsImage: img(app.icon)).resizable().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text(String(format: "%02d", index)).font(.system(size: 34, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    Text(app.name).font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                }
                Text(words(app.headline)).font(.system(size: 70, weight: .heavy)).lineSpacing(6).foregroundStyle(.white)
                    .padding(.top, 34).fixedSize(horizontal: false, vertical: true)
                Text(words(app.text)).font(.system(size: 36)).lineSpacing(10).foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 20).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                Dots(index: index, total: total)
            }.padding(.horizontal, 90).padding(.top, 44).padding(.bottom, 56)
        }.frame(width: W, height: H).background(bg)
    }
}

struct Outro: View {
    let deck: Deck, total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(words(deck.outro)).font(.system(size: 72, weight: .heavy)).lineSpacing(8).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 40)
            Spacer().frame(height: 70)
            VStack(alignment: .leading, spacing: 30) {
                ForEach(deck.apps.indices, id: \.self) { i in
                    HStack(spacing: 28) {
                        Image(nsImage: img(deck.apps[i].icon)).resizable().frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        Text(deck.apps[i].name).font(.system(size: 46, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            Spacer()
            Text("App Store 에서 이름으로 검색").font(.system(size: 36, weight: .bold))
                .padding(.horizontal, 30).padding(.vertical, 18)
                .background(.white, in: Capsule()).foregroundStyle(bg)
            Spacer().frame(height: 60)
            Dots(index: total - 1, total: total)
        }.padding(.horizontal, 90).padding(.top, 90).padding(.bottom, 56)
            .frame(width: W, height: H, alignment: .topLeading).background(bg)
    }
}

@MainActor func save(_ v: some View, _ path: String) {
    let r = ImageRenderer(content: v); r.scale = 1
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, r.cgImage!, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    CGImageDestinationFinalize(d); print(path)
}

@main struct Main {
    @MainActor static func main() {
        let a = CommandLine.arguments
        let deck = try! JSONDecoder().decode(Deck.self, from: Data(contentsOf: URL(fileURLWithPath: a[1])))
        let total = deck.apps.count + 2
        save(Cover(deck: deck, total: total), "\(a[2])/01.jpg")
        for (i, app) in deck.apps.enumerated() { save(AppSlide(app: app, index: i + 1, total: total), String(format: "%@/%02d.jpg", a[2], i + 2)) }
        save(Outro(deck: deck, total: total), String(format: "%@/%02d.jpg", a[2], total))
    }
}

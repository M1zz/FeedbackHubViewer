// 기능 소개형 카드뉴스 (앱 하나, 기능 여러 장). 사용법은 README.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// 표지(색 바탕 + 큰 글씨 + 전후 그림) → 기능마다 한 장(번호 · 제목 · 한 줄 · 아래로 잘린 폰 화면) → 마지막 장(아이콘 · 요점 · 검색 안내).
struct Feature: Decodable { let label: String; let headline: String; let text: String; var screen: String?; var top: Double?; var before: String?; var after: String? }
struct Deck: Decodable {
    let name: String; let icon: String; let accent: String
    let kicker: String; let cover: String; let coverScreens: [String]
    let features: [Feature]
    let outro: String; let points: [String]
    /// 마지막 장의 검색 안내. 없으면 한국어("App Store 에서 “이름” 검색"). 영어 덱은 "Search “Clip Keyboard” on the App Store".
    var search: String?
}

let W: CGFloat = 1080, H: CGFloat = 1350
let paper = Color(red: 0.965, green: 0.957, blue: 0.937)
let ink = Color(red: 0.07, green: 0.07, blue: 0.08)
let mark = Color(red: 0.18, green: 0.80, blue: 0.44)  // 아이콘의 초록 모서리

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16)!
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
func words(_ t: String) -> String {  // 한국어가 낱말 가운데서 끊기지 않게
    t.components(separatedBy: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: false)
        .map { $0.map(String.init).joined(separator: "\u{2060}") }.joined(separator: " ") }.joined(separator: "\n")
}
func img(_ p: String) -> NSImage { NSImage(contentsOfFile: p)! }

/// 아이콘의 스캔 모서리 네 개. 반듯하게 잡혔다는 표시.
struct Corners: View {
    var color = mark, len: CGFloat = 70, width: CGFloat = 12
    var body: some View {
        GeometryReader { g in
            Path { p in
                let w = g.size.width, h = g.size.height
                for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] {
                    p.move(to: CGPoint(x: x, y: y + dy * len)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * len, y: y))
                }
            }.stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}

struct TopBar: View {
    let deck: Deck, index: Int, total: Int, light: Bool
    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: img(deck.icon)).resizable().frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(deck.name).font(.system(size: 32, weight: .bold))
            Spacer()
            Text(String(format: "%02d / %02d", index + 1, total)).font(.system(size: 28, weight: .semibold).monospacedDigit()).opacity(0.55)
        }.foregroundStyle(light ? .white : ink)
    }
}

/// 전후 비교: 비스듬히 찍힌 사진 위에 반듯해진 장표.
struct BeforeAfter: View {
    let before: String, after: String
    var body: some View {
        let a = img(after)
        ZStack(alignment: .topLeading) {
            Image(nsImage: img(before)).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 600, height: 450).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .topLeading) { Tag(text: "찍은 그대로", dark: true).padding(22) }
                .rotationEffect(.degrees(-5)).shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            Image(nsImage: a).resizable().frame(width: 640, height: 640 * a.size.height / a.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 30, y: 16)
                .overlay { Corners().padding(-30) }
                .overlay(alignment: .bottomTrailing) { Tag(text: "장표스냅", dark: false).padding(22) }
                .offset(x: 300, y: 300)
        }.frame(width: 940, height: 640, alignment: .topLeading)
    }
}
struct Tag: View {
    let text: String, dark: Bool
    var body: some View {
        Text(text).font(.system(size: 26, weight: .bold)).padding(.horizontal, 20).padding(.vertical, 10)
            .background(dark ? Color.black.opacity(0.72) : mark, in: Capsule()).foregroundStyle(.white)
    }
}

struct Cover: View {
    let deck: Deck, total: Int
    var body: some View {
        let accent = Color(hex: deck.accent)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: 0, total: total, light: true)
            Text(deck.kicker).font(.system(size: 34, weight: .bold)).foregroundStyle(.white.opacity(0.75)).padding(.top, 80)
            Text(words(deck.cover)).font(.system(size: 104, weight: .black)).tracking(-3).lineSpacing(4).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            Spacer()
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading)
            .background(alignment: .bottom) {  // 폰 세 대를 부채꼴로, 아래는 잘려 나가게
                ZStack {
                    ForEach(deck.coverScreens.indices, id: \.self) { i in
                        let k = Double(i) - Double(deck.coverScreens.count - 1) / 2
                        Phone(screen: deck.coverScreens[i], width: 420).rotationEffect(.degrees(k * 9), anchor: .bottom)
                            .offset(x: k * 290, y: abs(k) * 50).zIndex(-abs(k))
                    }
                }.frame(width: W, height: 640, alignment: .top).offset(y: 40)
            }
            .background(accent).clipped()
    }
}

struct FeatureSlide: View {
    let deck: Deck, f: Feature, n: Int, index: Int, total: Int
    var body: some View {
        let accent = Color(hex: deck.accent)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: index, total: total, light: false)
            HStack(spacing: 16) {
                Text(String(format: "%02d", n)).font(.system(size: 30, weight: .black).monospacedDigit())
                    .foregroundStyle(.white).frame(width: 64, height: 64).background(accent, in: Circle())
                Text(f.label).font(.system(size: 34, weight: .bold)).foregroundStyle(accent)
            }.padding(.top, 70)
            Text(words(f.headline)).font(.system(size: 84, weight: .black)).tracking(-2).lineSpacing(2).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 26)
            Text(words(f.text)).font(.system(size: 34, weight: .medium)).lineSpacing(10).foregroundStyle(ink.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            Spacer(minLength: 50)
            if let s = f.screen {
                Phone(screen: s, top: f.top ?? 0).frame(maxWidth: .infinity)
            } else if let b = f.before, let a = f.after {
                BeforeAfter(before: b, after: a).frame(maxWidth: .infinity).padding(.bottom, 70)
            }
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading).background(paper).clipped()
    }
}

/// 폰 화면 위쪽만, 아래는 카드 밖으로 잘려 나가게.
struct Phone: View {
    let screen: String; var top: Double = 0; var width: CGFloat = 600
    var body: some View {
        let s = img(screen), w = width, h = w * s.size.height / s.size.width
        Image(nsImage: s).resizable().frame(width: w, height: h)
            .offset(y: -top * h).frame(width: w, height: h, alignment: .top).clipped()  // top: 화면의 몇 분의 몇부터 보일지
            .clipShape(RoundedRectangle(cornerRadius: w * 0.117, style: .continuous))
            .padding(w * 0.027).background(ink, in: RoundedRectangle(cornerRadius: w * 0.143, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 40, y: 20)
            .frame(height: 640, alignment: .top).offset(y: 30)
    }
}

struct Outro: View {
    let deck: Deck, total: Int
    var body: some View {
        let accent = Color(hex: deck.accent)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: total - 1, total: total, light: false)
            Image(nsImage: img(deck.icon)).resizable().frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                .shadow(color: accent.opacity(0.35), radius: 30, y: 14).padding(.top, 90)
            Text(words(deck.outro)).font(.system(size: 84, weight: .black)).tracking(-2).lineSpacing(2).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 56)
            VStack(alignment: .leading, spacing: 26) {
                ForEach(deck.points, id: \.self) { p in
                    HStack(spacing: 20) {
                        Image(systemName: "checkmark").font(.system(size: 26, weight: .black)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(mark, in: Circle())
                        Text(p).font(.system(size: 38, weight: .semibold)).foregroundStyle(ink.opacity(0.8))
                    }
                }
            }.padding(.top, 56)
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .bold))
                Text(deck.search ?? "App Store 에서 \u{201C}\(deck.name)\u{201D} 검색").font(.system(size: 38, weight: .bold))
            }.foregroundStyle(.white).padding(.horizontal, 44).padding(.vertical, 30)
                .frame(maxWidth: .infinity).background(accent, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            Spacer().frame(height: 70)
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading).background(paper)
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
        let total = deck.features.count + 2
        save(Cover(deck: deck, total: total), "\(a[2])/01.jpg")
        for (i, f) in deck.features.enumerated() {
            save(FeatureSlide(deck: deck, f: f, n: i + 1, index: i + 1, total: total), String(format: "%@/%02d.jpg", a[2], i + 2))
        }
        save(Outro(deck: deck, total: total), String(format: "%@/%02d.jpg", a[2], total))
    }
}

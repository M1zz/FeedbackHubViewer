// 기능 소개형 카드뉴스 — 빛번짐형 (앱 하나, 기능 여러 장). 사용법은 README.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// 짙은 바탕 위에 앱 색 두 가지가 번지고, 폰은 비스듬히 떠 있다. 폰 위에는 그 기능을 한마디로 적은 칩이 떠 있다.
// 표지(큰 질문 + 폰 한 대) → 기능마다 한 장(칩 라벨 · 큰 제목 · 한두 줄 · 폰 + 말풍선 칩) → 마지막 장(아이콘 · 한마디 · 요점 · 검색 안내).
struct Callout: Decodable { let symbol: String; let text: String; var x: Double = 0.5; var y: Double = 0.4 }
struct Feature: Decodable { let label: String; let headline: String; let text: String; let screen: String; var top: Double = 0; var callout: Callout? }
struct Deck: Decodable {
    let name: String; let icon: String; let accent: String; let accent2: String
    let kicker: String; let cover: String; let coverScreen: String; var coverTop: Double = 0; var coverCallout: Callout?
    let features: [Feature]
    let outro: String; let points: [String]
}

let W: CGFloat = 1080, H: CGFloat = 1350
let night = Color(red: 0.043, green: 0.055, blue: 0.11)
let dim = Color(red: 0.66, green: 0.70, blue: 0.80)

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

/// 바탕: 밤색 위에 두 색이 모서리에서 번진다.
struct Glow: View {
    let a: Color, b: Color
    var body: some View {
        ZStack {
            night
            Circle().fill(a).frame(width: 1100, height: 1100).blur(radius: 220).offset(x: -420, y: -560).opacity(0.75)
            Circle().fill(b).frame(width: 1000, height: 1000).blur(radius: 220).offset(x: 480, y: 560).opacity(0.7)
        }.frame(width: W, height: H).clipped()
    }
}

struct TopBar: View {
    let deck: Deck, index: Int, total: Int
    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: img(deck.icon)).resizable().frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(deck.name).font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 10) {  // 쪽 표시는 점으로
                ForEach(0..<total, id: \.self) { i in
                    Capsule().fill(.white.opacity(i == index ? 1 : 0.28)).frame(width: i == index ? 34 : 12, height: 12)
                }
            }
        }
    }
}

/// 기능 이름 칩 — 앱 색 그라데이션.
struct Pill: View {
    let n: Int?, text: String, a: Color, b: Color
    var body: some View {
        HStack(spacing: 14) {
            if let n { Text(String(format: "%02d", n)).font(.system(size: 28, weight: .black).monospacedDigit()).opacity(0.8) }
            Text(text).font(.system(size: 30, weight: .bold))
        }.foregroundStyle(.white).padding(.horizontal, 28).padding(.vertical, 14)
            .background(LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing), in: Capsule())
    }
}

/// 폰 위에 떠 있는 말풍선 칩 — 흰 바탕, 아이콘 + 짧은 말.
struct Bubble: View {
    let c: Callout, tint: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: c.symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(tint)
            Text(c.text).font(.system(size: 32, weight: .bold)).foregroundStyle(night)
        }.padding(.horizontal, 30).padding(.vertical, 20)
            .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
    }
}

/// 비스듬히 떠 있는 폰. 유리 테두리, 아래는 카드 밖으로.
struct Phone: View {
    let screen: String; var top: Double = 0; var width: CGFloat = 640; var tilt: Double = -6; var glow: Color = .white
    var body: some View {
        let s = img(screen), w = width, h = w * s.size.height / s.size.width
        Image(nsImage: s).resizable().frame(width: w, height: h)
            .offset(y: -top * h).frame(width: w, height: h, alignment: .top).clipped()
            .clipShape(RoundedRectangle(cornerRadius: w * 0.117, style: .continuous))
            .padding(w * 0.022)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: w * 0.14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: w * 0.14, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 3))
            .shadow(color: glow.opacity(0.45), radius: 70, y: 10)
            .shadow(color: .black.opacity(0.5), radius: 40, y: 30)
            .rotationEffect(.degrees(tilt), anchor: .top)
    }
}

/// 폰 + 말풍선 칩을 한 덩어리로, 카드 아래로 잘려 나가게.
struct Stage: View {
    let screen: String, top: Double, callout: Callout?, tint: Color, glow: Color
    var height: CGFloat = 640, phoneWidth: CGFloat = 640, tilt: Double = -6
    var body: some View {
        ZStack(alignment: .topLeading) {
            Phone(screen: screen, top: top, width: phoneWidth, tilt: tilt, glow: glow)
                .frame(maxWidth: .infinity).offset(y: 40)
            if let c = callout {
                Bubble(c: c, tint: tint).rotationEffect(.degrees(tilt / 2))
                    .position(x: W * c.x - 80, y: height * c.y)
            }
        }.frame(width: W - 160, height: height, alignment: .top).clipped()
    }
}

struct Cover: View {
    let deck: Deck, total: Int
    var body: some View {
        let a = Color(hex: deck.accent), b = Color(hex: deck.accent2)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: 0, total: total)
            Text(deck.kicker).font(.system(size: 32, weight: .bold)).foregroundStyle(dim).padding(.top, 76)
            Text(words(deck.cover)).font(.system(size: 108, weight: .black)).tracking(-3).lineSpacing(2).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 20)
            Spacer(minLength: 40)
            Stage(screen: deck.coverScreen, top: deck.coverTop, callout: deck.coverCallout, tint: a, glow: b, height: 560, phoneWidth: 700, tilt: -8)
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading).background(Glow(a: a, b: b)).clipped()
    }
}

struct FeatureSlide: View {
    let deck: Deck, f: Feature, n: Int, index: Int, total: Int
    var body: some View {
        let a = Color(hex: deck.accent), b = Color(hex: deck.accent2)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: index, total: total)
            Pill(n: n, text: f.label, a: a, b: b).padding(.top, 70)
            Text(words(f.headline)).font(.system(size: 86, weight: .black)).tracking(-2).lineSpacing(2).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 30)
            Text(words(f.text)).font(.system(size: 34, weight: .medium)).lineSpacing(10).foregroundStyle(dim)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            Spacer(minLength: 40)
            Stage(screen: f.screen, top: f.top, callout: f.callout, tint: a, glow: index % 2 == 0 ? a : b)
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading).background(Glow(a: a, b: b)).clipped()
    }
}

struct Outro: View {
    let deck: Deck, total: Int
    var body: some View {
        let a = Color(hex: deck.accent), b = Color(hex: deck.accent2)
        VStack(alignment: .leading, spacing: 0) {
            TopBar(deck: deck, index: total - 1, total: total)
            Image(nsImage: img(deck.icon)).resizable().frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
                .shadow(color: a.opacity(0.6), radius: 50, y: 16).padding(.top, 90)
            Text(words(deck.outro)).font(.system(size: 86, weight: .black)).tracking(-2).lineSpacing(2).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 56)
            VStack(alignment: .leading, spacing: 24) {
                ForEach(deck.points, id: \.self) { p in
                    HStack(spacing: 20) {
                        Image(systemName: "checkmark").font(.system(size: 24, weight: .black)).foregroundStyle(night)
                            .frame(width: 48, height: 48).background(LinearGradient(colors: [a, b], startPoint: .top, endPoint: .bottom), in: Circle())
                        Text(p).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }.padding(.top, 56)
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .bold))
                Text("App Store 에서 \u{201C}\(deck.name)\u{201D} 검색").font(.system(size: 38, weight: .bold))
            }.foregroundStyle(night).padding(.horizontal, 44).padding(.vertical, 30)
                .frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            Spacer().frame(height: 70)
        }.padding(.horizontal, 80).padding(.top, 64)
            .frame(width: W, height: H, alignment: .topLeading).background(Glow(a: a, b: b)).clipped()
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

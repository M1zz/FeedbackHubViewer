//
//  SalesMapCard.swift
//  FeedbackHubViewer
//
//  어디서 얼마를 벌었나 — 최근 30일 수익금을 세계 지도 위의 원과 나라 순위로.
//
//  원의 **넓이**가 수익금(달러 환산)에 비례한다. 지름으로 비례시키면 두 배 번 나라가
//  네 배로 보인다. 금액은 판매 리포트의 개발자 수익금(Apple 수수료 · 세금 뺀 것)을
//  오늘 환율로 원화로 바꾼 것이라 어림값이고, 그래서 "≈" 를 붙인다(`ExchangeRates`).
//
//  환율이 아직 없으면 지도를 그리지 않는다. 통화가 다른 금액끼리는 크기를 견줄 수 없다.
//

import MapKit
import SwiftUI

struct SalesMapCard: View {
    let totals: AppStoreConnectStore.SalesWindow.Totals
    let rates: ExchangeRates?
    /// 카드 제목 — "이 앱" / "계정 전체".
    var title = "어디서 벌었나"

    @State private var showsAll = false

    /// 나라 한 줄.
    private struct Place: Identifiable {
        let code: String
        let purchases: Int
        let money: Money?
        /// 환율이 없을 때의 통화별 표시.
        let rawLabel: String
        var id: String { code }
        var usd: Double { money?.usd ?? 0 }
    }

    private var places: [Place] {
        totals.countries.map { code, place in
            let raw = place.proceeds.filter { $0.value != 0 }.sorted { $0.key < $1.key }
                .map { AppStoreConnect.formatMoney($0.value, currency: $0.key) }
                .joined(separator: " · ")
            return Place(code: code, purchases: place.purchases,
                         money: Money(place.proceeds, rates: rates), rawLabel: raw.isEmpty ? "—" : raw)
        }
        .sorted { ($0.usd, $0.purchases) > ($1.usd, $1.purchases) }
    }

    var body: some View {
        let places = self.places
        let total = totals.money(rates)

        Card(title: title, systemImage: "globe.asia.australia") {
            if places.isEmpty {
                Text("최근 \(AppStoreConnectStore.salesDays)일에 수익이 난 나라가 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                headline(total: total, countries: places.filter { $0.usd > 0 || $0.purchases > 0 }.count)
                if rates != nil {
                    map(places)
                }
                list(places)
                footnote(total)
            }
        }
    }

    // MARK: - Parts

    private func headline(total: Money?, countries: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let total {
                Text("≈ \(MoneyFormat.krw(total.krw))")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text("\(countries)개 나라 · 결제 \(AppFormat.count(totals.purchases))건")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(totals.proceedsLabel)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("환율을 받으면 원화 합계와 지도가 나옵니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func map(_ places: [Place]) -> some View {
        let plotted = places.filter { $0.usd > 0 && CountryCentroids.coordinate($0.code) != nil }
        let peak = plotted.map(\.usd).max() ?? 1
        return WorldSnapshot { project in
            ForEach(plotted) { place in
                if let coordinate = CountryCentroids.coordinate(place.code), let point = project(coordinate) {
                    bubble(place, peak: peak)
                        .position(point)
                }
            }
        }
        .accessibilityLabel("수익 지도. 나라별 금액은 아래 목록에 있습니다.")
    }

    /// 넓이가 금액에 비례하는 원. 가장 작아도 눈에 보이게 10pt.
    private func bubble(_ place: Place, peak: Double) -> some View {
        let diameter = max(10, 56 * sqrt(place.usd / peak))
        return Circle()
            .fill(Color.orange.opacity(0.45))
            .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
            .frame(width: diameter, height: diameter)
            .help("\(ChartStorefronts.flag(place.code)) \(ChartStorefronts.name(place.code)) · \(place.money?.label ?? place.rawLabel)")
    }

    private func list(_ places: [Place]) -> some View {
        let shown = showsAll ? places : Array(places.prefix(8))
        let peak = places.first?.usd ?? 0
        return VStack(spacing: 10) {
            ForEach(shown) { place in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(place.code == "??" ? "🏳️" : ChartStorefronts.flag(place.code))
                        Text(place.code == "??" ? "나라 모름" : ChartStorefronts.name(place.code))
                            .font(.body)
                            .lineLimit(1)
                        if place.purchases > 0 {
                            Text("결제 \(place.purchases)건")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            if let money = place.money {
                                Text(MoneyFormat.krw(money.krw))
                                    .font(.body.monospacedDigit().weight(.semibold))
                            } else {
                                Text(place.rawLabel)
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                    if peak > 0 {
                        MeterBar(ratio: place.usd / peak, tint: .orange)
                            .frame(height: 6)
                    }
                }
            }
            if places.count > 8 {
                Button(showsAll ? "접기" : "\(places.count - 8)개 나라 더 보기") {
                    withAnimation { showsAll.toggle() }
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func footnote(_ total: Money?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("개발자 수익금(Apple 수수료 · 세금 뺀 금액)을 \(total.map { AppFormat.relative($0.ratesDate) } ?? "오늘") 환율로 바꾼 어림값입니다. 실제 지급액은 지급일 환율을 따릅니다.")
            if let missing = total?.unconverted, !missing.isEmpty {
                Text("환율이 없어 합계에서 빠진 통화: \(missing.joined(separator: ", "))")
                    .foregroundStyle(.orange)
            }
            Link(ExchangeRates.attribution, destination: ExchangeRates.attributionURL)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 세계 전체를 찍은 지도, 그 위에 원을 얹는 판.
///
/// 처음에는 움직이는 `Map` 이었다. 그런데 맥의 MapKit 은 경도 180도 넘게는 물러나지 않아
/// (영역 · 자동 맞춤 · 카메라 거리 모두) 한국과 브라질이 같이 벌면 둘 중 하나가 잘렸다.
/// 스냅샷도 한 장에 180도까지만 찍는다 — 그림을 크게 요청해도 배율만 커진다(실측). 그래서
/// 서반구 · 동반구를 한 장씩 찍어 나란히 붙인다.
///
/// 원의 자리는 스냅샷이 말해 주는 대로 놓는다(`Snapshot.point(for:)`). 맥에서는 그 점이
/// 그림의 **왼쪽 아래**를 원점으로 하므로(AppKit 좌표) 위아래를 뒤집는다.
private struct WorldSnapshot<Overlay: View>: View {
    /// 좌표 → 판 위의 점. 판 크기에 맞춰 부른다.
    @ViewBuilder let overlay: (_ project: @escaping (CLLocationCoordinate2D) -> CGPoint?) -> Overlay

    @Environment(\.colorScheme) private var colorScheme
    @State private var halves: (west: Half, east: Half)?

    /// 반구 한 장.
    private struct Half {
        let image: CGImage
        let scale: CGFloat
        let snapshot: MKMapSnapshotter.Snapshot
        let size: CGSize

        /// 이 반구 그림 안에서 0...1 로 잰 자리. 그림 밖이면 nil.
        func unit(_ coordinate: CLLocationCoordinate2D) -> CGPoint? {
            let point = snapshot.point(for: coordinate)
            let x = point.x / size.width
            #if os(macOS)
            let y = 1 - point.y / size.height
            #else
            let y = point.y / size.height
            #endif
            guard (0...1).contains(x), (0...1).contains(y) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    /// 반구 한 장의 크기(포인트). 화면에서는 줄여 보이므로 이만하면 충분하다.
    private static var halfSize: CGSize { CGSize(width: 900, height: 900 / WorldMapFrame.halfAspect) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let halves {
                    HStack(spacing: 0) {
                        Image(decorative: halves.west.image, scale: halves.west.scale).resizable()
                        Image(decorative: halves.east.image, scale: halves.east.scale).resizable()
                    }
                    overlay { coordinate in
                        // 서경은 왼쪽 판, 동경은 오른쪽 판.
                        let isWest = coordinate.longitude < 0
                        guard let unit = (isWest ? halves.west : halves.east).unit(coordinate) else { return nil }
                        let half = geo.size.width / 2
                        return CGPoint(x: (isWest ? 0 : half) + unit.x * half, y: unit.y * geo.size.height)
                    }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .aspectRatio(WorldMapFrame.halfAspect * 2, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: colorScheme) { await take() }
    }

    private func take() async {
        guard let west = await shoot(WorldMapFrame.west),
              let east = await shoot(WorldMapFrame.east) else { return }
        halves = (west, east)
    }

    private func shoot(_ rect: MKMapRect) async -> Half? {
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = Self.halfSize
        options.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        #if os(macOS)
        options.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        #else
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(displayScale: 2),
        ])
        #endif
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        #if os(macOS)
        guard let image = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let image = snapshot.image.cgImage else { return nil }
        #endif
        return Half(image: image, scale: CGFloat(image.width) / Self.halfSize.width,
                    snapshot: snapshot, size: Self.halfSize)
    }
}

/// 수익 지도가 찍는 영역: 북위 76도 ~ 남위 56도. 남극과 북극해는 뺀다 — 앱을 사는 사람이
/// 없는 넓은 흰 땅이다. 경도는 반구 둘로 나눈다(`WorldSnapshot`).
private enum WorldMapFrame {
    static let west = rect(west: -180, east: 0)
    static let east = rect(west: 0, east: 180)
    static var halfAspect: CGFloat { west.size.width / west.size.height }

    private static func rect(west: Double, east: Double) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: 76, longitude: west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: -56, longitude: east))
        // 동경 180도는 MKMapPoint 에서 0 으로 돌아가므로 폭은 세계 폭의 절반으로 둔다.
        return MKMapRect(x: topLeft.x, y: topLeft.y, width: MKMapRect.world.size.width / 2,
                         height: bottomRight.y - topLeft.y)
    }
}

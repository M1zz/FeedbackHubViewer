//
//  InstallMapCard.swift
//  FeedbackHubViewer
//
//  설치가 세계 어디에 있나 — 지도 위의 원과 많은 나라 순 목록.
//
//  두 가지를 고를 수 있다.
//   · 허브 설치(누적) — 앱이 보낸 사용 스냅샷의 기기 지역(locale). 통계 칸의 "설치 N대" 와 같은
//     설치들이다. 지역 없는 locale("en")은 나라를 모르니 따로 센다.
//   · App Store 첫 다운로드(30일) — 판매 리포트의 나라 코드. 정확하지만 최근 30일뿐이다.
//  지도는 판매 지도와 같은 판(`WorldSnapshot`)에 그린다.
//

import SwiftUI

struct InstallMapCard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var connect: AppStoreConnectStore
    /// nil == 전체 앱.
    let project: String?

    enum Source: String, CaseIterable, Identifiable {
        case hub = "허브 설치(누적)"
        case store = "App Store 첫 다운로드(30일)"
        var id: String { rawValue }
    }

    @State private var source: Source = .hub
    @State private var showsAll = false

    private struct Place: Identifiable {
        let code: String
        let count: Int
        var id: String { code }
    }

    var body: some View {
        let counts = self.counts
        let places = counts.places
        let total = places.reduce(0) { $0 + $1.count } + counts.unknown

        Card(title: "설치 지도", systemImage: "globe.asia.australia") {
            if connect.sales != nil {
                Picker("자료", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if places.isEmpty {
                Text(source == .hub ? "나라를 알 수 있는 설치가 아직 없어요." : "최근 30일 첫 다운로드가 없어요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                headline(places, total: total)
                map(places)
                list(places)
                if counts.unknown > 0 {
                    Text(source == .hub
                         ? "나라를 모르는 설치 \(AppFormat.count(counts.unknown))대 — 기기 지역 없이 언어만 보낸 설치(\"en\" 같은)예요."
                         : "나라 코드가 없는 다운로드 \(AppFormat.count(counts.unknown))회")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: project) {
            if let project, connect.isConfigured { await connect.loadCatalog(bundleID: project) }
        }
    }

    // MARK: - 셈

    private var counts: (places: [Place], unknown: Int) {
        var byCountry: [String: Int] = [:]
        var unknown = 0
        switch source {
        case .hub:
            let installs = store.audienceInstalls(for: project)
            for (code, ids) in installs.regions { byCountry[code] = ids.count }
            unknown = installs.regionUnknown.count
        case .store:
            guard let sales = connect.sales else { break }
            let raw: [String: Int]
            if let project {
                guard case .loaded(let app, _)? = connect.catalogs[project] else { raw = [:]; break }
                raw = sales.totals(for: app.id).firstDownloadCountries
            } else {
                raw = sales.allTotals.firstDownloadCountries
            }
            for (code, count) in raw {
                if code == "??" { unknown += count } else { byCountry[code.uppercased(), default: 0] += count }
            }
        }
        let places = byCountry.filter { $0.value > 0 }
            .map { Place(code: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.code) > ($1.count, $0.code) }
        return (places, unknown)
    }

    // MARK: - 그리기

    /// "설치 1,234대 · 42개 나라 · 한국 61% · 다음 미국 9%" — 지도보다 먼저 읽히는 한 줄.
    private func headline(_ places: [Place], total: Int) -> some View {
        let known = places.reduce(0) { $0 + $1.count }
        var detail = "\(places.count)개 나라"
        if let first = places.first {
            detail += " · \(ChartStorefronts.name(first.code)) \(Self.percent(first.count, of: known))"
        }
        if places.count > 1 {
            detail += " · 다음 \(ChartStorefronts.name(places[1].code)) \(Self.percent(places[1].count, of: known))"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(source == .hub ? "설치 \(AppFormat.count(total))대" : "첫 다운로드 \(AppFormat.count(total))회")
                .font(.title2.weight(.bold).monospacedDigit())
            Text(detail)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func map(_ places: [Place]) -> some View {
        let plotted = places.filter { CountryCentroids.coordinate($0.code) != nil }
        let peak = Double(plotted.map(\.count).max() ?? 1)
        return WorldSnapshot { project in
            ForEach(plotted) { place in
                if let coordinate = CountryCentroids.coordinate(place.code), let point = project(coordinate) {
                    // 넓이가 수에 비례. 가장 작아도 보이게 8pt.
                    let diameter = max(8, 56 * sqrt(Double(place.count) / peak))
                    Circle()
                        .fill(Color.accentColor.opacity(0.4))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: diameter, height: diameter)
                        .help("\(ChartStorefronts.flag(place.code)) \(ChartStorefronts.name(place.code)) · \(AppFormat.count(place.count))")
                        .position(point)
                }
            }
        }
        .accessibilityLabel("설치 지도. 나라별 수는 아래 목록에 있습니다.")
    }

    private func list(_ places: [Place]) -> some View {
        let shown = showsAll ? places : Array(places.prefix(8))
        let peak = Double(places.first?.count ?? 1)
        let known = places.reduce(0) { $0 + $1.count }
        return VStack(spacing: 8) {
            ForEach(shown) { place in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ChartStorefronts.flag(place.code))
                        Text(ChartStorefronts.name(place.code))
                            .font(.body)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(AppFormat.count(place.count)) · \(Self.percent(place.count, of: known))")
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    MeterBar(ratio: Double(place.count) / peak, tint: .accentColor)
                        .frame(height: 6)
                }
            }
            if places.count > 8 {
                Button(showsAll ? "접기" : "\(places.count - 8)개 나라 더 보기") {
                    withAnimation { showsAll.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "—" }
        let value = Double(part) / Double(whole) * 100
        return value < 1 ? "1% 미만" : String(format: "%.0f%%", value)
    }
}

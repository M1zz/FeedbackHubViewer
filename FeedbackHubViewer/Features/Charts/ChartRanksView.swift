//
//  ChartRanksView.swift
//  FeedbackHubViewer
//
//  차트 — 내 앱이 나라마다 App Store 인기 차트 몇 위인가.
//
//  전체 앱: 앱마다 몇 나라 차트에 들었고 가장 높은 자리가 어디인지, 높은 앱부터.
//  한 앱: 지금 든 차트(나라 · 차트 · 순위 · 직전과 견준 움직임), 이번에 빠진 차트,
//  그리고 최근 며칠 동안 가장 좋았던 자리. 순위를 누르면 그때의 차트(위아래 몇 칸)가 근거로
//  뜨고, 오른쪽 클릭으로 App Store 웹 차트 · 원본 피드를 연다.
//

import SwiftUI

struct ChartRanksView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var charts: ChartStore
    /// nil == 전체 앱.
    let project: String?

    @State private var bestDays = 30
    @State private var editingCountries = false
    @State private var evidence: ChartEvidence?

    var body: some View {
        List {
            if charts.history.lastScan == nil && !charts.isScanning {
                Section {
                    ContentUnavailableView {
                        Label("아직 확인하지 않았습니다", systemImage: "list.number")
                    } description: {
                        Text("국가 \(charts.countries.count)개의 무료 · 유료 · 매출 차트(전체와 앱의 카테고리)에서 상위 100위 안에 드는지 봅니다.")
                    } actions: {
                        Button("지금 확인") { scan() }
                            .buttonStyle(.borderedProminent)
                            .disabled(trackIds.isEmpty)
                    }
                }
            } else if let project {
                appSections(project)
            } else {
                overviewSection
            }
        }
        .hubListStyle()
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $editingCountries) {
            ChartCountriesSheet()
                .environmentObject(charts)
        }
        .sheet(item: $evidence) { item in
            ChartEvidenceSheet(evidence: item, mine: Set(charts.history.apps.keys))
        }
    }

    /// 허브에 있는 내 앱 중 App Store 와 이어진 것.
    private var trackIds: Set<Int> {
        Set(store.projectCounts.compactMap { keywords.trackId(for: $0.key) })
    }

    private func scan() {
        let ids = trackIds
        Task { await charts.scan(trackIds: ids) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    editingCountries = true
                } label: {
                    Label("국가 \(charts.countries.count)개", systemImage: "globe")
                }
                .help(charts.countries.map(ChartStorefronts.name).joined(separator: ", "))

                Spacer(minLength: 4)

                if let progress = charts.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 60)
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let last = charts.history.lastScan {
                    Text("확인 \(AppFormat.relative(last.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    scan()
                } label: {
                    Label("지금 확인", systemImage: "arrow.clockwise")
                }
                .disabled(charts.isScanning || trackIds.isEmpty)
            }
            .buttonStyle(.bordered)
            .font(.callout)

            if let message = charts.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .hubHeaderBar(verticalPadding: 8)
    }

    // MARK: - 전체 앱

    private var overviewSection: some View {
        let rows = store.projectCounts.compactMap { entry -> (project: String, trackId: Int)? in
            keywords.trackId(for: entry.key).map { (entry.key, $0) }
        }
        .sorted { lhs, rhs in
            let l = charts.history.bestCurrent(for: lhs.trackId)?.rank ?? .max
            let r = charts.history.bestCurrent(for: rhs.trackId)?.rank ?? .max
            return l == r ? store.displayName(for: lhs.project) < store.displayName(for: rhs.project) : l < r
        }

        return Section {
            ForEach(rows, id: \.project) { row in
                Button {
                    store.open(project: row.project, section: .charts)
                } label: {
                    overviewRow(project: row.project, trackId: row.trackId)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("높은 자리부터")
        } footer: {
            Text("상위 100위 안에 든 것만 순위가 있습니다. Apple 차트 피드가 100위까지만 줍니다.")
        }
    }

    private func overviewRow(project: String, trackId: Int) -> some View {
        let best = charts.history.bestCurrent(for: trackId)
        let byCountry = charts.history.bestByCountry(for: trackId)
        return HStack(spacing: 10) {
            AppIcon(url: keywords.storeApp(for: project)?.iconURL, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(for: project))
                    .lineLimit(1)
                Group {
                    if !byCountry.isEmpty {
                        // 나라마다 가장 높은 자리 — 어디서 몇 위인지가 한 줄에 다 보이게.
                        Text(ChartStorefronts.summary(byCountry, limit: 6))
                    } else {
                        Text("100위 밖")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let best { RankPill(rank: best.rank) }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - 한 앱

    @ViewBuilder
    private func appSections(_ project: String) -> some View {
        if let trackId = keywords.trackId(for: project) {
            let current = charts.history.current(for: trackId)
            let dropped = charts.history.dropped(for: trackId)

            Section {
                if current.isEmpty {
                    Text(charts.history.apps[trackId] == nil
                         ? "아직 이 앱을 확인하지 않았습니다. 지금 확인을 눌러 주세요."
                         : "고른 나라의 차트 상위 100위 안에 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(current, id: \.self) { hit in
                        evidenceButton(hit: hit, date: nil) {
                            ChartRankRow(country: hit.slot.country,
                                         detail: slotLabel(hit.slot),
                                         rank: hit.rank,
                                         move: charts.history.move(of: hit))
                        }
                    }
                }
            } header: {
                Text(currentHeader(trackId: trackId))
            }

            if !dropped.isEmpty {
                Section("이번에 100위 밖으로") {
                    ForEach(dropped, id: \.self) { hit in
                        ChartRankRow(country: hit.slot.country,
                                     detail: "\(slotLabel(hit.slot)) · 직전 \(hit.rank)위",
                                     rank: nil, move: nil)
                            .contextMenu { ChartSourceLinks(slot: hit.slot) }
                    }
                }
            }

            bestSection(trackId: trackId)
        } else {
            Section {
                Text("이 앱을 App Store 에서 찾지 못했습니다. 아직 출시 전이거나 번들 ID 가 다릅니다.")
                    .foregroundStyle(.secondary)
                StoreLinkField(project: project) {
                    // 이어졌으면 바로 순위를 본다.
                    if let id = keywords.trackId(for: project) {
                        Task { await charts.scan(trackIds: trackIds.union([id])) }
                    }
                }
            }
        }
    }

    private func currentHeader(trackId: Int) -> String {
        let countries = charts.history.countriesRanked(for: trackId)
        guard let app = charts.history.apps[trackId] else { return "지금 순위" }
        var text = "지금 순위 · \(countries)개국"
        text += " · \(app.platform.label) \(app.isFree ? "무료" : "유료")"
        if let genre = app.genreName { text += " · \(genre)" }
        return text
    }

    private func bestSection(trackId: Int) -> some View {
        let best = charts.history.best(for: trackId, days: bestDays)
        let countries = Set(best.map(\.hit.slot.country)).count
        return Section {
            Picker("기간", selection: $bestDays) {
                Text("7일").tag(7)
                Text("30일").tag(30)
                Text("90일").tag(90)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if best.isEmpty {
                Text("이 기간에 차트에 든 기록이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(best, id: \.hit) { entry in
                    evidenceButton(hit: entry.hit, date: entry.date) {
                        ChartRankRow(country: entry.hit.slot.country,
                                     detail: "\(slotLabel(entry.hit.slot)) · \(AppFormat.relative(entry.date))",
                                     rank: entry.hit.rank, move: nil)
                    }
                }
            }
        } header: {
            Text("최근 \(bestDays)일 최고 순위 · \(countries)개국")
        }
    }

    /// 순위 한 줄 — 누르면 그때의 차트, 오른쪽 클릭이면 원본. `date` 가 nil 이면 가장 최근 확인.
    private func evidenceButton(hit: ChartHit, date: Date?, @ViewBuilder label: () -> some View) -> some View {
        Button {
            evidence = ChartEvidence(hit: hit, label: slotLabel(hit.slot),
                                     date: date ?? charts.history.lastScan?.date ?? .now,
                                     snapshot: charts.history.snapshot(of: hit, at: date))
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { ChartSourceLinks(slot: hit.slot) }
    }

    /// "iPhone 무료 · 전체" / "무료 · 생산성".
    private func slotLabel(_ slot: ChartSlot) -> String {
        let genre = slot.genreId == nil ? "전체" : (charts.history.apps.values
            .first { $0.genreId == slot.genreId }?.genreName ?? "카테고리")
        let platform = slot.platform == .mac ? "Mac " : ""
        return "\(platform)\(slot.kind.label) · \(genre)"
    }
}

/// 나라 한 줄: 국기 · 이름 · 차트 · 순위 · 움직임.
private struct ChartRankRow: View {
    let country: String
    let detail: String
    let rank: Int?
    let move: ChartMove?

    var body: some View {
        HStack(spacing: 10) {
            Text(ChartStorefronts.flag(country))
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(ChartStorefronts.name(country))
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let move { MoveLabel(move: move) }
            if let rank { RankPill(rank: rank) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// 순위 알약. 10위 안은 노랗게 — 거기가 스토어 첫 화면에 보이는 자리다.
private struct RankPill: View {
    let rank: Int

    var body: some View {
        Text("\(rank)위")
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rank <= 10 ? Color.yellow.opacity(0.35) : Color.secondary.opacity(0.15),
                        in: Capsule())
    }
}

private struct MoveLabel: View {
    let move: ChartMove

    var body: some View {
        switch move {
        // 시세판처럼 오름 빨강 · 내림 파랑(`RankTrend`).
        case .entered:
            Text("새로 듦").foregroundStyle(RankTrend.up)
                .font(.body.weight(.semibold))
        case .up(let n):
            RankMoveLabel(climbed: n)
        case .down(let n):
            RankMoveLabel(climbed: -n)
        case .same:
            RankMoveLabel(climbed: 0)
        case .unknown:
            EmptyView()
        }
    }
}

/// 순위 하나의 근거를 띄울 때 넘기는 것.
private struct ChartEvidence: Identifiable {
    let hit: ChartHit
    let label: String
    /// 그 순위를 적은 확인.
    let date: Date
    /// 그때의 차트. 이 기록이 생기기 전 확인이면 nil.
    let snapshot: ChartSnapshot?

    var id: String { "\(hit.hashValue)-\(date.timeIntervalSince1970)" }
}

/// 원본으로 가는 길: App Store 웹 차트와 받은 피드. 둘 다 **지금의** 차트를 보여 준다.
private struct ChartSourceLinks: View {
    let slot: ChartSlot

    var body: some View {
        if let url = slot.webURL {
            Link(destination: url) {
                Label("App Store 에서 차트 열기", systemImage: "safari")
            }
        }
        if let url = slot.feedURL {
            Link(destination: url) {
                Label("차트 피드 열기 (JSON)", systemImage: "curlybraces")
            }
        }
    }
}

/// 그때의 차트 — 내 앱 위아래 몇 칸, 내 앱은 칠해서. 캡쳐 대신 남겨 둔 근거다.
private struct ChartEvidenceSheet: View {
    let evidence: ChartEvidence
    /// 칠할 앱 — 허브의 내 앱 전부. 같은 차트에 다른 내 앱이 옆에 있으면 그것도 보인다.
    let mine: Set<Int>
    @Environment(\.dismiss) private var dismiss

    private var slot: ChartSlot { evidence.hit.slot }

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = evidence.snapshot {
                    Section {
                        ForEach(snapshot.rows, id: \.rank) { row in
                            entryRow(rank: row.rank, entry: row.entry)
                        }
                    } header: {
                        Text("\(ChartStorefronts.flag(slot.country)) \(ChartStorefronts.name(slot.country)) · \(evidence.label)")
                    } footer: {
                        Text(sourceText(snapshot))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        Text("이 순위를 적은 확인에는 그때의 차트가 남아 있지 않습니다. 근거를 남기기 전에 한 확인입니다. 다음 확인부터 남습니다.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ChartSourceLinks(slot: slot)
                } header: {
                    Text("원본")
                } footer: {
                    Text(slot.webURL == nil
                         ? "지금의 차트가 열립니다. App Store 웹에는 매출 차트가 없어 피드만 엽니다."
                         : "지금의 차트가 열립니다. 위 목록은 확인했던 때의 것입니다.")
                }
            }
            .navigationTitle("\(evidence.hit.rank)위의 근거")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private func entryRow(rank: Int, entry: ChartEntry) -> some View {
        let isMine = mine.contains(entry.trackId)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.body.monospacedDigit().weight(isMine ? .bold : .regular))
                .frame(minWidth: 32, alignment: .trailing)
            AppIcon(url: entry.iconURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(isMine ? .bold : .regular))
                    .lineLimit(1)
                if let developer = entry.developer {
                    Text(developer)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .listRowBackground(isMine ? Color.yellow.opacity(0.25) : nil)
        .accessibilityElement(children: .combine)
    }

    /// 어디서 · 언제 받은 것인지. 이어 쓴 칸이면 그것도 밝힌다.
    private func sourceText(_ snapshot: ChartSnapshot) -> String {
        let when = snapshot.date.formatted(date: .abbreviated, time: .shortened)
        var text = "출처: Apple RSS 차트 피드 · \(when) 확인 · \(snapshot.total)위까지 중 위아래 \(ChartSnapshot.around)칸."
        if snapshot.date != evidence.date {
            text += " 이 확인에서는 이 차트를 받지 못해 \(when) 확인의 차트를 이어 썼습니다."
        }
        text += " App Store 앱에 보이는 차트와 조금 다를 수 있습니다."
        return text
    }
}

/// 볼 나라 고르기.
private struct ChartCountriesSheet: View {
    @EnvironmentObject private var charts: ChartStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var visible: [String] {
        guard !filter.isEmpty else { return ChartStorefronts.all }
        return ChartStorefronts.all.filter {
            ChartStorefronts.name($0).localizedCaseInsensitiveContains(filter) || $0.contains(filter.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("전체 선택") { charts.countries = ChartStorefronts.all }
                        Spacer()
                        Button("기본 \(ChartStorefronts.defaults.count)개국") { charts.countries = ChartStorefronts.defaults }
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text(costText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    ForEach(visible, id: \.self) { code in
                        Button {
                            toggle(code)
                        } label: {
                            HStack {
                                Text(ChartStorefronts.flag(code))
                                Text(ChartStorefronts.name(code))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if charts.countries.contains(code) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $filter, prompt: "나라 이름 또는 코드")
            .navigationTitle("볼 나라 · \(charts.countries.count)/\(ChartStorefronts.all.count)개")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
    }

    /// 확인 한 번이 얼마나 무거운지 — 나라를 다 고르면 몇 분 걸리고 수백 MB 를 받는다.
    private var costText: String {
        let feeds = charts.countries.count * charts.feedsPerCountry
        let megabytes = Double(feeds * ChartStorefronts.approximateFeedBytes) / 1_000_000
        let size = megabytes >= 100 ? String(format: "%.0fMB", megabytes) : String(format: "%.1fMB", megabytes)
        return "확인 한 번에 차트 피드 \(feeds)개, 약 \(size)를 받습니다. 저절로는 하루 한 번, 와이파이에서만 확인합니다(셀룰러 · 저데이터 모드에서는 건너뜀). 지금 확인은 언제든 됩니다."
    }

    private func toggle(_ code: String) {
        if let index = charts.countries.firstIndex(of: code) {
            // 하나는 남긴다 — 볼 나라가 없으면 확인이 아무것도 못 본다.
            guard charts.countries.count > 1 else { return }
            charts.countries.remove(at: index)
        } else {
            // 고를 수 있는 나라 순서를 지킨다(큰 시장부터).
            charts.countries = ChartStorefronts.all.filter { charts.countries.contains($0) || $0 == code }
        }
    }
}

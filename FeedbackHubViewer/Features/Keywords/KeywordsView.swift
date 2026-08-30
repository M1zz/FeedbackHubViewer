//
//  KeywordsView.swift
//  FeedbackHubViewer
//
//  One app's 키워드 screen — where it ranks in App Store search, who ranks
//  above it, and where that has moved.
//
//  Ranked terms come first and unranked ones after, because the ranked ones are
//  what you came to look at and the unranked ones are the work list. A rank
//  that improved is green and negative ("−6"), which reads backwards for a
//  moment and then never again: in a ranking, down is up.
//
//  Nothing here shows a 검색량. Apple publishes none, so any figure would be a
//  model dressed up as a measurement. What the screen shows instead is how many
//  results the store actually returned, which is the honest denominator for
//  "안 잡힘".
//

import SwiftUI

struct KeywordsView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore

    /// nil == 전체 프로젝트.
    let project: String?

    @State private var newTerm = ""
    @State private var addCountries: Set<String> = []
    @State private var expanded: TrackedKeyword.ID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let app = linkedApp { linkedAppCard(app) } else { unlinkedCard }
                if linkedApp != nil && standings.isEmpty { startCard }
                addCard
                if !standings.isEmpty { rankCard }
                // Shown even when empty. Competitors are read out of the
                // results for the terms you track, so with no terms this card
                // is blank — and a card that just disappears leaves you to
                // work out the dependency for yourself.
                if linkedApp != nil { competitorCard }
                if !suggestions.isEmpty { suggestionCard }
                limitsCard
            }
            .padding(16)
        }
        .task { addCountries = Set(keywords.countries.prefix(1)) }
        .overlay(alignment: .top) { checkBanner }
    }

    // MARK: - The app on the store

    private var linkedApp: StoreApp? {
        guard let project else { return nil }
        return keywords.storeApp(for: project)
    }

    private func linkedAppCard(_ app: StoreApp) -> some View {
        Card(title: "App Store", systemImage: "app.badge") {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: app.iconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline)
                    Text(app.genres.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if let rating = app.averageRating, app.ratingCount > 0 {
                            Label(String(format: "%.2f (%d)", rating, app.ratingCount),
                                  systemImage: "star.fill")
                        }
                        if let version = app.version { Text("v\(version)") }
                        if let released = app.releasedAt { Text(AppFormat.relative(released)) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = app.storeURL {
                    Link(destination: url) { Image(systemName: "arrow.up.forward.square") }
                        .help("App Store에서 열기")
                }
            }
        }
    }

    /// An app the hub knows about that the store does not. Almost always a
    /// Development-only build or one still in review — worth saying plainly
    /// rather than showing an empty keyword table.
    private var unlinkedCard: some View {
        Card(title: "App Store", systemImage: "questionmark.app") {
            VStack(alignment: .leading, spacing: 8) {
                Text(project == nil
                     ? "프로젝트를 하나 고르면 그 앱의 키워드 순위를 봅니다."
                     : keywords.isChecking
                         ? "App Store에서 이 앱을 찾는 중입니다…"
                         : "이 번들 ID로 App Store에서 앱을 찾지 못했습니다. 아직 심사 중이거나 개발용 빌드일 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                if project != nil {
                    Button("App Store에서 다시 찾기") {
                        keywords.refreshLinks(bundleIds: store.allProjectKeys)
                    }
                }
            }
        }
    }

    // MARK: - Getting started

    /// The first screen anyone sees. It has to say two things: that everything
    /// below hangs off the terms you track, and that you do not have to think
    /// any of them up.
    private var startCard: some View {
        Card(title: "여기서 시작", systemImage: "sparkle.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text("추적 중인 검색어가 없습니다. **순위도 경쟁 앱도 검색어에서 나옵니다** — 검색어 하나를 넣으면 그 검색 결과에서 내 순위를 읽고, 같은 결과의 상위 앱들이 경쟁 앱이 됩니다.")
                    .font(.callout)
                Text("떠올리지 않아도 됩니다. 이 앱 이름으로 검색해 같은 자리에 서는 앱들을 모으고, **경쟁 앱 몇 개의 이웃까지** 훑어 이름들이 공통으로 쓰는 말을 후보로 뽑은 다음, **하나씩 실제로 검색해서 순위에 잡히는 것만** 남깁니다.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        if let project { keywords.discover(for: project, country: addCountries.first) }
                    } label: {
                        Label("앱 이름으로 자동 찾기", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project == nil || keywords.isChecking)
                    Text("검색어 하나당 3초, 열두 개면 30초쯤")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Adding

    private var addCard: some View {
        Card(title: "키워드 추가", systemImage: "plus.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("검색어 (예: 클립보드)", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("추가", action: add)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty
                                  || addCountries.isEmpty)
                }
                countryPicker
                HStack(spacing: 8) {
                    Text("검색 한 번이 내 앱 전부를 커버합니다. 같은 검색어를 다른 앱에서도 추적해도 요청은 늘지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if project != nil, !standings.isEmpty {
                        Button {
                            if let project { keywords.discover(for: project, country: addCountries.first) }
                        } label: {
                            Label("자동 찾기", systemImage: "wand.and.stars").font(.caption)
                        }
                        .disabled(keywords.isChecking)
                    }
                }
            }
        }
    }

    /// The storefronts to add a term for. Multi-select, because a term is
    /// tracked per store and adding "메모" for kr and us at once is the common
    /// case; each one is its own row afterwards, since the ranks differ.
    private var countryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keywords.countries, id: \.self) { code in
                    let on = addCountries.contains(code)
                    FilterChip(title: Storefront.name(for: code), isSelected: on) {
                        if on { addCountries.remove(code) } else { addCountries.insert(code) }
                    }
                }
                Menu {
                    ForEach(Storefront.common, id: \.code) { entry in
                        if !keywords.countries.contains(entry.code) {
                            Button(entry.name) { keywords.countries.append(entry.code) }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("추적할 국가 추가")
            }
        }
    }

    private func add() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !addCountries.isEmpty else { return }
        keywords.add(term: term, countries: Array(addCountries), for: project)
        // Checked on the spot rather than waiting for tomorrow's pass: a term
        // added to an empty row tells you nothing.
        for country in addCountries {
            keywords.checkNow(TrackedKeyword(term: term, country: country))
        }
        newTerm = ""
    }

    // MARK: - Ranks

    private var standings: [KeywordStanding] { keywords.standings(for: project) }

    private var rankCard: some View {
        Card(title: "키워드 순위", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 0) {
                if standings.contains(where: { $0.blockers != nil }) {
                    Text("순위순입니다. 각 줄의 **‘N개 앞섬’** 은 위에 있는 앱 중 내 앱보다 리뷰가 많은 것의 수 — 18위인데 위 17개 중 7개가 나보다 작으면 실제로는 10개 뒤입니다. 순위가 낮아도 앞선 앱이 적으면 그쪽이 더 가깝습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }
                ForEach(standings, id: \.keyword.id) { standing in
                    KeywordRow(standing: standing,
                               isExpanded: expanded == standing.keyword.id,
                               trackId: keywords.trackId(for: project),
                               history: keywords.history) {
                        expanded = expanded == standing.keyword.id ? nil : standing.keyword.id
                    } onCheck: {
                        keywords.checkNow(standing.keyword)
                    } onRemove: {
                        keywords.remove(standing.keyword, from: project)
                    }
                    if standing.keyword.id != standings.last?.keyword.id { Divider() }
                }
            }
        }
    }

    // MARK: - Competitors

    private var competitors: [CompetitorStanding] { keywords.competitors(for: project) }

    private var competitorCard: some View {
        Card(title: "경쟁 앱", systemImage: "person.2") {
            VStack(alignment: .leading, spacing: 10) {
                if competitors.isEmpty {
                    Text(standings.isEmpty
                         ? "아직 없습니다. 경쟁 앱은 **추적 중인 검색어의 결과**에서 뽑으므로, 검색어를 하나 넣어야 나옵니다."
                         : "아직 없습니다. 추적 중인 검색어를 한 번 확인하고 나면 그 결과의 상위 앱들이 여기 섭니다.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !competitors.isEmpty {
                    Text("추적 중인 키워드에서 실제로 마주친 앱입니다. 내 앱보다 위에 있는 횟수가 많은 순.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(competitors) { competitor in
                    competitorRow(competitor)
                }
            }
        }
    }

    /// One rival. The whole row opens its App Store page — looking at what the
    /// app above you actually looks like is the next thing anyone wants after
    /// reading that it is above you, and making them copy the name into the
    /// store by hand for that is silly.
    @ViewBuilder
    private func competitorRow(_ competitor: CompetitorStanding) -> some View {
        let row = HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: competitor.app.iconURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(competitor.app.name).font(.callout.weight(.medium)).lineLimit(1)
                    if let rating = competitor.app.averageRating, competitor.app.ratingCount > 0 {
                        Text(String(format: "★%.1f (%@)", rating,
                                    AppFormat.count(competitor.app.ratingCount)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(competitor.terms.prefix(4).joined(separator: " · ")
                     + (competitor.terms.count > 4 ? " 외 \(competitor.terms.count - 4)" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if competitor.timesAbove > 0 {
                    Text("내 위 \(competitor.timesAbove)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("\(competitor.keywords)개 키워드 · 최고 \(competitor.bestRank)위")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())

        if let url = competitor.app.storeURL {
            Link(destination: url) { row }
                .buttonStyle(.plain)
                .help("App Store에서 \(competitor.app.name) 열기")
        } else {
            row
        }
    }

    // MARK: - Suggestions

    private var suggestions: [String] { keywords.suggestions(for: project) }

    private var suggestionCard: some View {
        Card(title: "추가해볼 키워드", systemImage: "lightbulb") {
            VStack(alignment: .leading, spacing: 10) {
                Text("내 위에 있는 앱들의 이름에서 두 번 이상 나온 단어입니다. 추정이 아니라 검색 결과에서 그대로 뽑은 것이라, 실제로 쓸모 있는지는 눌러서 확인해보는 게 맞습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(suggestions, id: \.self) { word in
                        Button {
                            keywords.add(term: word, countries: Array(addCountries), for: project)
                            for country in addCountries {
                                keywords.checkNow(TrackedKeyword(term: word, country: country))
                            }
                        } label: {
                            Label(word, systemImage: "plus")
                                .font(.caption)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(addCountries.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - What this cannot tell you

    /// Stated on the screen rather than in a README. A tool that quietly leaves
    /// out what it cannot measure is how you end up trusting a number that was
    /// never a measurement.
    private var limitsCard: some View {
        Card(title: "이 숫자의 한계", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                limit("검색량은 없습니다.", "애플이 공개하지 않습니다. 다른 ASO 툴의 검색량도 전부 추정 모델입니다.")
                limit("순위는 iTunes Search API의 결과 순서입니다.", "App Store 앱 안의 검색 순위와 아주 가깝지만 같다는 보장은 없습니다.")
                limit("Google Play는 없습니다.", "공식 API가 없어 다른 방식이 필요합니다.")
                if let checked = keywords.history.lastCheckedAt {
                    limit("마지막 확인 \(AppFormat.relative(checked))",
                          "순위는 하루 단위로 움직이므로 하루 한 번만 확인합니다.")
                }
            }
        }
    }

    private func limit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Progress

    @ViewBuilder
    private var checkBanner: some View {
        if let progress = keywords.progress {
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction).frame(width: 90)
                Text(progress.text).font(.caption).lineLimit(1)
                Button("중단") { keywords.cancelCheck() }.font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let message = keywords.errorMessage {
            Text(message)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .onTapGesture { keywords.errorMessage = nil }
        }
    }
}

// MARK: - One keyword

/// One row: the term, where it sits, which way it moved, and thirty days of it.
private struct KeywordRow: View {
    let standing: KeywordStanding
    let isExpanded: Bool
    let trackId: Int?
    let history: KeywordHistory
    let onTap: () -> Void
    let onCheck: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(standing.keyword.term).font(.callout.weight(.medium))
                        // The country, and — where it is known — how far this
                        // place really is. A rank on its own cannot say whether
                        // it is worth going after; the apps above that are not
                        // smaller than yours can.
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    blockerLabel
                    RankSparkline(values: standing.recent).frame(width: 72, height: 22)
                    deltaLabel
                    rankLabel
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded { detail }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("지금 확인", systemImage: "arrow.clockwise", action: onCheck)
            Button("추적 중단", systemImage: "trash", role: .destructive, action: onRemove)
        }
    }

    private var subtitle: String {
        let country = Storefront.name(for: standing.keyword.country)
        guard let rank = standing.rank, rank > 1, let weaker = standing.weakerAbove else { return country }
        return "\(country) · 위 \(rank - 1)개 중 \(weaker)개가 내 앱보다 리뷰 적음"
    }

    /// How many apps above this one are not smaller than it — the honest
    /// distance to the top, next to the raw rank rather than in place of it.
    @ViewBuilder
    private var blockerLabel: some View {
        if let blockers = standing.blockers, standing.rank ?? 0 > 1 {
            Text(blockers == 0 ? "앞에 없음" : "\(blockers)개 앞섬")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(blockers <= 2 ? .green : (blockers <= 10 ? .orange : .secondary))
                .frame(width: 62, alignment: .trailing)
        } else {
            Color.clear.frame(width: 62, height: 1)
        }
    }

    private var rankLabel: some View {
        Group {
            if let rank = standing.rank {
                Text("\(rank)위")
                    .font(.body.weight(.semibold).monospacedDigit())
            } else {
                Text("안 잡힘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, alignment: .trailing)
    }

    /// Down is up. A rank that fell from 30 to 12 is −18 and green, which takes
    /// one glance to learn and then reads faster than any arrow would.
    @ViewBuilder
    private var deltaLabel: some View {
        if let delta = standing.delta, delta != 0 {
            Text(AppFormat.signed(delta))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(DeltaPolarity.lowerIsBetter.tint(for: delta))
                .frame(width: 36, alignment: .trailing)
        } else {
            Color.clear.frame(width: 36, height: 1)
        }
    }

    /// What the store actually returned for this term, with your app marked —
    /// the row's number, but checkable.
    @ViewBuilder
    private var detail: some View {
        let check = history.latestCheck(standing.keyword)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let best = standing.best { Text("최고 \(best)위") }
                if standing.resultCount > 0 { Text("결과 \(standing.resultCount)개") }
                if let seen = standing.seenAt { Text(AppFormat.relative(seen)) }
                Spacer()
                Button("지금 확인", action: onCheck).font(.caption)
            }
            .font(.caption).foregroundStyle(.secondary)

            if let check {
                ForEach(Array(check.top.prefix(10).enumerated()), id: \.offset) { index, id in
                    let isMine = id == trackId
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(history.apps[String(id)]?.name ?? "앱 \(id)")
                            .font(.caption)
                            .fontWeight(isMine ? .bold : .regular)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 1)
                    .background(isMine ? Color.accentColor.opacity(0.12) : .clear)
                }
            }
        }
        .padding(.leading, 4)
    }
}

/// Thirty days of one rank. Drawn upside down on purpose — 1위 belongs at the
/// top — with gaps left as gaps rather than joined through, so a day nobody
/// checked does not look like a day the rank held.
private struct RankSparkline: View {
    let values: [Int?]

    /// (day index, rank) for the days that actually have one. Computed outside
    /// the view builder: a `compactMap` with a `return` in it is not something
    /// `@ViewBuilder` will accept.
    private var points: [(day: Int, rank: Int)] {
        values.enumerated().compactMap { index, value in
            value.map { (day: index, rank: $0) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points = points
                guard points.count >= 2 else { return }
                let ranks = points.map(\.rank)
                let best = ranks.min() ?? 1
                // A flat line would divide by zero; one rank apart puts it in
                // the middle instead of at the top.
                let worst = max(ranks.max() ?? 1, best + 1)
                let stepX = geometry.size.width / CGFloat(max(values.count - 1, 1))

                var previous: Int?
                for point in points {
                    let ratio = CGFloat(point.rank - best) / CGFloat(worst - best)
                    let at = CGPoint(x: CGFloat(point.day) * stepX,
                                     y: ratio * geometry.size.height)
                    // Only join days that sit next to each other; a break in
                    // the checks is a break in the line.
                    if let previous, point.day == previous + 1 {
                        path.addLine(to: at)
                    } else {
                        path.move(to: at)
                    }
                    previous = point.day
                }
            }
            .stroke(Color.accentColor,
                    style: .init(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

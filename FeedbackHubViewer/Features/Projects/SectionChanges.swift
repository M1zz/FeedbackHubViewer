//
//  SectionChanges.swift
//  FeedbackHubViewer
//
//  마지막으로 본 뒤 바뀐 것 — 사이드바 · 앱 목록의 "새로 바뀜" 뱃지.
//
//  피드백 · 리뷰 · 진단 · 소식은 한 건 한 건이 새것이라 제 뱃지가 있다. 통계 · 차트 · 키워드
//  같은 칸은 새로고침이 숫자를 바꿀 뿐 "새 건" 이 없어서, 업데이트가 끝나도 어느 칸을 열어
//  봐야 하는지 알 길이 없었다. 그래서 칸마다 앱마다 그 칸이 하는 말(앱 목록 줄의 한마디 —
//  "설치 120대", "한국 3위", "문제 2개")을 기억해 두고, 마지막으로 그 칸을 본 때와 말이
//  달라진 앱을 센다. 숫자가 아니라 말을 견주므로 뜻이 같은 흔들림은 뱃지가 되지 않는다.
//
//  처음 보는 칸 · 앱은 조용히 기준선으로 잡는다 — 켜자마자 모든 칸에 뱃지가 서지 않게.
//
//  뱃지만으로는 열어 봐도 무엇이 바뀌었는지 모른다. 그래서 칸을 열어 본 것으로 칠 때 그 전
//  말과 지금 말을 따로 남겨 두고(`recent`), 화면 맨 위 띠(`SectionChangesBanner`)가
//  "설치 120대 → 125대" 처럼 그대로 보여 준다. 띠는 "확인" 을 누를 때까지 남는다.
//

import SwiftUI

/// 칸 · 앱마다 마지막으로 본 말. 이 기기에만 둔다.
@MainActor
final class SectionChanges: ObservableObject {
    static let shared = SectionChanges()

    /// "새 건" 뱃지가 따로 없는 칸 — 이 칸들만 바뀐 것을 센다.
    static let tracked: [FeedbackStore.ProjectSection] = [
        .stats, .release, .acquisition, .storeAnalytics, .keywords, .charts, .purchases, .design,
    ]

    private static let defaultsKey = "section-seen-signatures"
    private static let recentKey = "section-recent-changes"

    /// 열어 본 순간 달라져 있던 것 — 그 전 말과 지금 말.
    struct Change: Codable, Equatable {
        let section: String
        let project: String
        let before: String
        let after: String
        let at: Date
    }

    /// "칸|앱" → 확인 안 한 바뀜. 화면 맨 위 띠가 읽는다.
    @Published private(set) var recent: [String: Change]

    /// "칸|앱" → 마지막으로 본 말.
    @Published private var seen: [String: String]

    private init() {
        seen = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        recent = (UserDefaults.standard.data(forKey: Self.recentKey))
            .flatMap { try? JSONDecoder().decode([String: Change].self, from: $0) } ?? [:]
    }

    private static func key(_ section: FeedbackStore.ProjectSection, _ project: String) -> String {
        "\(section.rawValue)|\(project)"
    }

    /// 본 뒤 말이 달라졌는가. 기준선이 아직 없으면 아니다.
    func isChanged(_ section: FeedbackStore.ProjectSection, project: String, signature: String) -> Bool {
        guard let stored = seen[Self.key(section, project)] else { return false }
        return stored != signature
    }

    /// 처음 보는 칸 · 앱만 지금 말로 잡아 둔다.
    func adoptBaselines(_ signatures: [String: String]) {
        let missing = signatures.filter { seen[$0.key] == nil }
        guard !missing.isEmpty else { return }
        seen.merge(missing) { old, _ in old }
        persist()
    }

    /// 열어 봤다 — 지금 말을 본 것으로. 달라져 있던 것은 띠에 남긴다.
    func markSeen(_ section: FeedbackStore.ProjectSection, signatures: [String: String]) {
        var next = seen
        var nextRecent = recent
        for (project, signature) in signatures {
            let key = Self.key(section, project)
            if let old = seen[key], old != signature {
                // 확인 안 한 바뀜이 또 바뀌면 처음 말부터 지금 말까지 한 줄로.
                let before = nextRecent[key]?.before ?? old
                nextRecent[key] = before == signature ? nil
                    : Change(section: section.rawValue, project: project, before: before, after: signature, at: Date())
            }
            next[key] = signature
        }
        guard next != seen || nextRecent != recent else { return }
        seen = next
        recent = nextRecent
        persist()
    }

    /// 이 칸(한 앱이면 그 앱)의 확인 안 한 바뀜. 최근 것이 위.
    func recentChanges(_ section: FeedbackStore.ProjectSection, project: String?) -> [Change] {
        recent.values
            .filter { $0.section == section.rawValue && (project == nil || $0.project == project) }
            // 키워드는 10위 안팎을 넘나든 것만 말한다 — 그 안에서만 움직였으면 띠에 올리지 않는다.
            .filter { !Self.lines(section, before: $0.before, after: $0.after).isEmpty }
            .sorted { $0.at > $1.at }
    }

    /// 띠의 "확인".
    func dismiss(_ section: FeedbackStore.ProjectSection, project: String?) {
        let keys = recentChanges(section, project: project).map { Self.key(section, $0.project) }
        guard !keys.isEmpty else { return }
        for key in keys { recent[key] = nil }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(seen, forKey: Self.defaultsKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(recent), forKey: Self.recentKey)
    }

    // MARK: - 말

    /// 칸 하나 · 앱 하나가 지금 하는 말. 대부분 앱 목록 줄의 한마디와 같고, 그 한마디가
    /// 움직임을 놓치는 칸만 더 자세히 적는다.
    static func signature(_ section: FeedbackStore.ProjectSection, project: String,
                          metrics: SectionMetrics) -> String {
        let label = metrics.label(section, project: project)
        switch section {
        case .keywords:
            // "3/10 잡힘" 은 12위가 5위가 돼도 그대로다 — 키워드마다 순위를 적는다.
            return metrics.keywords.standings(for: project)
                .map { "\($0.keyword.id)=\($0.rank.map(String.init) ?? "-")" }
                .sorted()
                .joined(separator: ",")
        case .release:
            return label + "|" + metrics.subtitle(section, project: project)
        case .purchases:
            let products = metrics.purchases.products(for: project) ?? []
            return label + "|" + products.filter(\.isOnSale).count.description
        default:
            return label
        }
    }

    /// 그 칸의 모든 앱의 지금 말. 키는 앱.
    static func signatures(_ section: FeedbackStore.ProjectSection, project: String?,
                           metrics: SectionMetrics) -> [String: String] {
        let projects = project.map { [$0] } ?? appKeys(metrics.store)
        return Dictionary(uniqueKeysWithValues: projects.map {
            ($0, signature(section, project: $0, metrics: metrics))
        })
    }

    /// 모든 칸 · 모든 앱. 기준선을 잡을 때 쓴다. 키는 "칸|앱".
    static func allSignatures(metrics: SectionMetrics) -> [String: String] {
        var all: [String: String] = [:]
        for section in tracked {
            for (project, signature) in signatures(section, project: nil, metrics: metrics) {
                all[key(section, project)] = signature
            }
        }
        return all
    }

    static func appKeys(_ store: FeedbackStore) -> [String] {
        store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject }
    }

    /// 본 뒤 바뀐 것의 수. 키워드는 10위 선을 넘나든 키워드마다, 나머지 칸은 앱마다 하나.
    func changedCount(_ section: FeedbackStore.ProjectSection, project: String?,
                      metrics: SectionMetrics) -> Int {
        guard Self.tracked.contains(section) else { return 0 }
        return Self.signatures(section, project: project, metrics: metrics).reduce(0) { total, entry in
            guard let old = seen[Self.key(section, entry.key)], old != entry.value else { return total }
            let lines = Self.lines(section, before: old, after: entry.value).count
            // 키워드는 10위 안으로 들어오거나 밖으로 밀려난 것만 센다. 나머지 칸은 말이 바뀌면 하나.
            return total + (section == .keywords ? lines : max(1, lines))
        }
    }

    // MARK: - 무엇이 바뀌었나

    /// 바뀜을 사람 말로 — "설치 120대 → 125대", "🇰🇷 메모 12위 → 5위".
    static func lines(_ section: FeedbackStore.ProjectSection, before: String, after: String) -> [String] {
        switch section {
        case .keywords:
            let old = ranks(before), new = ranks(after)
            return new.keys.sorted().compactMap { id in
                let now = new[id] ?? "-"
                guard let was = old[id] else { return nil }
                // 순위가 매일 몇 칸씩 흔들려 다 세면 뱃지가 늘 가득했다 — 10위 선을 넘을 때만.
                guard isTopTen(was) != isTopTen(now) else { return nil }
                let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
                let name = parts.count == 2 ? "\(ChartStorefronts.flag(parts[0])) \(parts[1])" : id
                return "\(name) \(rankText(was)) → \(rankText(now))"
            }
        case .release:
            // "판정|부제" — 부제가 판정까지 담고 있어(… · 초록) 부제가 바뀌었으면 부제 한 줄만.
            let old = before.components(separatedBy: "|"), new = after.components(separatedBy: "|")
            if old.count == 2, new.count == 2, old[1] != new[1] { return ["\(old[1]) → \(new[1])"] }
            return old.first != new.first ? ["\(old.first ?? "") → \(new.first ?? "")"] : []
        case .purchases:
            let old = before.components(separatedBy: "|"), new = after.components(separatedBy: "|")
            let labels = section == .purchases ? ["", "판매 중 "] : ["", ""]
            return zip(old, new).enumerated().compactMap { index, pair in
                pair.0 == pair.1 ? nil : "\(labels[min(index, 1)])\(pair.0) → \(pair.1)"
            }
        default:
            return ["\(before) → \(after)"]
        }
    }

    private static func ranks(_ signature: String) -> [String: String] {
        Dictionary(signature.split(separator: ",").compactMap { item -> (String, String)? in
            guard let eq = item.lastIndex(of: "=") else { return nil }
            return (String(item[..<eq]), String(item[item.index(after: eq)...]))
        }, uniquingKeysWith: { a, _ in a })
    }

    /// 뱃지를 다는 선. 이 안에 들어야 검색 첫 화면 두 장 안쪽이다.
    static let topRankLine = 10

    private static func isTopTen(_ rank: String) -> Bool {
        Int(rank).map { $0 <= topRankLine } ?? false
    }

    private static func rankText(_ rank: String) -> String { rank == "-" ? "순위 밖" : "\(rank)위" }
}

/// 처음 보는 칸 · 앱의 기준선을 잡는다. 저장된 허브를 다 들인 뒤에만 — 들이는 도중의 빈
/// 말("확인 전")을 기준선으로 삼으면 다 들인 순간 모든 칸에 뱃지가 선다.
struct SectionChangesBaseline: ViewModifier {
    @EnvironmentObject private var store: FeedbackStore
    let metrics: SectionMetrics
    @State private var isRestored = false

    func body(content: Content) -> some View {
        content
            .task {
                await store.awaitRestore()
                isRestored = true
            }
            .onChange(of: isRestored ? SectionChanges.allSignatures(metrics: metrics) : [:], initial: true) { _, signatures in
                SectionChanges.shared.adoptBaselines(signatures)
            }
    }
}

/// 칸 맨 위의 띠 — 지난번 본 뒤 무엇이 바뀌었나. 사이드바 뱃지를 눌러 들어온 사람이 무엇을
/// 봐야 하는지 여기서 안다. 전체 앱이면 줄을 눌러 그 앱으로 간다.
struct SectionChangesBanner: View {
    @EnvironmentObject private var store: FeedbackStore
    @ObservedObject private var changes = SectionChanges.shared
    let section: FeedbackStore.ProjectSection
    let project: String?

    private static let shownLimit = 6
    /// 띠는 화면 위에 붙어 있어 그만큼 스크롤할 자리를 먹는다. 처음엔 한 줄만, 펼치면 전부.
    @State private var isExpanded = false
    /// 펼친 줄들의 실제 높이. 이보다 크면 띠 안에서 스크롤한다 — 릴리즈처럼 줄이 긴 칸에서
    /// 펼친 띠가 창 높이를 넘어 아래 화면을 0까지 눌러 버렸다.
    @State private var rowsHeight: CGFloat = 0
    private static let maxExpandedHeight: CGFloat = 280

    var body: some View {
        let items = changes.recentChanges(section, project: project)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("지난번 본 뒤 바뀐 것" + (items.count > 1 ? " \(items.count)개" : ""), systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer(minLength: 8)
                    if items.count > 1 || lineCount(items[0]) > 1 {
                        Button(isExpanded ? "접기" : "펼치기") { isExpanded.toggle() }
                            .buttonStyle(.borderless)
                            .font(.body)
                    }
                    Button("확인") { changes.dismiss(section, project: project) }
                        .buttonStyle(.borderless)
                        .font(.body)
                }
                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items.prefix(Self.shownLimit), id: \.project) { item in
                                row(item)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    .frame(height: min(max(rowsHeight, 1), Self.maxExpandedHeight))
                } else if let first = items.first {
                    row(first)
                }
                if isExpanded, items.count > Self.shownLimit {
                    Text("외 \(items.count - Self.shownLimit)개 앱")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func lineCount(_ item: SectionChanges.Change) -> Int {
        SectionChanges.lines(section, before: item.before, after: item.after).count
    }

    @ViewBuilder
    private func row(_ item: SectionChanges.Change) -> some View {
        let all = SectionChanges.lines(section, before: item.before, after: item.after)
        let lines = isExpanded ? all : Array(all.prefix(1))
        let text = VStack(alignment: .leading, spacing: 2) {
            if project == nil {
                Text(store.displayName(for: item.project))
                    .font(.body.weight(.semibold))
            }
            ForEach(Array(lines.prefix(5).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.body.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }
            if lines.count > 5 {
                Text("외 \(lines.count - 5)개")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if project == nil {
            Button { store.open(project: item.project, section: section) } label: {
                HStack {
                    text
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            text
        }
    }
}

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
//  달라진 앱을 센다. 말의 꼴이 그대로이고 숫자만 움직였으면 15% 넘게 움직인 것만 센다
//  (`notableShift`) — 설치 120대가 121대가 될 때마다 뱃지가 서면 뱃지가 아무 말도 하지 않는다.
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
    private static let releaseAckKey = "release-red-acknowledged"

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

    /// 지금 보고 있는 칸에서, 열었을 때 바뀌어 있던 앱과 그 수. 열자마자 본 것으로 넘어가
    /// 뱃지가 사라져도 앱 목록 줄에는 이 수가 남는다 — 사이드바에서 3을 보고 들어왔으면 그
    /// 칸에서 3이 보여야 한다. 기기 메모리에만 두고, 다른 칸을 열거나 띠의 "확인" 으로 비운다.
    struct Visit: Equatable {
        let section: String
        var counts: [String: Int]
    }

    @Published private(set) var visit: Visit?

    /// "칸|앱" → 마지막으로 본 말.
    @Published private var seen: [String: String]

    /// 읽음으로 넘긴 릴리즈 빨강 — "앱|버전". 같은 버전이 빨강인 동안은 뱃지를 다시 달지
    /// 않고, 새 버전이 빨강이 되면 다시 단다. 빨강 점 · 판정은 그대로다.
    @Published private var acknowledgedRed: Set<String>

    private init() {
        seen = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        recent = (UserDefaults.standard.data(forKey: Self.recentKey))
            .flatMap { try? JSONDecoder().decode([String: Change].self, from: $0) } ?? [:]
        acknowledgedRed = Set(UserDefaults.standard.stringArray(forKey: Self.releaseAckKey) ?? [])
    }

    // MARK: - 릴리즈 빨강

    static func redKey(_ project: String, store: FeedbackStore) -> String? {
        guard let report = store.releaseHealth(for: project), report.verdict.level == .red else { return nil }
        return "\(project)|\(report.latest.version)"
    }

    /// 아직 읽음으로 넘기지 않은 빨강인 앱.
    func unacknowledgedRed(_ projects: [String], store: FeedbackStore) -> [String] {
        projects.filter { Self.redKey($0, store: store).map { !acknowledgedRed.contains($0) } ?? false }
    }

    func acknowledgeRed(_ projects: [String], store: FeedbackStore) {
        let keys = projects.compactMap { Self.redKey($0, store: store) }
        // 빨강이 아닌 앱의 옛 기록은 지운다 — 다시 빨강이 되면 다시 알리게.
        let live = Set(Self.appKeys(store).compactMap { Self.redKey($0, store: store) })
        let next = acknowledgedRed.intersection(live).union(keys)
        guard next != acknowledgedRed else { return }
        acknowledgedRed = next
        UserDefaults.standard.set(Array(next), forKey: Self.releaseAckKey)
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

    /// 열어 봤다 — 지금 말을 본 것으로. 달라져 있던 것은 띠에 남긴다. `visiting` 이면 칸을
    /// 실제로 연 것이라 바뀌어 있던 앱을 `visit` 에도 적는다("모두 읽음" 은 열지 않은 것).
    func markSeen(_ section: FeedbackStore.ProjectSection, signatures: [String: String], visiting: Bool = false) {
        var next = seen
        var nextRecent = recent
        var nextVisit = visit?.section == section.rawValue ? visit! : Visit(section: section.rawValue, counts: [:])
        for (project, signature) in signatures {
            let key = Self.key(section, project)
            if let old = seen[key], old != signature {
                let weight = Self.weight(section, before: old, after: signature)
                if weight > 0 { nextVisit.counts[project, default: 0] += weight }
                // 확인 안 한 바뀜이 또 바뀌면 처음 말부터 지금 말까지 한 줄로.
                let before = nextRecent[key]?.before ?? old
                nextRecent[key] = before == signature ? nil
                    : Change(section: section.rawValue, project: project, before: before, after: signature, at: Date())
            }
            next[key] = signature
        }
        if visiting, nextVisit != visit { visit = nextVisit }
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

    /// 이 칸을 열었을 때 바뀌어 있던 것의 수(한 앱이면 그 앱만). 앱 목록 줄의 뱃지가 쓴다.
    func visitedCount(_ section: FeedbackStore.ProjectSection, project: String?) -> Int {
        guard let visit, visit.section == section.rawValue else { return 0 }
        return project.map { visit.counts[$0] ?? 0 } ?? visit.counts.values.reduce(0, +)
    }

    /// 띠의 "확인".
    func dismiss(_ section: FeedbackStore.ProjectSection, project: String?) {
        let items = recentChanges(section, project: project)
        if var next = visit, next.section == section.rawValue {
            for item in items { next.counts[item.project] = nil }
            if project == nil { next.counts = [:] }
            visit = next
        }
        let keys = items.map { Self.key(section, $0.project) }
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
        let key = SectionMetrics.memoKey(section, project)
        if let cached = metrics.memo.signatures[key] { return cached }
        let projects = project.map { [$0] } ?? appKeys(metrics.store)
        let value = Dictionary(uniqueKeysWithValues: projects.map {
            ($0, signature(section, project: $0, metrics: metrics))
        })
        metrics.memo.signatures[key] = value
        return value
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
            return total + Self.weight(section, before: old, after: entry.value)
        }
    }

    /// 바뀜 하나가 뱃지에서 몇인가. 키워드는 10위 선을 넘나든 것마다, 숫자 칸은 15% 넘게
    /// 움직였을 때만 하나, 릴리즈 · 앱 내 구입은 말이 바뀌면 하나. 뱃지 · 띠 · 앱 목록이 같은 셈을 쓴다.
    static func weight(_ section: FeedbackStore.ProjectSection, before: String, after: String) -> Int {
        guard before != after else { return 0 }
        let lines = lines(section, before: before, after: after).count
        return section == .release || section == .purchases ? max(1, lines) : lines
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
            guard let shift = notableShift(before: before, after: after) else { return [] }
            return ["\(before) → \(after)" + shift]
        }
    }

    /// 숫자가 이만큼은 움직여야 뱃지가 선다.
    static let notableRatio = 0.15

    /// 말이 볼 만큼 바뀌었나. 숫자를 뺀 꼴이 다르면(확인 전 → 설치 120대, 새 나라) 그것만으로
    /// 바뀐 것이고 덧붙일 말은 "". 꼴이 같으면 15% 넘게 움직인 숫자가 있을 때만 — 가장 크게
    /// 움직인 것을 " (+17%)" 로 붙인다. 볼 만하지 않으면 nil.
    static func notableShift(before: String, after: String) -> String? {
        let old = numbers(before), new = numbers(after)
        guard old.skeleton == new.skeleton, old.values.count == new.values.count else { return "" }
        let ratios = zip(old.values, new.values).map { was, now -> Double in
            if was == now { return 0 }
            return was == 0 ? .infinity : (now - was) / abs(was)
        }
        guard let largest = ratios.max(by: { abs($0) < abs($1) }), abs(largest) >= notableRatio else { return nil }
        guard largest.isFinite else { return "" }
        let percent = Int((largest * 100).rounded())
        return " (\(percent > 0 ? "+" : "−")\(abs(percent))%)"
    }

    /// "설치 1,234대 · 7일 56명" → 꼴 "설치 #대 · 7일 #명", 숫자 [1234, 7, 56].
    private static func numbers(_ text: String) -> (skeleton: String, values: [Double]) {
        var skeleton = "", values: [Double] = [], digits = ""
        func flush() {
            guard !digits.isEmpty else { return }
            values.append(Double(digits.replacingOccurrences(of: ",", with: "")) ?? 0)
            skeleton += "#"
            digits = ""
        }
        for character in text {
            // 쉼표 · 점은 숫자 사이에 있을 때만 숫자의 일부다.
            if character.isASCII, character.isNumber || (!digits.isEmpty && (character == "," || character == ".")) {
                digits.append(character)
            } else {
                // "1,234," 처럼 숫자 끝에 붙은 쉼표는 말로 돌려 준다.
                var tail = ""
                while let last = digits.last, last == "," || last == "." { tail.insert(digits.removeLast(), at: tail.startIndex) }
                flush()
                skeleton += tail + String(character)
            }
        }
        flush()
        return (skeleton, values)
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

/// 이 화면을 열 때 새것이던 항목의 id(진단 · 리뷰). 열자마자 본 것으로 넘어가 뱃지가 사라져도
/// 이번에 보는 동안은 줄마다 "새" 가 남는다 — `ProjectSectionView` 가 채운다.
private struct FreshItemIDsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var freshItemIDs: Set<String> {
        get { self[FreshItemIDsKey.self] }
        set { self[FreshItemIDsKey.self] = newValue }
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
    /// 접어 둔 띠에도 이만큼은 다 보인다 — 뱃지 3을 보고 들어왔는데 한 줄만 보이면 나머지를 못 찾는다.
    private static let collapsedLimit = 3
    /// 띠는 화면 위에 붙어 있어 그만큼 스크롤할 자리를 먹는다. 처음엔 한 줄만, 펼치면 전부.
    @State private var isExpanded = false
    /// 펼친 줄들의 실제 높이. 이보다 크면 띠 안에서 스크롤한다 — 릴리즈처럼 줄이 긴 칸에서
    /// 펼친 띠가 창 높이를 넘어 아래 화면을 0까지 눌러 버렸다.
    @State private var rowsHeight: CGFloat = 0
    private static let maxExpandedHeight: CGFloat = 280

    var body: some View {
        let items = changes.recentChanges(section, project: project)
        if !items.isEmpty {
            let total = items.reduce(0) { $0 + SectionChanges.weight(section, before: $1.before, after: $1.after) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("지난번 본 뒤 바뀐 것" + (total > 1 ? " \(total)개" : ""), systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer(minLength: 8)
                    if items.count > Self.collapsedLimit {
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
                } else {
                    ForEach(items.prefix(Self.collapsedLimit), id: \.project) { item in
                        row(item)
                    }
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

    @ViewBuilder
    private func row(_ item: SectionChanges.Change) -> some View {
        let lines = SectionChanges.lines(section, before: item.before, after: item.after)
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

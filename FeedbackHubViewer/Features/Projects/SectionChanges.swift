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

    /// "칸|앱" → 마지막으로 본 말.
    @Published private var seen: [String: String]

    private init() {
        seen = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
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

    /// 열어 봤다 — 지금 말을 본 것으로.
    func markSeen(_ section: FeedbackStore.ProjectSection, signatures: [String: String]) {
        var next = seen
        for (project, signature) in signatures { next[Self.key(section, project)] = signature }
        guard next != seen else { return }
        seen = next
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(seen, forKey: Self.defaultsKey)
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

    /// 본 뒤 바뀐 앱들.
    func changedApps(_ section: FeedbackStore.ProjectSection, project: String?,
                     metrics: SectionMetrics) -> [String] {
        guard Self.tracked.contains(section) else { return [] }
        return Self.signatures(section, project: project, metrics: metrics)
            .filter { isChanged(section, project: $0.key, signature: $0.value) }
            .map(\.key)
    }
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

//
//  QualityBoard.swift
//  FeedbackHubViewer
//
//  홈의 세 번째 얼굴 — "쓰는 사람이 겪는 것이 멀쩡한가". 앱마다 안정성 · 실행 속도 · 멈춤 ·
//  만족도 · 지원 응답 · 핵심 기능 · 온보딩 · 기기 테스트 · 커버리지를 기준과 견주고,
//  가장 나쁜 항목이 종합이 된다. 나쁜 앱부터.
//
//  판정은 `AppQuality` 가 한다(순수 함수). 여기는 재료를 모으고 그린다.
//  재료: 릴리즈 건강(`ReleaseHealth` — 크래시 없는 설치 · MetricKit 성능 한 줄) · 스토어 별점 ·
//  피드백 처리 여부 · 일 버킷의 온보딩 이벤트 · 레포 폴더의 테스트 결과(`docs/*.json`).
//  새로 셈하지 않고 다른 칸이 쓰는 값을 그대로 읽는다(온보딩만 `FeedbackStore.onboarding(for:)`).
//

import SwiftUI

struct QualityBoard: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    @State private var filter: AppQuality.Grade?

    private var apps: [String] { SectionMetrics.keywordProjects(store) }

    var body: some View {
        let ranked = AppQuality.rank(apps.map(input))
        let shown = filter.map { grade in ranked.filter { $0.grade == grade } } ?? ranked

        VStack(alignment: .leading, spacing: 16) {
            conclusion(ranked)
            filterBar(ranked)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360, maximum: 560), spacing: 14)], spacing: 14) {
                ForEach(shown) { app in
                    Button {
                        store.open(project: app.input.project, section: section(for: app))
                    } label: {
                        card(app)
                    }
                    .buttonStyle(.plain)
                }
            }
            footnote
        }
        .task(id: apps) { await icons.resolve(apps, keywords: keywords) }
    }

    // MARK: - 재료

    private func input(_ project: String) -> AppQuality.Input {
        var input = AppQuality.Input(project: project, name: store.displayName(for: project))
        input.active7 = store.usage(for: project).activeInstalls7

        if let stability = store.qualityStability(for: project) {
            input.crashFree = stability.rate
            input.crashFreeIsEstimate = stability.isEstimate
            input.crashVersion = stability.version
        }

        let versions = store.releaseHealth(for: project).map { $0.recent.isEmpty ? [$0.latest] : $0.recent } ?? []
        if let version = versions.first(where: { ($0.performance?.samples ?? 0) >= ReleaseHealth.performanceMinSamples }) {
            input.launchMs = version.performance?.launchMs
            input.hangPerHour = version.performance?.hangPerHour
            input.performanceVersion = "\(version.version) 버전"
        } else if let pooled = recentPerformance(project), pooled.samples >= ReleaseHealth.performanceMinSamples {
            // 한 버전에 다섯 장이 안 모이는 앱 — 버전을 자주 내면 늘 그렇다. 최근 30일 모든 버전의 가운데 값.
            input.launchMs = pooled.launchMs
            input.hangPerHour = pooled.hangPerHour
            input.performanceVersion = "최근 30일 \(pooled.samples)대"
        }

        if let report = store.releaseHealth(for: project) {
            let minInstalls = report.spec.thresholds.minInstallsForVerdict
            if let action = report.spec.coreAction {
                let recent = report.recent.isEmpty ? [report.latest] + [report.previous].compactMap { $0 } : report.recent
                input.core = .init(label: action.label, versions: recent,
                                   dropMax: report.spec.thresholds.coreActionDropMax, minInstalls: minInstalls)
            }
        }

        input.onboarding = store.onboarding(for: project)
        input.coverage = keywords.testCoverage[project.lowercased()]

        input.deviceTest = keywords.deviceTests[project.lowercased()]

        if let world = keywords.worldRating(for: project) {
            input.rating = world.average
            input.ratingCount = world.count
            input.ratingCountries = world.countries
        } else if let app = keywords.storeApp(for: project) {
            input.rating = app.averageRating
            input.ratingCount = app.ratingCount
        }

        // 최근 90일, 받은 지 3일이 지난 피드백 — 막 온 것은 아직 답할 차례가 아니다. 설문 응답은 뺀다.
        let now = Date()
        let support = store.feedback(for: project).filter { item in
            guard !item.isVoice, let created = item.createdAt else { return false }
            return created >= now.addingTimeInterval(-90 * 86_400) && created <= now.addingTimeInterval(-3 * 86_400)
        }
        input.supportTotal = support.count
        input.supportHandled = support.filter(store.isHandled).count
        return input
    }

    /// 최근 30일 이 앱의 성능 한 줄들(모든 버전). 한 장도 없으면 nil.
    private func recentPerformance(_ project: String) -> ReleaseHealth.Performance? {
        let since = Date().addingTimeInterval(-30 * 86_400)
        return ReleaseHealth.Performance(store.allMetrics.filter {
            $0.projectKey == project && ($0.happenedAt ?? .distantPast) >= since
        })
    }

    /// 가장 나쁜 항목을 고칠 칸으로.
    private func section(for app: AppQuality) -> FeedbackStore.ProjectSection {
        switch app.worst?.dimension {
        case .stability?: return .crashes
        case .rating?: return .reviews
        case .support?: return .feedback
        case .onboarding?: return .stats
        case .launch?, .hang?, .core?, .deviceTest?, .coverage?, nil: return .release
        }
    }

    // MARK: - 결론

    private func conclusion(_ ranked: [AppQuality]) -> some View {
        let counts = Dictionary(grouping: ranked, by: \.grade).mapValues(\.count)
        let parts = [AppQuality.Grade.bad, .warning, .good].compactMap { grade in
            counts[grade].map { "\(grade.label) \($0)개" }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(parts.isEmpty ? "아직 품질을 잴 만한 숫자가 모이지 않았습니다." : parts.joined(separator: " · "))
                .font(.title3.weight(.semibold))
            if let first = ranked.first, first.grade == .bad, let worst = first.worst {
                Label("먼저 볼 앱: \(first.input.name) — \(worst.dimension.rawValue) \(worst.value)",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
    }

    // MARK: - 거르기

    private func filterBar(_ ranked: [AppQuality]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, count: ranked.count)
                ForEach(AppQuality.Grade.allCases) { grade in
                    let count = ranked.filter { $0.grade == grade }.count
                    if count > 0 { chip(grade, count: count) }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ grade: AppQuality.Grade?, count: Int) -> some View {
        let isOn = filter == grade
        let title = grade?.label ?? "전체"
        let tint = grade.map(Self.tint) ?? .accentColor
        return Button {
            filter = isOn ? nil : grade
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text(AppFormat.count(count))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
            .font(.body)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary.opacity(0.6))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), 앱 \(count)개")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static func tint(_ grade: AppQuality.Grade) -> Color {
        switch grade {
        case .good: return .green
        case .warning: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }

    // MARK: - 카드

    private func card(_ app: AppQuality) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIcon(url: icons.url(for: app.input.project, keywords: keywords), size: 36)
                Text(app.input.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Tag(text: app.grade.label, tint: app.grade == .unknown ? nil : Self.tint(app.grade), isCompact: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(app.scores) { score in row(score) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.45)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func row(_ score: AppQuality.Score) -> some View {
        let isKnown = score.grade != .unknown
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: score.dimension.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(score.dimension.rawValue)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(score.value)
                .font(.body.monospacedDigit().weight(score.grade == .bad ? .semibold : .regular))
                .foregroundStyle(isKnown ? AnyShapeStyle(Self.tint(score.grade)) : AnyShapeStyle(.tertiary))
            if let basis = score.basis {
                Text(basis)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.body)
        .help(score.dimension.standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(score.dimension.rawValue) \(score.value), \(score.grade.label)")
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("틀은 ISO/IEC 25010 의 신뢰성 · 성능 효율성 · 사용 품질 · 기능 적합성 · 유지보수성입니다. 종합은 가장 나쁜 항목을 따릅니다.")
            ForEach(AppQuality.Dimension.allCases) { dimension in
                Text("\(dimension.rawValue): \(dimension.standard)")
            }
            Text("기기 테스트 · 커버리지는 scripts/device-qa.py · scripts/test-coverage.py 가 workspace/Auto/docs 에 쓴 결과입니다(맥이 그 폴더에서 읽어 아이폰에도 나눕니다).")
            Text("핵심 기능은 릴리즈 건강의 핵심 행동(스펙 coreAction, 없으면 통계에서 고른 가치 행동), 온보딩은 지난 30일 새 설치가 onboarding_completed · _skipped 같은 이벤트를 보냈는지입니다.")
            Text("안정성은 설치가 판정할 만큼 모인 가장 새 버전(그 버전의 전 기간 설치), 성능은 다섯 대가 모인 가장 새 버전이고 없으면 최근 30일 모든 버전, 만족도는 모든 나라 가게의 별점을 합친 것, 지원 응답은 최근 90일 중 받은 지 3일 지난 피드백입니다.")
        }
        .font(.body)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

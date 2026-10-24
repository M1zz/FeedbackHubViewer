//
//  ExperienceView.swift
//  FeedbackHubViewer
//
//  경험 칸 — 앱마다 사용자가 꿈꿀 수 있는 모습이 맨 위, 그 아래 앱이 줘야 하는 경험과
//  누구의 어떤 순간을 푸는 앱인가. 숫자를 보다가 "이 앱이 원래 뭘 하려던 거였지" 를 다시
//  붙잡는 자리다. 정의가 빠진 앱은 빠졌다고 말한다.
//

import SwiftUI

struct ExperienceView: View {
    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @EnvironmentObject private var design: DesignDocsStore
    @ObservedObject private var portfolio = PortfolioStore.shared
    @ObservedObject private var icons = StoreIcons.shared
    /// nil == 전체 앱.
    let project: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let project {
                    appContent(project)
                } else {
                    overview
                }
            }
            .padding(Platform.cardPadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: design.workspace) {
            await portfolio.load(workspace: design.workspace)
        }
    }

    // MARK: - 한 앱

    @ViewBuilder
    private func appContent(_ project: String) -> some View {
        let experience = AppExperience.of(project)
        // 출처가 틀린 것으로 확인된 앱은 그 출처를 쓰지 않는다(`AppExperience.sourceNote`).
        let vision = experience?.skipVision == true ? nil : portfolio.app(for: project)?.vision
        let showcase = experience?.skipShowcase == true ? nil : portfolio.showcase(for: project)

        // 꿈꾸는 모습 — 이 칸의 요점이라 카드 틀 없이 크게.
        VStack(alignment: .leading, spacing: 10) {
            Label("사용자가 꿈꿀 수 있는 모습", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.tint)
            if let experience {
                Text(experience.dream)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let scene = experience.scene {
                    Text(scene)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("아직 그려 두지 않았어요.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

        Card(title: "사용자에게 줘야 하는 경험", systemImage: "heart.text.square") {
            if let core = vision?.coreValue {
                Text(core)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            let goals = vision?.userExperienceGoals ?? []
            let promises = experience?.promises ?? []
            if goals.isEmpty && promises.isEmpty {
                Text("정의된 경험이 없어요.").font(.body).foregroundStyle(.secondary)
            }
            ForEach(promises, id: \.self) { promise in
                Label(promise, systemImage: "checkmark.circle")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !goals.isEmpty {
                Text("경험 목표 (app-portfolio vision)")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(goals, id: \.self) { goal in
                    Label(goal, systemImage: "target")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let avoid = experience?.avoid, !avoid.isEmpty {
                Text("주면 안 되는 경험")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(avoid, id: \.self) { item in
                    Label(item, systemImage: "xmark.octagon")
                        .font(.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let principles = vision?.designPrinciples, !principles.isEmpty {
                DisclosureGroup("디자인 원칙 \(principles.count)개") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(principles, id: \.self) { Text("· \($0)").font(.body) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.body)
            }
        }

        Card(title: "누구의 어떤 순간", systemImage: "person.crop.circle") {
            if showcase == nil && vision?.targetUsers == nil {
                Text("app-portfolio 에 이 앱의 소개(showcase)가 없어요.")
                    .font(.body).foregroundStyle(.secondary)
            }
            if let persona = showcase?.persona { row("페르소나", persona) }
            if let users = vision?.targetUsers ?? showcase?.stakeholders { row("누가 쓰나", users) }
            if let context = showcase?.context { row("그 순간", context) }
            if let problem = showcase?.problem { row("문제", problem) }
            if let solution = showcase?.solution { row("이 앱이 하는 일", solution) }
            if let highlight = showcase?.highlight ?? vision?.uniqueSellingPoint { row("다른 점", highlight) }
        }

        if let note = experience?.sourceNote {
            Label(note, systemImage: "exclamationmark.triangle")
                .font(.body)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if experience != nil {
            Text("꿈꾸는 모습 · 줘야 하는 경험 · 주면 안 되는 경험은 app-portfolio 의 소개와 vision, 앱 리포의 스토어 문구를 근거로 쓴 초안이에요.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 전체 앱

    private var overview: some View {
        let keys = store.projectCounts.map(\.key).filter { $0 != Feedback.unclassifiedProject }
        let missing = keys.filter { AppExperience.of($0) == nil }
        return VStack(alignment: .leading, spacing: 12) {
            Text("앱마다 사용자가 꿈꿀 수 있는 모습")
                .font(.title2.weight(.bold))
            if !missing.isEmpty {
                Text("아직 그려 두지 않은 앱 \(missing.count)개: " + missing.map { store.displayName(for: $0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(keys.filter { AppExperience.of($0) != nil }, id: \.self) { key in
                Button { store.open(project: key, section: .experience) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        AppIcon(url: icons.url(for: key, keywords: keywords), size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.displayName(for: key)).font(.headline)
                            Text(AppExperience.of(key)?.dream ?? "")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

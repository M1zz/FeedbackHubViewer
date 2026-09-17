//
//  MonetizationCards.swift
//  FeedbackHubViewer
//
//  수익 설계를 관측하는 세 카드 — 쐐기 · 잠재 고객 · 설계된 순간.
//  계산과 그 이유는 `FeedbackStore+Monetization.swift` 머리말에 있다.
//
//  이 화면이 지키는 규칙 하나: **값을 말하지 않는다.** 가격은 App Store Connect가
//  진실이고 여기 오는 것은 설치가 보낸 지표뿐이라, 값을 적어 두면 대조할 상대
//  없이 숫자만 그럴듯해진다. 여기서 말하는 것은 값이 서 있을 땅이 있는가다.
//

import SwiftUI

struct MonetizationCards: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String?

    var body: some View {
        if let money = store.monetization(for: project), !money.isEmpty {
            if let activation = money.activation { ActivationCard(activation: activation) }
            if let prospects = money.prospects { ProspectsCard(prospects: prospects) }
            if !money.moments.isEmpty {
                MomentsCard(moments: money.moments, lacksOutcomeEvents: money.lacksOutcomeEvents,
                            note: money.note)
            }
        }
    }
}

// MARK: - 쐐기

/// 설치에서 가치를 받은 상태까지 몇이 오는가.
///
/// 이 카드가 수익 카드 중 맨 위인 이유: 가치를 못 받은 사람에게는 어떤 값도
/// 비싸다. 여기 숫자가 낮으면 가격표를 고칠 일이 아니라 제품을 고칠 일이다.
private struct ActivationCard: View {
    let activation: FeedbackStore.Monetization.Activation

    var body: some View {
        Card(title: activation.title, systemImage: "figure.walk.arrival") {
            VStack(spacing: 8) {
                ForEach(activation.steps) { step in
                    SpecBar(label: step.label,
                            value: step.isMissing ? "—" : "\(step.installs)명",
                            ratio: step.ratio,
                            hint: hint(for: step),
                            tint: step.isMissing ? Color.secondary.opacity(0.25) : .accentColor,
                            isMuted: step.isMissing)
                }
            }
            if let verdict { notice(verdict) }
            if let note = activation.note { Footnote(note) }
        }
    }

    private func hint(for step: FeedbackStore.Monetization.Step) -> String {
        // 안 보내는 지표와 0명을 갈라 말한다 — 고칠 곳이 다르다.
        if step.isMissing {
            return "이 칸을 재는 지표를 앱이 아직 안 보냅니다. 0명이 아니라 못 셉니다."
        }
        var parts = ["전체의 \(percent(step.ratio))"]
        if let previous = step.fromPrevious {
            parts.append("앞 칸의 \(percent(previous))가 여기까지")
        }
        if let hint = step.hint { parts.append(hint) }
        return parts.joined(separator: " · ")
    }

    /// 앱이 스스로 그어 둔 선과 견준 한 줄. 선이 있어야 7%가 "낮다"가 아니라
    /// "기준의 7분의 1"로 읽힌다.
    private var verdict: String? {
        guard let reached = activation.reached, let last = activation.steps.last,
              !last.isMissing else { return nil }
        if let floor = activation.floor, reached < floor {
            var text = "마지막 칸이 \(percent(reached))입니다. 이 앱이 정해 둔 하한 \(percent(floor)) 아래예요 — "
                     + "그 문서가 말하는 대로라면 여기는 가격이 아니라 제품 문제입니다."
            if let worst = activation.worstDrop, let drop = worst.fromPrevious {
                text += " 제일 크게 새는 칸은 \"\(worst.label)\"이고, 앞 칸의 \(percent(drop))만 넘어옵니다."
            }
            return text
        }
        if let target = activation.target, reached < target {
            return "마지막 칸이 \(percent(reached))로 목표 \(percent(target))에 못 미칩니다."
        }
        return nil
    }
}

// MARK: - 잠재 고객

/// 값을 낼 이유가 생긴 사람이 몇인가.
///
/// 순서가 곧 결제와의 거리다. 맨 위가 지금 막혀 있는 사람이고, 맨 아래 둘은
/// 팔 대상이 아닌 사람 — 이미 열렸거나, 권한을 못 읽는 설치다.
private struct ProspectsCard: View {
    let prospects: FeedbackStore.Monetization.Prospects

    var body: some View {
        Card(title: prospects.title, systemImage: "person.badge.clock") {
            VStack(spacing: 8) {
                row("지금 막혀 있음", prospects.blocked, .orange,
                    "\(prospects.label) \(prospects.limit)개를 다 썼는데 유료 기능이 안 열린 설치. 값을 낼 이유가 지금 있는 사람입니다")
                row("곧 막힘", prospects.nearing, .yellow,
                    "한도까지 얼마 안 남은 설치")
                row("아직 여유", prospects.roomLeft, .secondary,
                    "쓰고는 있지만 한도가 아직 먼 설치")
                row("아직 시작 안 함", prospects.notStarted, .secondary,
                    "\(prospects.label)를 하나도 안 만든 설치. 값을 낼 이유가 아직 없습니다")
                Divider().padding(.vertical, 2)
                row("팔 대상 아님 (이미 열림)", prospects.alreadyOpen, .secondary,
                    "유료 기능이 이미 열려 있어 값을 낼 이유가 없는 설치")
                if prospects.unknown > 0 {
                    row("모름", prospects.unknown, .secondary, "권한을 안 보내는 설치")
                }
            }
            if let headline { notice(headline) }
            if let note = prospects.note { Footnote(note) }
        }
    }

    private func row(_ label: String, _ count: Int, _ tint: Color, _ hint: String) -> some View {
        SpecBar(label: label,
                value: "\(count)명",
                ratio: prospects.scanned > 0 ? Double(count) / Double(prospects.scanned) : 0,
                hint: hint,
                tint: tint,
                isMuted: count == 0)
    }

    /// 이 카드의 결론 한 줄. 팔 모수가 전체에 견줘 얼마나 작은지를 말한다 —
    /// 그 수가 작으면 손댈 곳은 가격표가 아니라 그 위다.
    private var headline: String? {
        guard prospects.scanned > 0 else { return nil }
        let sellable = prospects.prospects
        var text = "지금 값을 낼 이유가 있는 사람은 \(prospects.scanned)대 중 \(sellable)명"
        if let ratio = prospects.prospectRatio { text += "(\(percent(ratio)))" }
        text += "입니다."
        if prospects.alreadyOpen > sellable * 5, prospects.alreadyOpen > 0 {
            text += " 유료 기능이 이미 열린 설치가 \(prospects.alreadyOpen)대로 그보다 훨씬 많아요 — "
                  + "가격표보다 먼저, 그 권한이 어떻게 열렸는지를 보셔야 합니다."
        }
        return text
    }
}

// MARK: - 설계된 순간

/// 결제 화면이 뜨기로 설계된 자리마다, 실제로 떴는가.
private struct MomentsCard: View {
    let moments: [FeedbackStore.Monetization.Moment]
    let lacksOutcomeEvents: Bool
    let note: String?

    var body: some View {
        Card(title: "결제 화면이 뜬 순간", systemImage: "rectangle.on.rectangle.angled") {
            VStack(spacing: 8) {
                ForEach(moments) { moment in
                    SpecBar(label: moment.label,
                            value: moment.isMissing ? "—" : "\(moment.shown)명",
                            ratio: ratio(moment),
                            hint: hint(for: moment),
                            tint: moment.isMissing ? Color.secondary.opacity(0.25) : .accentColor,
                            isMuted: moment.isMissing)
                }
            }
            if let verdict { notice(verdict) }
            if let note { Footnote(note) }
        }
    }

    /// 막대는 **가장 많이 뜬 순간** 대비다. 설치 대비로 그리면 전부 0에 붙어
    /// 어느 벽이 그나마 서 있는지가 안 보인다.
    private func ratio(_ moment: FeedbackStore.Monetization.Moment) -> Double {
        let top = moments.map(\.shown).max() ?? 0
        return top > 0 ? Double(moment.shown) / Double(top) : 0
    }

    private func hint(for moment: FeedbackStore.Monetization.Moment) -> String {
        if moment.isMissing {
            return "이 벽은 아직 한 번도 안 섰습니다 — \(moment.event)가 한 건도 안 왔어요. "
                 + "아무도 안 온 게 아니라 코드에 그 자리가 없거나, 조건에 닿는 사람이 없는 겁니다."
        }
        var parts: [String] = []
        if let tapped = moment.tapped { parts.append("누름 \(tapped)명") }
        if let purchased = moment.purchased { parts.append("결제 \(purchased)명") }
        if let note = moment.note { parts.append(note) }
        return parts.isEmpty ? moment.event : parts.joined(separator: " · ")
    }

    private var verdict: String? {
        let standing = moments.filter { !$0.isMissing }
        if standing.isEmpty {
            return "설계한 벽 \(moments.count)개가 하나도 안 섰습니다. 값을 고치기 전에 "
                 + "이 화면들이 실제로 뜨는지부터 보셔야 해요."
        }
        if lacksOutcomeEvents {
            return "누름·결제를 셀 이벤트 기본형이 스펙에 없어서, 뜬 횟수까지만 셉니다. "
                 + "스펙에 tappedEvent·purchasedEvent를 적으면 벽마다 성과가 갈립니다."
        }
        return nil
    }
}

// MARK: - 조각

/// 카드 안의 한 줄짜리 결론. 경고가 아니라 읽을 거리라 색을 죽여 둔다.
private func notice(_ text: String) -> some View {
    Label(text, systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
}

private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func percent(_ ratio: Double) -> String {
    String(format: "%.1f%%", ratio * 100)
}

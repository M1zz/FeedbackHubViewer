//
//  HabitCard.swift
//  FeedbackHubViewer
//
//  "습관" 카드의 몸통 — 사용 주기 · 가치 행동 고르기, 주 지표와 고착도(지금 · 4주 전),
//  L28 분포(power user curve). 판정 문장은 위에서 `AnalyzedCard` 가 `StatsAnalysis.stickiness`
//  로 그린다. 계산은 `FeedbackStore+Habit.swift`.
//
//  그리고 "세 질문" 카드 — 습관이 되었나(고착도) · 남는 사람이 있나(코호트 잔존) ·
//  남은 사람이 가치를 느끼나(유료). 세 지표가 각각 무엇에 답하는지를 한 장에 나란히 둔다.
//

import SwiftUI
import Charts

struct HabitCardBody: View {
    @EnvironmentObject private var store: FeedbackStore
    let project: String
    let habit: FeedbackStore.Habit

    private var definition: ActivityDefinition { store.activityDefinition(for: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cyclePicker
            valueEventPicker
            if !habit.isEmpty {
                figures
                curveChart
            }
        }
    }

    // MARK: 정의

    private var cyclePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이 앱은 얼마나 자주 쓰여야 하나요?")
                .font(.headline)
            Picker("사용 주기", selection: Binding(
                get: { definition.cycle },
                set: { cycle in
                    var next = definition
                    next.cycle = cycle
                    store.setActivityDefinition(next, for: project)
                })) {
                ForEach(UsageCycle.allCases) { cycle in
                    Text("\(cycle.label) (\(cycle.metricName))").tag(Optional(cycle))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(definition.cycle.map { "\($0.example). 주 지표는 \($0.metricName)입니다." }
                 ?? "정하면 그 주기에 맞는 지표로 판정합니다. 주간 회고 앱을 DAU로 재면 잘 되는데도 실패처럼 보여요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueEventPicker: some View {
        let candidates = store.valueEventCandidates(for: project).prefix(40)
        let chosen = Set(definition.valueEvents)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("무엇을 해야 \"썼다\"고 치나요?")
                    .font(.headline)
                Spacer(minLength: 8)
                Menu {
                    Button {
                        update(valueEvents: [])
                    } label: {
                        checkLabel("아무 이벤트 (앱 실행 포함)", isOn: chosen.isEmpty)
                    }
                    Divider()
                    ForEach(Array(candidates), id: \.name) { candidate in
                        Button {
                            var next = chosen
                            if next.contains(candidate.name) { next.remove(candidate.name) } else { next.insert(candidate.name) }
                            update(valueEvents: next.sorted())
                        } label: {
                            checkLabel("\(candidate.name) · \(AppFormat.count(candidate.count))건",
                                       isOn: chosen.contains(candidate.name))
                        }
                    }
                } label: {
                    Text("가치 행동 고르기")
                        .font(.body)
                }
                .fixedSize()
            }
            Text(definitionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private var definitionText: String {
        if definition.valueEvents.isEmpty {
            return "지금 \"활동\"은 이벤트를 하나라도 보낸 날이에요(앱 실행 포함). 알림만 열심히 보내도 숫자가 부풀 수 있어서, 할 일 완료 · 기록 작성 같은 핵심 가치 행동을 고르는 게 좋아요. 정의를 바꾸면 그 전과의 추세 비교가 깨지니 한 번 정하고 고정하세요."
        }
        var text = "\"활동\" = \(definition.valueEvents.joined(separator: " · ")) 중 하나를 한 날."
        if habit.fellBackToAnyEvent {
            let since = habit.valueSince.map { AppFormat.chartDay($0) } ?? "지금"
            text += " 이 기록은 \(since)부터라 지금 창(58일)을 다 덮지 못해, 덮을 때까지는 아무 이벤트 기준으로 보여요."
        }
        return text
    }

    private func update(valueEvents: [String]) {
        var next = definition
        next.valueEvents = valueEvents
        store.setActivityDefinition(next, for: project)
    }

    // MARK: 숫자

    private var figures: some View {
        let main = habit.mainMetric
        let metricName = habit.cycle?.metricName ?? "MAU"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { figureItems(main: main, metricName: metricName) }
            VStack(alignment: .leading, spacing: 12) { figureItems(main: main, metricName: metricName) }
        }
    }

    @ViewBuilder
    private func figureItems(main: (now: Int, before: Int), metricName: String) -> some View {
        number(habit.cycle == .daily ? "주 지표 · 하루 평균 DAU" : "주 지표 · \(metricName)",
               "\(AppFormat.count(main.now))명", before: "4주 전 \(AppFormat.count(main.before))명")
        number("DAU/MAU", habit.dauOverMau.map(StatsAnalysis.percent) ?? "—",
               before: "4주 전 \(habit.previousDauOverMau.map(StatsAnalysis.percent) ?? "—")",
               isMain: habit.cycle == .daily)
        number("WAU/MAU", habit.wauOverMau.map(StatsAnalysis.percent) ?? "—",
               before: "4주 전 \(habit.previousWauOverMau.map(StatsAnalysis.percent) ?? "—")",
               isMain: habit.cycle == .weekly)
    }

    private func number(_ title: String, _ value: String, before: String, isMain: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(isMain ? Color.accentColor : .secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(before)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: L28

    private struct Bar: Identifiable {
        let day: Int
        let count: Int
        var id: Int { day }
    }

    private var curveChart: some View {
        let bars = habit.curve.enumerated().map { Bar(day: $0.offset + 1, count: $0.element) }
        let threshold = habit.tailThreshold
        return VStack(alignment: .leading, spacing: 6) {
            Text("L28 — 지난 28일 중 며칠 왔나")
                .font(.headline)
            Chart(bars) { bar in
                BarMark(x: .value("온 날", bar.day), y: .value("사람", bar.count))
                    .foregroundStyle(threshold.map { bar.day >= $0 } == true
                                     ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .chartXScale(domain: 0.5...28.5)
            .chartXAxis {
                AxisMarks(values: [1, 7, 14, 21, 28]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)일").font(.body) }
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.body) }
            }
            .frame(height: 160)
            .accessibilityLabel("지난 28일 중 며칠 왔는지 분포")
            Text(curveNote)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var curveNote: String {
        var text = "DAU/MAU 같은 평균은 \"모두가 한 달에 6일\"과 \"10%는 매일, 나머지는 한 번\"을 못 가릅니다. 오른쪽 끝(거의 매일 쓰는 사람)에 사람이 쌓이는지가 진짜 신호예요."
        if let threshold = habit.tailThreshold {
            text += " 색칠한 칸이 \(threshold)일 이상이에요."
        } else {
            text += " 가끔 쓰는 앱은 오른쪽 끝이 비어도 정상이에요."
        }
        return text
    }
}

// MARK: - 세 질문

/// DAU/MAU 는 "습관이 되었나", 코호트 잔존은 "남는 사람이 있나", 유료는 "남은 사람이
/// 가치를 느끼나"에 답한다. 규모가 작으면 잔존이 주인공이라 맨 위로 올린다.
struct ThreeQuestionsCard: View {
    let habit: StatsFinding
    let retention: StatsFinding
    let paid: StatsFinding?
    let isSmall: Bool
    let mau: Int

    var body: some View {
        Card(title: "세 가지 질문", systemImage: "questionmark.bubble") {
            if isSmall {
                Label("MAU \(AppFormat.count(mau))명 규모에서는 DAU가 출시 · 피처링 같은 바깥 일에 크게 흔들려요. 코호트 잔존을 주로, 습관 비율은 보조로 보세요.",
                      systemImage: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .top, spacing: 10) {
                        FindingDot(state: row.state).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.headline)
                            Text(row.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var rows: [(title: String, subtitle: String, state: StatsFinding.State)] {
        let stay = ("남는 사람이 있나? · 코호트 잔존", retention.answer, retention.state)
        let sticky = ("습관이 되었나? · 고착도", habit.answer, habit.state)
        let value = ("남은 사람이 가치를 느끼나? · 유료",
                     paid?.answer ?? "유료 여부를 보내지 않아 모릅니다. 스냅샷에 flag.hasAccess · flag.isPaid 를 보내면 여기 나와요.",
                     paid?.state ?? .unknown)
        return isSmall ? [stay, sticky, value] : [sticky, stay, value]
    }
}

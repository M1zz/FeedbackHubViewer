//
//  DeployCalendarBoard.swift
//  FeedbackHubViewer
//
//  홈의 배포 캘린더 — 2주 스프린트 안에서 날마다 **배포할 앱**과 **QA 할 앱**(사람이 기기에서 시험)을
//  한 줄씩 늘어놓는다. 맨 위는 오늘 할 일 두 칸(오늘 테스트 · 오늘 배포), 그 아래 스프린트의 날들.
//  배포한 앱은 초록 체크와 흐린 글씨, 배포해야 할 앱은 굵은 글씨 — 둘이 한눈에 갈린다.
//  오늘 줄은 주황 테두리. 앱을 다른 날 줄에 끌어 놓으면 그날 배포로 옮겨진다.
//  날을 나누고 판정하는 것은 `DeployCalendar` 가 한다. 여기는 그린다.
//

import SwiftUI

struct DeployCalendarBoard: View {
    /// 홈이 이미 만든 앱 줄 — 사용자 수(`reach`)와 배포 리듬(`cadence`)을 그대로 쓴다.
    let rows: [AppGridHome.Row]

    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    @AppStorage("deploy-calendar-days") private var savedRaw = ""
    @State private var dropTarget: Date?
    /// 지난 2주를 펼쳐 보는가 — 처음엔 오늘부터 보인다.
    @State private var showPast = false

    /// 스토어에 나가 있는 앱만 — 배포할 데가 없는 앱은 캘린더에 둘 까닭이 없다.
    private var apps: [AppGridHome.Row] {
        rows.filter { $0.cadence != nil }.sorted { $0.reach == $1.reach ? $0.name < $1.name : $0.reach > $1.reach }
    }

    var body: some View {
        let apps = apps
        let slots = DeployCalendar.assign(apps.map(\.project), keeping: DeployCalendar.decode(savedRaw))
        let today = Date()
        let start = DeployCalendar.cycleStart(containing: today)
        let todaySlot = DeployCalendar.slot(of: today)
        let on = { (slot: Int) in apps.filter { slots[$0.project] == slot } }

        VStack(alignment: .leading, spacing: 16) {
            header(start: start, today: today, apps: apps, slots: slots)
            todayCards(todaySlot: todaySlot, today: today, on: on)
            Button {
                withAnimation { showPast.toggle() }
            } label: {
                Label(showPast ? "지난 날 접기" : "지난 2주 보기", systemImage: showPast ? "chevron.up" : "clock.arrow.circlepath")
                    .font(.hubCaption)
            }
            .buttonStyle(.borderless)
            // 오늘이 맨 위 — 지난 날은 펼치면 그 위에 붙는다. 오늘부터 2주(한 주기 길이)를 앞으로 보여 준다.
            VStack(spacing: 8) {
                ForEach(showPast ? -14..<14 : 0..<14, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: today))!
                    let slot = DeployCalendar.slot(of: date)
                    if offset == 0 && showPast { weekDivider("오늘부터") }
                    dayRow(date: date, start: start, today: today,
                           deploys: on(slot), tests: on(DeployCalendar.deploySlot(forQA: slot)), slots: slots)
                }
            }
            Text("앱마다 2주에 한 번, 정해진 날에 냅니다(주말 포함). 그 전날이 QA 날입니다. 앱을 다른 날 줄에 끌어 놓으면 그날 배포로 옮겨집니다.")
                .font(.hubCaption)
                .foregroundStyle(.secondary)
        }
        .task(id: apps.map(\.project)) {
            // 처음 보거나 앱이 늘었으면 정한 자리를 남긴다 — 다음에 열어도 같은 날이게.
            let encoded = DeployCalendar.encode(slots)
            if encoded != savedRaw { savedRaw = encoded }
            await icons.resolve(apps.map(\.project), keywords: keywords)
        }
    }

    // MARK: - 맨 위

    /// 스프린트 기간과 진행 — "스프린트 11/30 ~ 12/11 · 배포됨 12 · 배포할 것 25 · 놓침 3".
    private func header(start: Date, today: Date, apps: [AppGridHome.Row], slots: [String: Int]) -> some View {
        let states = apps.compactMap { row in slots[row.project].map { DeployCalendar.state(slot: $0, cadence: row.cadence, today: today) } }
        let done = states.filter { $0 == .shipped || $0 == .inFlight }.count
        let late = states.filter { $0 == .missed || $0 == .blocked }.count
        let day = Date.FormatStyle.dateTime.month(.defaultDigits).day()
        let range = "\(start.formatted(day)) ~ \(DeployCalendar.sprintEnd(cycleStart: start).formatted(day))"

        return VStack(alignment: .leading, spacing: 6) {
            Text("스프린트 \(range)").font(.title3.weight(.semibold))
            HStack(spacing: 14) {
                Label("배포됨 \(done)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("배포할 것 \(states.count - done - late)", systemImage: "circle").foregroundStyle(.secondary)
                if late > 0 {
                    Label("놓침 · 막힘 \(late)", systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.hubCaption)
        }
    }

    /// 오늘 할 일 — 테스트할 앱 · 배포할 앱.
    private func todayCards(todaySlot: Int, today: Date, on: (Int) -> [AppGridHome.Row]) -> some View {
        let start = DeployCalendar.cycleStart(containing: today)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: today))!
        let tests = on(DeployCalendar.deploySlot(forQA: todaySlot))
            .filter { !qaDone(deployState($0, on: tomorrow, start: start, today: today)) }
        let deploys = on(todaySlot).filter {
            DeployCalendar.state(slot: todaySlot, cadence: $0.cadence, today: today) == .today
        }
        let empty = "없음"
        let layout = horizontalOnMac(spacing: 12)
        return layout {
            todayCard("오늘 테스트할 앱", systemImage: "checklist", tint: .purple, empty: empty, names: tests.map(\.name))
            todayCard("오늘 배포할 앱", systemImage: "paperplane.fill", tint: .orange, empty: empty, names: deploys.map(\.name))
        }
    }

    private func todayCard(_ title: String, systemImage: String, tint: Color, empty: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tint)
            Text(names.isEmpty ? empty : names.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(names.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.08)))
    }

    private func weekDivider(_ title: String) -> some View {
        Text(title).font(.hubCaption).foregroundStyle(.secondary).padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 하루 줄

    private func dayRow(date: Date, start: Date, today: Date,
                        deploys: [AppGridHome.Row], tests: [AppGridHome.Row], slots: [String: Int]) -> some View {
        let slot = DeployCalendar.slot(of: date)
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let isPast = date < Calendar.current.startOfDay(for: today)
        let qaFor = Calendar.current.date(byAdding: .day, value: 1, to: date)!

        let layout = horizontalOnMac(spacing: 14)
        return layout {
            Text(date, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated))
                .font(.body.weight(isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                #if os(macOS)
                .frame(width: 90, alignment: .leading)
                #endif
            column("배포", tint: .orange) {
                ForEach(deploys) { row in
                    deployChip(row, state: deployState(row, on: date, start: start, today: today))
                }
            }
            column("QA", tint: .purple) {
                ForEach(tests) { row in testChip(row, deploy: deployState(row, on: qaFor, start: start, today: today)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(dropTarget == date ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isToday ? Color.orange : .clear, lineWidth: 2.5))
        .opacity(isPast && !isToday ? 0.75 : 1)
        .accessibilityAddTraits(isToday ? .isSelected : [])
        .dropDestination(for: String.self) { projects, _ in
            guard let project = projects.first else { return false }
            var moved = slots
            moved[project] = slot
            savedRaw = DeployCalendar.encode(moved)
            return true
        } isTargeted: { dropTarget = $0 ? date : (dropTarget == date ? nil : dropTarget) }
    }

    /// 배포 · QA 칸 — 제목 아래 앱들이 줄바꿈하며 늘어선다.
    private func column<Content: View>(_ title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            FlowLayout(spacing: 6) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 배포 앱 — 낸 것은 초록 체크와 흐린 글씨, 낼 것은 굵은 글씨, 오늘은 주황 테두리, 놓친 것은 빨간 테두리.
    /// `state` 가 nil 이면 지난 주기 — 그때 냈는지는 기록이 없어 흐리게만.
    private func deployChip(_ row: AppGridHome.Row, state: DeployCalendar.State?) -> some View {
        let done = state == nil || state == .shipped || state == .inFlight
        let border: Color = state == .missed || state == .blocked ? .red : state == .today ? .orange : .clear
        let label = state?.label ?? "지난 주기"
        return Button {
            store.open(project: row.project, section: .release)
        } label: {
            chipLabel(row, systemImage: state?.systemImage ?? "clock", tint: state?.tint ?? .secondary, faded: done, border: border)
        }
        .buttonStyle(.plain)
        .draggable(row.project)
        .help("\(label)\(row.cadence.map { " · \($0.line)" } ?? "")")
        .accessibilityLabel("\(row.name) 배포, \(label), \(detail(row))")
    }

    /// 그날 배포 판정 — 이번 주기 안이면 배포 기록으로, 지난 주기는 기록이 없어 nil(흐리게), 다음 주기는 예정.
    private func deployState(_ row: AppGridHome.Row, on date: Date, start: Date, today: Date) -> DeployCalendar.State? {
        let end = Calendar.current.date(byAdding: .day, value: DeployCalendar.slotCount, to: start)!
        if date < start { return nil }
        if date >= end { return .upcoming }
        return DeployCalendar.state(slot: DeployCalendar.slot(of: date), cadence: row.cadence, today: today)
    }

    /// QA 할 필요가 없는가 — 그 배포가 이미 나갔거나 심사 중이거나 지난 주기.
    private func qaDone(_ deploy: DeployCalendar.State?) -> Bool {
        deploy == nil || deploy == .shipped || deploy == .inFlight
    }

    /// QA 앱 — 사람이 기기에서 시험할 것. 다음 날 배포가 이미 끝났으면 흐리게.
    private func testChip(_ row: AppGridHome.Row, deploy: DeployCalendar.State?) -> some View {
        let done = qaDone(deploy)
        return Button {
            store.open(project: row.project, section: .release)
        } label: {
            chipLabel(row, systemImage: done ? "checkmark.circle.fill" : "iphone",
                      tint: done ? .green : .purple, faded: done, border: .clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name) QA, \(detail(row))")
    }

    private func chipLabel(_ row: AppGridHome.Row, systemImage: String, tint: Color, faded: Bool, border: Color) -> some View {
        HStack(spacing: 6) {
            AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.hubCaption.weight(faded ? .regular : .semibold)).lineLimit(1)
                Text(detail(row)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1.5))
        .opacity(faded ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    /// 앱 이름 아래 한 줄 — 스토어의 지금 버전(다음 버전이 길 위에 있으면 그것도)과 플랫폼.
    /// "v1.0.5 → 1.0.6 심사 대기 · iOS · macOS"
    private func detail(_ row: AppGridHome.Row) -> String {
        var version = keywords.storeApp(for: row.project)?.version.map { "v\($0)" } ?? ""
        if let next = row.cadence?.next { version += version.isEmpty ? next : " → \(next)" }
        let platforms = Set(store.snapshots(for: row.project).compactMap { AppQuality.Platform.normalize($0.platform) })
        let names = AppQuality.Platform.order.filter(platforms.contains)
        return ([version] + (names.isEmpty ? ["iOS"] : names)).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 맥은 옆으로, 아이폰은 폭이 모자라 위아래로.
    private func horizontalOnMac(spacing: CGFloat) -> AnyLayout {
        #if os(iOS)
        AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        #else
        AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        #endif
    }
}

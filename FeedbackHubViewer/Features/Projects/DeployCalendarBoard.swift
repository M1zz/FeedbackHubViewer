//
//  DeployCalendarBoard.swift
//  FeedbackHubViewer
//
//  홈의 배포 캘린더 — 2주(평일 열 날) 안에 앱마다 배포하는 날이 정해져 있고, 이번 주기에
//  누가 냈고 누가 남았는지 본다. 앱을 다른 날로 끌어 놓으면 그날로 옮겨지고, 그 자리는 남는다.
//  날을 나누고 판정하는 것은 `DeployCalendar` 가 한다. 여기는 그린다.
//

import SwiftUI

struct DeployCalendarBoard: View {
    /// 홈이 이미 만든 앱 줄 — 사용자 수(`reach`)와 배포 리듬(`cadence`)을 그대로 쓴다.
    let rows: [AppGridHome.Row]

    @EnvironmentObject private var store: FeedbackStore
    @EnvironmentObject private var keywords: KeywordStore
    @ObservedObject private var icons = StoreIcons.shared
    @AppStorage("deploy-calendar-slots") private var savedRaw = ""
    @State private var dropTarget: Int?

    /// 스토어에 나가 있는 앱만 — 배포할 데가 없는 앱은 캘린더에 둘 까닭이 없다.
    private var apps: [AppGridHome.Row] {
        rows.filter { $0.cadence != nil }.sorted { $0.reach == $1.reach ? $0.name < $1.name : $0.reach > $1.reach }
    }

    var body: some View {
        let apps = apps
        let slots = DeployCalendar.assign(apps.map(\.project), keeping: DeployCalendar.decode(savedRaw))
        let today = Date()
        let start = DeployCalendar.cycleStart(containing: today)
        let byProject = Dictionary(uniqueKeysWithValues: apps.map { ($0.project, $0) })

        VStack(alignment: .leading, spacing: 16) {
            summary(slots: slots, byProject: byProject, today: today)
            ForEach(0..<2, id: \.self) { week in
                // 맥은 한 주를 한 줄에(월~일, 주말은 좁게), 아이폰은 폭이 모자라 날마다 한 줄씩.
                #if os(iOS)
                let layout = AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                #else
                let layout = AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                #endif
                layout {
                    ForEach(0..<7, id: \.self) { weekday in
                        if weekday < 5 {
                            let slot = week * 5 + weekday
                            day(slot: slot, start: start, today: today,
                                apps: apps.filter { slots[$0.project] == slot }, slots: slots)
                        } else {
                            weekend(Calendar.current.date(byAdding: .day, value: week * 7 + weekday, to: start)!, today: today)
                        }
                    }
                }
            }
            Text("앱마다 2주에 한 번, 정해진 평일에 냅니다. 앱을 다른 날로 끌어 놓으면 옮겨집니다. 새 앱은 가장 한가한 날에 들어갑니다.")
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

    // MARK: - 맨 위 한 줄

    private func summary(slots: [String: Int], byProject: [String: AppGridHome.Row], today: Date) -> some View {
        let states = slots.compactMap { project, slot in
            byProject[project].map { (row: $0, state: DeployCalendar.state(slot: slot, cadence: $0.cadence, today: today)) }
        }
        let todays = states.filter { $0.state == .today }.map(\.row.name).sorted()
        let missed = states.filter { $0.state == .missed || $0.state == .blocked }.count
        let done = states.filter { $0.state == .shipped || $0.state == .inFlight }.count

        return VStack(alignment: .leading, spacing: 6) {
            Text("오늘 \(today.formatted(.dateTime.month().day().weekday(.wide)))")
                .font(.title3.weight(.semibold))
            Text(todays.isEmpty
                 ? (DeployCalendar.slot(of: today) == nil ? "주말이라 배포 없는 날" : "오늘 낼 앱은 다 냈어요")
                 : "오늘 배포 · \(todays.joined(separator: " · "))")
                .font(.headline)
            HStack(spacing: 14) {
                Label("이번 주기 \(done)/\(states.count) 냄", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                if missed > 0 {
                    Label("놓침 · 막힘 \(missed)", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
            .font(.hubCaption)
        }
    }

    // MARK: - 하루 칸

    private func day(slot: Int, start: Date, today: Date, apps: [AppGridHome.Row], slots: [String: Int]) -> some View {
        let date = DeployCalendar.date(slot: slot, cycleStart: start)
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)

        return VStack(alignment: .leading, spacing: 6) {
            Text(date, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated))
                .font(.hubCaption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            ForEach(apps) { row in
                chip(row, state: DeployCalendar.state(slot: slot, cadence: row.cadence, today: today))
            }
            if apps.isEmpty {
                Text("없음").font(.hubCaption).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #else
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        #endif
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(dropTarget == slot ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03)))
        .modifier(TodayBorder(isToday: isToday))
        .dropDestination(for: String.self) { projects, _ in
            guard let project = projects.first else { return false }
            var moved = slots
            moved[project] = slot
            savedRaw = DeployCalendar.encode(moved)
            return true
        } isTargeted: { dropTarget = $0 ? slot : (dropTarget == slot ? nil : dropTarget) }
    }

    /// 주말 — 배포하지 않는 날. 오늘이 주말이어도 테두리로 어디쯤인지 보이게 좁은 칸으로 둔다.
    /// 아이폰은 세로로 늘어놓으니 오늘인 주말만 한 줄로.
    @ViewBuilder
    private func weekend(_ date: Date, today: Date) -> some View {
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        #if os(iOS)
        if isToday {
            Text("\(date.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))) · 배포 없는 날")
                .font(.hubCaption.weight(.bold))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(TodayBorder(isToday: true))
        }
        #else
        Text(date, format: .dateTime.day().weekday(.narrow))
            .font(.hubCaption.weight(isToday ? .bold : .regular))
            .foregroundStyle(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.vertical, 10)
            .frame(width: 44)
            .frame(minHeight: 140, alignment: .top)
            .modifier(TodayBorder(isToday: isToday))
        #endif
    }

    private func chip(_ row: AppGridHome.Row, state: DeployCalendar.State) -> some View {
        Button {
            store.open(project: row.project, section: .release)
        } label: {
            HStack(spacing: 6) {
                AppIcon(url: icons.url(for: row.project, keywords: keywords), size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).lineLimit(1)
                    Text(detail(row))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: state.systemImage).foregroundStyle(state.tint)
            }
            .font(.hubCaption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(row.project)
        .help("\(state.label)\(row.cadence.map { " · \($0.line)" } ?? "")")
        .accessibilityLabel("\(row.name), \(detail(row)), \(state.label)")
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
}

/// 오늘 칸 — 주황 테두리 하나로 표시한다.
private struct TodayBorder: ViewModifier {
    let isToday: Bool
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isToday ? Color.orange : .clear, lineWidth: 2.5))
            .accessibilityAddTraits(isToday ? .isSelected : [])
    }
}

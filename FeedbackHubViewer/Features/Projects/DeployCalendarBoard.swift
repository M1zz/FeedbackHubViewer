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
                // 맥은 한 주를 한 줄에(월~금), 아이폰은 폭이 모자라 날마다 한 줄씩.
                #if os(iOS)
                let layout = AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                #else
                let layout = AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                #endif
                layout {
                    ForEach(0..<5, id: \.self) { weekday in
                        let slot = week * 5 + weekday
                        day(slot: slot, start: start, today: today,
                            apps: apps.filter { slots[$0.project] == slot }, slots: slots)
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
            Text(todays.isEmpty
                 ? (DeployCalendar.slot(of: today) == nil ? "주말 — 배포 없는 날" : "오늘 낼 앱은 다 냈어요")
                 : "오늘 배포 · \(todays.joined(separator: " · "))")
                .font(.title3.weight(.semibold))
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
                .foregroundStyle(isToday ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
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
            .fill(dropTarget == slot ? Color.accentColor.opacity(0.15) : Color.primary.opacity(isToday ? 0.07 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isToday ? Color.orange.opacity(0.6) : .clear, lineWidth: 1.5))
        .dropDestination(for: String.self) { projects, _ in
            guard let project = projects.first else { return false }
            var moved = slots
            moved[project] = slot
            savedRaw = DeployCalendar.encode(moved)
            return true
        } isTargeted: { dropTarget = $0 ? slot : (dropTarget == slot ? nil : dropTarget) }
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

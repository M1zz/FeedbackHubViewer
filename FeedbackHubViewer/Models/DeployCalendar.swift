//
//  DeployCalendar.swift
//  FeedbackHubViewer
//
//  배포 캘린더 — 2주에 한 번 배포(`ReleaseCadence.goalDays`)를 앱마다 **정해진 평일 하나**로 나눈다.
//
//  2주는 평일 열 날(월~금 × 2)이다. 앱마다 그중 하루를 갖고, 그날이 2주마다 돌아온다.
//  한 날에 몰리면 이 Mac 이 무거워지니(배포는 한 번에 하나) 하루에 너덧 개씩 고르게 나눈다.
//
//  자리는 한 번 정하면 그대로 둔다 — 사용자 수가 바뀔 때마다 날이 바뀌면 캘린더가 아니다.
//  새로 생긴 앱만 가장 한가한 날에 들어가고, 손으로 옮긴 자리도 남는다. 사라진 앱은 빠진다.
//  사용자가 많은 앱이 먼저 자리를 골라, 큰 앱끼리 한 날에 겹치지 않는다.
//
//  판정은 순수 함수다 — 같은 날짜 · 같은 배포 기록이면 같은 말이 나온다.
//

import SwiftUI

enum DeployCalendar {

    /// 주기의 기준 월요일(2026-11-16). 여기서 2주씩 돈다 — 2주 배포를 정한 뒤 첫 주기가 11-30 에 시작한다.
    static let anchor: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 16
        return Calendar.current.date(from: parts)!
    }()
    static let slotCount = 10

    private static var calendar: Calendar { Calendar.current }

    // MARK: 날짜 ↔ 자리

    /// 이 날이 주기의 몇 번째 평일인가(0~9). 주말이면 nil.
    static func slot(of date: Date) -> Int? {
        let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
        let inCycle = ((days % 14) + 14) % 14
        let week = inCycle / 7, weekday = inCycle % 7
        return weekday < 5 ? week * 5 + weekday : nil
    }

    /// `date` 가 든 주기의 첫 월요일.
    static func cycleStart(containing date: Date) -> Date {
        let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
        let back = ((days % 14) + 14) % 14
        return calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: date))!
    }

    /// 주기 안 자리의 날짜.
    static func date(slot: Int, cycleStart: Date) -> Date {
        calendar.date(byAdding: .day, value: (slot / 5) * 7 + slot % 5, to: cycleStart)!
    }

    // MARK: 자리 나누기

    /// 있던 자리는 그대로 두고, 없는 앱만 가장 한가한 날(같으면 앞 날)에 넣는다.
    /// `projects` 는 먼저 자리를 고를 앱부터(사용자 많은 순).
    static func assign(_ projects: [String], keeping saved: [String: Int]) -> [String: Int] {
        let wanted = Set(projects)
        var slots = saved.filter { wanted.contains($0.key) && (0..<slotCount).contains($0.value) }
        var load = Array(repeating: 0, count: slotCount)
        for slot in slots.values { load[slot] += 1 }
        for project in projects where slots[project] == nil {
            let lightest = load.indices.min { load[$0] < load[$1] }!
            slots[project] = lightest
            load[lightest] += 1
        }
        return slots
    }

    /// 저장 형식 — "앱\t자리" 줄들. `@AppStorage` 에 그대로 둔다.
    static func decode(_ raw: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2, let slot = Int(parts[1]) { out[String(parts[0])] = slot }
        }
        return out
    }

    static func encode(_ slots: [String: Int]) -> String {
        slots.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
    }

    // MARK: 이번 주기의 판정

    enum State: Int, Comparable {
        /// 다음 버전이 거절 · 바이너리 오류.
        case blocked
        /// 날이 지났는데 이번 주기에 안 나감.
        case missed
        /// 오늘이 그날.
        case today
        /// 심사 · 출시 대기.
        case inFlight
        /// 날이 아직.
        case upcoming
        /// 이번 주기에 이미 나감.
        case shipped
        static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .blocked: "막힘"
            case .missed: "놓침"
            case .today: "오늘"
            case .inFlight: "심사 중"
            case .upcoming: "예정"
            case .shipped: "냄"
            }
        }

        var tint: Color {
            switch self {
            case .blocked, .missed: .red
            case .today: .orange
            case .inFlight: .blue
            case .upcoming: .secondary
            case .shipped: .green
            }
        }

        var systemImage: String {
            switch self {
            case .blocked: "xmark.octagon.fill"
            case .missed: "exclamationmark.circle.fill"
            case .today: "arrow.up.circle.fill"
            case .inFlight: "paperplane.fill"
            case .upcoming: "circle"
            case .shipped: "checkmark.circle.fill"
            }
        }
    }

    /// 이번 주기에 이 앱은 어디쯤인가. 배포일을 모르면(스토어에 없음) 날짜로만 본다.
    static func state(slot: Int, cadence: ReleaseCadence?, today: Date) -> State {
        let start = cycleStart(containing: today)
        let due = date(slot: slot, cycleStart: start)
        let startOfToday = calendar.startOfDay(for: today)
        switch cadence?.status {
        case .blocked?: return .blocked
        case .inFlight?: return .inFlight
        default: break
        }
        // 이번 주기 안에(첫 월요일부터 오늘까지) 나갔나.
        let sinceStart = calendar.dateComponents([.day], from: start, to: startOfToday).day ?? 0
        if let days = cadence?.days, days <= sinceStart { return .shipped }
        if due == startOfToday { return .today }
        return due < startOfToday ? .missed : .upcoming
    }
}

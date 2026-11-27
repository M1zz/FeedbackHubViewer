//
//  ReleaseCadence.swift
//  FeedbackHubViewer
//
//  배포 리듬 — 앱마다 마지막으로 스토어에 나간 지 며칠 지났나, **2주에 한 번** 목표에 견주면 어디쯤인가.
//
//  재료:
//   · 마지막 배포일 — 스토어의 지금 버전이 나온 날(`AppStoreApp.releasedAt`, iTunes 조회의 currentVersionReleaseDate).
//   · 다음 버전의 상태 — App Store Connect 의 가장 새 버전(`AppVersionStatus`). 심사 대기 · 심사 중 · 출시 대기면
//     이미 다음 배포가 길 위에 있으니 재촉하지 않는다. 거절이면 따로 알린다.
//
//  판정(목표 14일):
//   · 여유      0~10일    — 초록
//   · 곧        11~14일   — 주황, "D-n"
//   · 넘김      15일~     — 빨강, "+n일"
//   · 가는 중   다음 버전이 심사 · 출시 대기 — 파랑
//   · 막힘      다음 버전이 거절 · 바이너리 오류 — 빨강
//
//  판정은 순수 함수다 — 같은 날짜 · 상태면 같은 말이 나온다.
//

import SwiftUI

struct ReleaseCadence: Equatable {

    /// 목표 — 2주에 한 번.
    static let goalDays = 14
    /// 이만큼부터 "곧 낼 때".
    static let soonDays = 11

    enum Status: Int, Comparable {
        /// 급한 것부터.
        case blocked, overdue, soon, inFlight, fresh, unknown
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    let status: Status
    /// 마지막 배포 뒤 지난 날. 모르면 nil.
    let days: Int?
    /// 길 위에 있는 · 막힌 다음 버전("1.2.8 심사 대기").
    let next: String?

    init(releasedAt: Date?, liveVersion: String?, latest: AppVersionStatus?, now: Date = Date()) {
        let days = releasedAt.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0) }
        self.days = days
        // 가장 새 버전이 지금 나가 있는 것과 다르고 움직이는 중이면 — 다음 배포가 길 위에 있다.
        let pending = latest.flatMap { status -> AppVersionStatus? in
            guard status.version != liveVersion, status.tone != .live else { return nil }
            return status
        }
        if let pending, pending.tone == .blocked {
            status = .blocked
            next = "\(pending.version) \(pending.stateLabel)"
        } else if let pending, pending.state != "PREPARE_FOR_SUBMISSION" {
            status = .inFlight
            next = "\(pending.version) \(pending.stateLabel)"
        } else if let days {
            status = days > Self.goalDays ? .overdue : days >= Self.soonDays ? .soon : .fresh
            next = nil
        } else {
            status = .unknown
            next = nil
        }
    }

    /// 카드의 한 줄 — "마지막 배포 9일 전 · D-5".
    var line: String {
        let since = days.map { $0 == 0 ? "마지막 배포 오늘" : "마지막 배포 \($0)일 전" } ?? "배포일 모름"
        switch status {
        case .fresh: return since
        case .soon: return "\(since) · D-\(max(0, Self.goalDays - (days ?? 0)))"
        case .overdue: return "\(since) · 목표 넘김 +\((days ?? 0) - Self.goalDays)일"
        case .inFlight, .blocked: return "\(since) · \(next ?? "")"
        case .unknown: return since
        }
    }

    var tint: Color {
        switch status {
        case .fresh: return .green
        case .soon: return .orange
        case .overdue, .blocked: return .red
        case .inFlight: return .blue
        case .unknown: return .secondary
        }
    }

    var systemImage: String {
        switch status {
        case .inFlight: return "paperplane"
        case .blocked: return "xmark.octagon"
        default: return "shippingbox"
        }
    }

    /// 목표 안에 있나 — 나가 있는 지 2주 안이거나, 다음 버전이 이미 길 위에 있다.
    var isOnTrack: Bool { status == .fresh || status == .soon || status == .inFlight }
}

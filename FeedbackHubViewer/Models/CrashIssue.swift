//
//  CrashIssue.swift
//  FeedbackHubViewer
//
//  같은 사고끼리 묶은 덩어리. 크래시 목록이 대답하지 못하는 것을 대답한다.
//
//   · 무엇이 제일 많이 죽는가 (건수)
//   · 언제부터인가 (첫 등장, 그리고 어느 버전부터)
//   · 아직도 나는가 (최근 7일, 지난주 대비)
//   · 몇 종류 기기·OS 인가 (특정 기기만의 일인지)
//
//  한 건씩 늘어놓은 목록으로는 이 중 무엇도 알 수 없다. 149건을 다 열어 봐도
//  "많이 나는 것부터"를 못 고른다. 고칠 순서를 정하는 것이 이 화면의 일이다.
//

import Foundation

struct CrashIssue: Identifiable, Hashable {

    /// 지문. `CrashReport.fingerprint` 그대로다.
    let id: String
    let kind: String
    let cause: CrashReport.Cause

    /// 이 사고에 묶인 진단들, 최신순.
    let reports: [CrashReport]

    /// 죽은 자리에서 가장 가까운 내 코드 프레임. 제목이자 "여기부터 보라"다.
    let culprit: CrashReport.Frame?

    let firstSeen: Date?
    let lastSeen: Date?
    let last7Days: Int
    let previous7Days: Int

    /// 이 사고가 난 앱 버전, 많은 순.
    let versions: [(version: String, count: Int)]
    /// 기기 모델, 많은 순.
    let devices: [(device: String, count: Int)]
    /// OS 버전, 많은 순.
    let osVersions: [(os: String, count: Int)]

    /// 같은 이슈 안에서 오프셋이 다른 자리의 수. 심볼이 없어 이름으로 묶은 탓에
    /// 서로 다른 자리가 한데 들어올 수 있는데, 그 정도를 이 숫자가 알려 준다.
    let variants: Int

    /// 갈라 볼 수 없는 옛 형식 레코드 묶음인가.
    let isLegacy: Bool

    var count: Int { reports.count }
    var delta: Int { last7Days - previous7Days }

    /// 이번 주에 처음 봤다. 새로 생긴 사고일 가능성이 크다.
    var isNew: Bool {
        guard let firstSeen else { return false }
        return firstSeen >= Date().addingTimeInterval(-7 * 86_400)
    }

    /// 최근 7일에 한 건도 없다. 사라졌거나, 그 버전을 쓰는 사람이 없어졌다.
    var isDormant: Bool { last7Days == 0 }

    /// 화면에 쓸 제목.
    var title: String {
        if isLegacy { return "옛 형식 (콜스택 분석 불가)" }
        guard let culprit else { return cause.label }
        return culprit.isSystem
            ? "\(culprit.binary) (시스템 프레임)"
            : "\(culprit.binary) +\(culprit.offset)"
    }

    /// 제목 아래 한 줄. 스택의 모양을 짧게 보여 준다.
    var shape: String {
        let binaries = reports.first?.frames.prefix(4).map(\.binary) ?? []
        return binaries.isEmpty ? cause.label : binaries.joined(separator: " ← ")
    }

    static func == (lhs: CrashIssue, rhs: CrashIssue) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - 묶기

    /// 진단 묶음을 이슈로 접는다. **아픈 것부터** 나온다: 최근 7일이 많은 순,
    /// 같으면 전체 건수 순. 고칠 순서가 그 순서다.
    static func group(_ reports: [CrashReport], now: Date = Date()) -> [CrashIssue] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)

        return Dictionary(grouping: reports, by: \.fingerprint).map { fingerprint, group in
            let sorted = group.sorted {
                ($0.happenedAt ?? .distantPast) > ($1.happenedAt ?? .distantPast)
            }
            let dates = group.compactMap(\.happenedAt)

            func tally<Key: Hashable>(_ key: (CrashReport) -> Key) -> [(Key, Int)] {
                Dictionary(grouping: group, by: key)
                    .map { ($0.key, $0.value.count) }
                    .sorted { $0.1 > $1.1 }
            }

            return CrashIssue(
                id: fingerprint,
                kind: sorted.first?.kind ?? "-",
                cause: sorted.first?.cause ?? .unknown,
                reports: sorted,
                culprit: sorted.first?.culprit,
                firstSeen: dates.min(),
                lastSeen: dates.max(),
                last7Days: dates.filter { $0 >= weekAgo }.count,
                previous7Days: dates.filter { $0 >= twoWeeksAgo && $0 < weekAgo }.count,
                versions: tally(\.versionLabel).map { (version: $0.0, count: $0.1) },
                devices: tally(\.deviceType).map { (device: $0.0, count: $0.1) },
                osVersions: tally(\.osVersion).map { (os: $0.0, count: $0.1) },
                variants: Set(group.map(\.variantKey)).count,
                isLegacy: sorted.first?.isLegacyStack ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.last7Days != rhs.last7Days { return lhs.last7Days > rhs.last7Days }
            return lhs.count > rhs.count
        }
    }
}

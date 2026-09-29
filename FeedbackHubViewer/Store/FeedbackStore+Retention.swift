//
//  FeedbackStore+Retention.swift
//  FeedbackHubViewer
//
//  시간 축으로 본 사용 형태 두 가지 — 코호트 잔존과 한 달에 며칠 오는가.
//
//  둘 다 새 데이터가 필요 없다. 일 버킷이 그날 이벤트를 보낸 설치 ID를 180일 치
//  들고 있고(`UsageRollups.idRetentionDays`), 스냅샷이 설치일을 들고 있다. 설치
//  하나를 "며칠 전에 깔렸고, 그 뒤 어느 날들에 왔는가"로 펼치면 두 카드가 다 나온다.
//
//  활성의 정의는 DAU · WAU · MAU와 같다: 그날 이벤트를 하나라도 보낸 설치.
//

import Foundation

extension FeedbackStore {

    // MARK: - 코호트 잔존

    /// 같은 주에 깐 설치들이 며칠 뒤에도 오는가.
    ///
    /// **활성 사용자 수로는 이 답이 안 나온다.** MAU가 그대로여도 새로 온 사람이 떠난
    /// 사람을 메우는 중일 수 있고, 그건 설치가 끊기는 날 한꺼번에 드러난다. 잔존은
    /// 같은 사람을 따라가므로 새 유입에 가려지지 않는다.
    struct Retention {

        /// 재는 자리. 7일 · 30일이 하루가 아니라 일주일 폭인 이유: 하루로 재면
        /// "7일째가 마침 일요일이었다"가 숫자를 흔든다. 필요할 때만 여는 도구는
        /// 특히 그렇다. 1일은 다음 날 하루 — 첫인상이 남았는가를 묻는 자리라 좁게 잰다.
        enum Checkpoint: String, CaseIterable, Identifiable {
            case day1, day7, day30

            var id: String { rawValue }

            /// 설치일을 0으로 센 날 범위.
            var days: ClosedRange<Int> {
                switch self {
                case .day1: return 1...1
                case .day7: return 7...13
                case .day30: return 30...36
                }
            }

            var label: String {
                switch self {
                case .day1: return "1일 뒤"
                case .day7: return "7일 뒤"
                case .day30: return "30일 뒤"
                }
            }

            var detail: String {
                switch self {
                case .day1: return "다음 날"
                case .day7: return "7~13일째"
                case .day30: return "30~36일째"
                }
            }
        }

        /// 돌아온 수와, 잴 수 있었던 수. 재는 창이 아직 다 지나지 않은 설치는
        /// 분모에 안 든다 — 어제 깐 사람을 "7일 뒤에 안 왔다"로 세면 최근 주가
        /// 늘 폭락한 것처럼 보인다.
        struct Rate {
            var returned = 0
            var eligible = 0

            var ratio: Double? { eligible > 0 ? Double(returned) / Double(eligible) : nil }
        }

        struct Cohort: Identifiable {
            /// 그 주의 첫날.
            let start: Date
            let size: Int
            let rates: [Checkpoint: Rate]
            /// 주 단위 잔존 — k주째(깐 날부터 7k~7k+6일째)에 한 번이라도 온 비율.
            /// 인덱스 0이 1주째. Firebase · Amplitude 의 코호트 삼각형 표가 이것이다.
            var weekly: [Rate] = []

            var id: Date { start }
        }

        /// 최근 주가 위.
        let cohorts: [Cohort]
        /// 코호트를 합친 값 — 주마다 몇 명 안 되는 앱에서 읽을 한 숫자.
        let pooled: [Checkpoint: Rate]
        /// 이 날 이전에 깐 설치는 뺐다. 이 앱이 이벤트를 보내기 시작한 날이거나,
        /// 설치 ID가 남아 있는 가장 먼 날이다.
        let since: Date?
        /// 설치일이 그보다 앞서서 뺀 설치 수.
        let excludedBeforeSince: Int
        /// 잔존 곡선 — 깐 지 N일째(1…30)에 앱을 쓴 비율. 1·7·30일 세 점과 달리
        /// **모양**이 보인다: 떨어지다 어디서 평평해지는가가 잔존의 요점이다.
        var curve: [Int: Rate] = [:]
        /// 같은 곡선을 최근 4주에 깐 설치만으로.
        var recentCurve: [Int: Rate] = [:]
        /// 그보다 전에 깐 설치만으로. 최근 곡선과 겹쳐 나아졌는지 본다.
        var olderCurve: [Int: Rate] = [:]

        static let curveDays = 30
        /// 삼각형 표의 열 수(1주째 … 8주째).
        static let triangleWeeks = 8
        /// 곡선에서 "최근"으로 가르는 설치 경과일.
        static let recentWindow = 28

        var isEmpty: Bool { cohorts.isEmpty }

        /// 몇 주를 보여 줄까. 30일 칸이 채워지려면 5주가 넘게 걸리므로 그 뒤로
        /// 몇 주를 더 둬야 30일 칸에 숫자가 있는 줄이 생긴다.
        static let weeks = 12
    }

    func retention(for project: String?, audience: Audience = .all,
                   calendar: Calendar = .current) -> Retention {
        memoized(\.retention, ScopeKey(project: project, audience: audience)) {
            let now = Date()
            let lookback = Retention.weeks * 7 + 7
            // 설치 ID가 있는 날만 읽는다. 그보다 먼 날은 이름이 지워져 "안 왔다"와
            // 구별이 안 된다.
            let span = min(UsageRollups.idRetentionDays,
                           lookback + Retention.Checkpoint.day30.days.upperBound)
            let axis = UsageRollups.recentDayKeys(span, calendar: calendar, endingAt: now)
            // 오늘이 0, 어제가 1 — 날짜 계산 없이 키 하나로 며칠 전인지 안다.
            var daysAgo: [String: Int] = [:]
            for (index, entry) in axis.enumerated() { daysAgo[entry.key] = span - 1 - index }

            let days = self.days(for: project, audience: audience)
            var seen: [String: Set<Int>] = [:]
            var firstEventAgo: Int?
            for (key, bucket) in days {
                guard let ago = daysAgo[key], !bucket.installs.isEmpty else { continue }
                firstEventAgo = max(firstEventAgo ?? ago, ago)
                for install in bucket.installs { seen[install, default: []].insert(ago) }
            }
            // 이벤트를 한 번도 안 보낸 앱은 모든 설치가 "안 왔다"가 된다. 그건 잔존이
            // 0인 게 아니라 잴 수 없는 것이다.
            guard let firstEventAgo else {
                return Retention(cohorts: [], pooled: [:], since: nil, excludedBeforeSince: 0)
            }

            var members: [Date: [(installAgo: Int, active: Set<Int>)]] = [:]
            var excluded = 0
            for snapshot in snapshots(for: project, audience: audience) {
                guard let installed = snapshot.installDate,
                      let installAgo = daysAgo[UsageRollups.dayKey(installed, calendar: calendar)]
                else { continue }
                // 이벤트를 보내기 전에 깐 사람은 설치 직후를 못 봤다 — 다음 날 왔어도
                // 기록이 없다. 넣으면 잔존이 거짓으로 낮아진다.
                guard installAgo <= firstEventAgo else { excluded += 1; continue }
                guard installAgo < lookback,
                      let week = calendar.dateInterval(of: .weekOfYear, for: installed)?.start
                else { continue }
                members[week, default: []].append((installAgo, seen[snapshot.installID] ?? []))
            }

            var pooled: [Retention.Checkpoint: Retention.Rate] = [:]
            let cohorts = members.keys.sorted(by: >).prefix(Retention.weeks).map { week in
                let group = members[week] ?? []
                var rates: [Retention.Checkpoint: Retention.Rate] = [:]
                for checkpoint in Retention.Checkpoint.allCases {
                    var rate = Retention.Rate()
                    for member in group {
                        // 재는 창의 마지막 날이 어제 이전이어야 잰다(오늘은 안 끝났다).
                        let lastAgo = member.installAgo - checkpoint.days.upperBound
                        guard lastAgo >= 1 else { continue }
                        rate.eligible += 1
                        let firstAgo = member.installAgo - checkpoint.days.lowerBound
                        if member.active.contains(where: { $0 >= lastAgo && $0 <= firstAgo }) {
                            rate.returned += 1
                        }
                    }
                    rates[checkpoint] = rate
                    pooled[checkpoint, default: .init()].returned += rate.returned
                    pooled[checkpoint, default: .init()].eligible += rate.eligible
                }
                let weekly = (1...Retention.triangleWeeks).map { k -> Retention.Rate in
                    var rate = Retention.Rate()
                    for member in group {
                        let lastAgo = member.installAgo - (7 * k + 6)
                        guard lastAgo >= 1 else { continue }
                        rate.eligible += 1
                        let firstAgo = member.installAgo - 7 * k
                        if member.active.contains(where: { $0 >= lastAgo && $0 <= firstAgo }) {
                            rate.returned += 1
                        }
                    }
                    return rate
                }
                return Retention.Cohort(start: week, size: group.count, rates: rates, weekly: weekly)
            }

            // 곡선: 깐 지 N일째 되는 날이 어제 이전인 설치만 분모에 든다.
            var curve: [Int: Retention.Rate] = [:]
            var recent: [Int: Retention.Rate] = [:]
            var older: [Int: Retention.Rate] = [:]
            for member in members.values.joined() {
                let isRecent = member.installAgo <= Retention.recentWindow
                for day in 1...Retention.curveDays {
                    let ago = member.installAgo - day
                    guard ago >= 1 else { break }
                    let came = member.active.contains(ago)
                    curve[day, default: .init()].eligible += 1
                    if came { curve[day, default: .init()].returned += 1 }
                    if isRecent {
                        recent[day, default: .init()].eligible += 1
                        if came { recent[day, default: .init()].returned += 1 }
                    } else {
                        older[day, default: .init()].eligible += 1
                        if came { older[day, default: .init()].returned += 1 }
                    }
                }
            }

            let since = calendar.date(byAdding: .day, value: -firstEventAgo,
                                      to: calendar.startOfDay(for: now))
            return Retention(cohorts: Array(cohorts), pooled: pooled,
                             since: since, excludedBeforeSince: excluded,
                             curve: curve, recentCurve: recent, olderCurve: older)
        }
    }

    // MARK: - Lifecycle (신규 · 유지 · 복귀 · 이탈)

    /// 한 주 동안 활동한 사람을 넷으로 가른다. Amplitude 의 Lifecycle, 흔히 growth
    /// accounting 이라 부르는 그림이다. 활성 사용자 수가 그대로여도 안에서 새로 온
    /// 사람이 떠난 사람을 메우고 있는지, 둘 다 적은지는 이것으로만 보인다.
    ///
    ///  · 신규: 이번 주에 처음 온 사람(이 허브가 기억하는 180일 안에서)
    ///  · 유지: 지난주에도 오고 이번 주에도 온 사람
    ///  · 복귀: 지난주엔 없었는데 그 전에 왔던 사람이 돌아옴
    ///  · 이탈: 지난주엔 왔는데 이번 주엔 안 온 사람(음수로 그린다)
    ///
    /// 주는 달력 주가 아니라 **어제에서 끝나는 7일**씩 물러난다. 이번 주가 반만 지난
    /// 월요일에 막대가 폭락한 것처럼 보이지 않게.
    struct Lifecycle {
        struct Week: Identifiable {
            /// 이 7일의 첫날.
            let start: Date
            let new: Int
            let retained: Int
            let resurrected: Int
            let dormant: Int
            var id: Date { start }
            var active: Int { new + retained + resurrected }
            /// (신규 + 복귀) ÷ 이탈. 1보다 크면 늘고, 작으면 준다.
            var quickRatio: Double? { dormant > 0 ? Double(new + resurrected) / Double(dormant) : nil }
        }

        /// 오래된 것부터.
        let weeks: [Week]
        var isEmpty: Bool { weeks.allSatisfy { $0.active == 0 && $0.dormant == 0 } }

        static let weekCount = 12
    }

    func lifecycle(for project: String?, audience: Audience = .all,
                   calendar: Calendar = .current) -> Lifecycle {
        memoized(\.lifecycle, ScopeKey(project: project, audience: audience)) {
            let span = UsageRollups.idRetentionDays
            let axis = UsageRollups.recentDayKeys(span, calendar: calendar)
            let days = self.days(for: project, audience: audience)
            // 며칠 전 → 그날 온 설치.
            var byAgo: [Int: Set<String>] = [:]
            for (index, entry) in axis.enumerated() {
                guard let bucket = days[entry.key], !bucket.installs.isEmpty else { continue }
                byAgo[span - 1 - index] = bucket.installs
            }
            func union(_ range: ClosedRange<Int>) -> Set<String> {
                range.reduce(into: Set<String>()) { $0.formUnion(byAgo[$1] ?? []) }
            }

            let count = Lifecycle.weekCount
            // w = 0 이 가장 오래된 주. 끝나는 날(며칠 전)은 1 + 7 × (count - 1 - w).
            let oldestEnd = 1 + 7 * (count - 1)
            var seenBefore = union((oldestEnd + 7)...(span - 1))
            var previous = union((oldestEnd + 7)...(oldestEnd + 13))
            var weeks: [Lifecycle.Week] = []
            for w in 0..<count {
                let end = 1 + 7 * (count - 1 - w)
                let active = union(end...(end + 6))
                let new = active.subtracting(seenBefore)
                let retained = active.intersection(previous)
                let resurrected = active.subtracting(previous).subtracting(new)
                let dormant = previous.subtracting(active)
                let start = calendar.date(byAdding: .day, value: -(end + 6),
                                          to: calendar.startOfDay(for: Date())) ?? Date()
                weeks.append(.init(start: start, new: new.count, retained: retained.count,
                                   resurrected: resurrected.count, dormant: dormant.count))
                seenBefore.formUnion(active)
                previous = active
            }
            return Lifecycle(weeks: weeks)
        }
    }

    // MARK: - 한 달에 며칠 오는가

    /// 최근 30일 안에 온 설치가 그 30일 중 며칠 왔는가.
    ///
    /// 고착도(평균 DAU ÷ MAU)는 이 분포의 평균 하나다. 평균은 "매일 오는 소수 +
    /// 한 번 오고 끝난 다수"와 "모두가 가끔 오는 앱"을 같은 숫자로 만든다. 둘은
    /// 할 일이 정반대다 — 앞은 첫 주를 고쳐야 하고, 뒤는 다시 부를 계기를 만들어야 한다.
    struct ActiveDays {
        struct Bucket: Identifiable {
            let label: String
            let range: ClosedRange<Int>
            let count: Int
            var id: String { label }
        }

        let buckets: [Bucket]
        /// 버킷의 합. 창이 MAU와 같아서 이 숫자는 MAU와 같다.
        let total: Int
        /// 설치당 평균 활동일.
        let averageDays: Double?
        /// 이 30일 안에 깐 설치. 올 수 있었던 날이 30일보다 짧아서 앞 칸에 몰린다.
        let installedWithin: Int

        var isEmpty: Bool { total == 0 }

        static let window = 30
        static let ranges: [(String, ClosedRange<Int>)] = [
            ("1일", 1...1), ("2~3일", 2...3), ("4~7일", 4...7),
            ("8~15일", 8...15), ("16일 이상", 16...window)
        ]
    }

    func activeDays(for project: String?, audience: Audience = .all,
                    calendar: Calendar = .current) -> ActiveDays {
        memoized(\.activeDays, ScopeKey(project: project, audience: audience)) {
            let days = self.days(for: project, audience: audience)
            var counts: [String: Int] = [:]
            for key in UsageRollups.windowKeys(days: ActiveDays.window, calendar: calendar) {
                guard let bucket = days[key] else { continue }
                for install in bucket.installs { counts[install, default: 0] += 1 }
            }

            let buckets = ActiveDays.ranges.map { label, range in
                ActiveDays.Bucket(label: label, range: range,
                                  count: counts.values.filter { range.contains($0) }.count)
            }
            let total = counts.count
            let average = total > 0 ? Double(counts.values.reduce(0, +)) / Double(total) : nil

            let windowStart = calendar.date(byAdding: .day, value: -(ActiveDays.window - 1),
                                            to: calendar.startOfDay(for: Date())) ?? Date()
            let recent = snapshots(for: project, audience: audience).filter {
                counts[$0.installID] != nil && ($0.installDate ?? .distantPast) >= windowStart
            }.count

            return ActiveDays(buckets: buckets, total: total, averageDays: average,
                              installedWithin: recent)
        }
    }
}

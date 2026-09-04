//
//  UsageRollups.swift
//  FeedbackHubViewer
//
//  Usage events, summed once at the moment they arrive and never summed again.
//
//  The raw `UsageEvent` stream is the one record type that grows without bound:
//  every significant action in every app, forever. Keeping all of it and
//  re-aggregating on every screen means the hub gets slower the more it is
//  used — exactly backwards. So each event is folded into its day the first
//  time it is read, and after that only the day survives:
//
//      project → "2026-08-28" → { 건수, 그날 활동한 installID 집합, 이벤트명별 건수 }
//
//  Every number the statistics screen shows is a sum or a union over those day
//  buckets. Weeks, months and years are day buckets added up; "활동 사용자" is
//  the union of the daily installID sets, because the same install on two days
//  is one user, not two.
//
//  Above the day sits a ladder of the same sums — week, month, year — kept on
//  disk beside the days rather than rebuilt on every read. Days stay the truth;
//  a period is by definition its days added up, so the ladder is a cache with
//  an exact definition. What makes it cheap is that a fold only ever touches
//  today and, at most, the handful of days a late-arriving batch reaches back
//  to: those days' periods are the only ones re-summed. A monthly chart four
//  years deep therefore costs one dictionary read, not four years of days.
//
//  Folding is idempotent. Each day keeps the record names it has already
//  counted, so an overlapping incremental read (see `FeedbackStore.syncOverlap`)
//  or a full refresh hands the same event back without inflating anything.
//  Those name sets are the only part that is pruned: past
//  `idRetentionDays` a day is closed, its names are dropped, and any event that
//  somehow arrives for it afterwards is ignored rather than double-counted. The
//  counts themselves are kept forever — that is the whole point.
//

import Foundation

/// One project-day, already summed.
struct UsageDayBucket: Codable {
    var events = 0
    /// Distinct installs seen that day. A set rather than a count so a week or
    /// a month is a union — the same install on two days is one user.
    var installs: Set<String> = []
    /// This day's count per event name, slice included ("paywall_view:memo").
    var byEvent: [String: Int] = [:]
    /// The newest `occurredAt` folded into this day.
    var lastAt: Date?
    /// Record names already counted here. `nil` means the day is closed (its
    /// names were pruned); a late event for a closed day is dropped, since it
    /// was almost certainly counted before the pruning.
    var foldedIDs: Set<String>?

    var isClosed: Bool { foldedIDs == nil }

    /// Whether two buckets say the same thing about the day. Compares the sums
    /// and not `foldedIDs`, which is bookkeeping: a merge that only widened the
    /// set of names it has already counted changed no number on screen.
    func isSameSums(as other: UsageDayBucket) -> Bool {
        events == other.events && installs == other.installs
            && byEvent == other.byEvent && lastAt == other.lastAt
    }
}

/// One project-period above the day — a week, a month or a year — held as the
/// sum of the days inside it.
///
/// No `foldedIDs` here, and no `byEvent`: a period is never folded into
/// directly, only re-summed from its days, and nothing on screen asks a week
/// for its per-event breakdown. Keeping it to what is read keeps the file
/// small enough that the ladder is worth writing down at all.
struct UsagePeriodBucket: Codable {
    var events = 0
    /// Distinct installs across the period — the *union* of its days' sets,
    /// because one install active on Monday and Tuesday is one user.
    var installs: Set<String> = []
    var lastAt: Date?

    init() {}

    init(_ day: UsageDayBucket) {
        events = day.events
        installs = day.installs
        lastAt = day.lastAt
    }

    mutating func add(_ other: UsagePeriodBucket) {
        events += other.events
        installs.formUnion(other.installs)
        if (lastAt ?? .distantPast) < (other.lastAt ?? .distantPast) { lastAt = other.lastAt }
    }

    mutating func add(_ day: UsageDayBucket) { add(UsagePeriodBucket(day)) }
}

/// One event name's all-time total for a project. `installs` is kept as a set
/// because "이 이벤트를 보낸 설치 수" is a distinct count, and installs are the
/// bounded dimension here (hundreds), unlike the event stream itself.
struct UsageNameTotal: Codable {
    var count = 0
    var installs: Set<String> = []
    var lastAt: Date?
}

/// Every project's day buckets. Persisted next to the record cache, in its own
/// file, so painting the screen never waits on decoding the raw stream.
struct UsageRollups: Codable {

    /// Bumped when the shape below changes. Unlike the record cache, a version
    /// this file no longer understands is not simply thrown away where it can
    /// be repaired instead: the day buckets are the only copy of history the
    /// hub has once the raw events age out, so anything derivable from them is
    /// rebuilt rather than discarded. See `earliestReadableVersion`.
    static let currentVersion = 2

    /// The oldest file this version can still make sense of. A v1 file has the
    /// day buckets but not the week/month/year ladder above them — and the
    /// ladder is exactly those days added up, so it is rebuilt on load.
    static let earliestReadableVersion = 1

    /// How long a day keeps the record names it counted. Long enough that no
    /// realistic re-read reaches past it, short enough that the file does not
    /// carry every record name the hub has ever seen.
    static let idRetentionDays = 180

    var version = UsageRollups.currentVersion
    /// The zone the day boundaries were drawn in. Recorded rather than acted
    /// on: buckets already written stay where they are if the device moves, and
    /// a day-sized shift in history is not worth discarding real numbers over.
    var timeZoneIdentifier = TimeZone.current.identifier

    /// project key → day key ("yyyy-MM-dd") → bucket.
    var projects: [String: [String: UsageDayBucket]] = [:]
    /// project key → event name → all-time total.
    var eventTotals: [String: [String: UsageNameTotal]] = [:]

    // MARK: The ladder above the day

    /// project key → "2026-W35" → the week's days added up.
    var weeks: [String: [String: UsagePeriodBucket]] = [:]
    /// project key → "2026-08" → the month's days added up.
    var months: [String: [String: UsagePeriodBucket]] = [:]
    /// project key → "2026" → the year's days added up.
    var years: [String: [String: UsagePeriodBucket]] = [:]

    /// Day keys whose periods have not been re-summed yet, per project.
    /// Written by `fold`, cleared by `rebuildDirtyPeriods()`.
    ///
    /// This is what "마지막 업데이트 이후 필요한 부분만" comes down to: the
    /// ladder is not rebuilt on a schedule or on a read, but for exactly the
    /// days a refresh moved. Persisted rather than kept in memory so a refresh
    /// interrupted between the fold and the rebuild leaves the work for the
    /// next launch instead of leaving a wrong week on screen.
    var dirtyDays: [String: Set<String>] = [:]

    /// Which calendar the ladder was built in. Week boundaries follow the
    /// region's first weekday, so a device that changes region has to have the
    /// ladder rebuilt — the days underneath it are unaffected.
    var ladderCalendar = UsageRollups.calendarSignature()

    var isEmpty: Bool { projects.isEmpty }

    /// 얼마나 담고 있는가 — 두 요약본 중 어느 쪽이 더 완전한지 가늠하는 값.
    ///
    /// 정확한 뜻이 있는 숫자가 아니라 비교용이다. `merge`가 칸을 늘리기만
    /// 하므로(줄이는 경우가 없다) 합친 뒤의 이 값이 상대의 것보다 크다는 것은
    /// 곧 이쪽에만 있는 것이 있다는 뜻이고, 그것이 올릴지 말지의 기준이다.
    var weight: Int {
        projects.values.reduce(0) { running, days in
            running + days.values.reduce(0) { $0 + $1.events + $1.installs.count }
        }
    }

    /// Every project that has ever reported an event, including ones whose raw
    /// events have since aged out of the record cache.
    var projectKeys: Set<String> { Set(projects.keys) }

    init() {}

    /// Hand-written so a file from before the ladder existed still decodes:
    /// the synthesised initialiser would throw on the missing keys, and
    /// throwing here means deleting the only copy of the hub's history.
    /// Everything the ladder needs is rebuilt from the days on load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.current.identifier
        projects = try c.decodeIfPresent([String: [String: UsageDayBucket]].self, forKey: .projects) ?? [:]
        eventTotals = try c.decodeIfPresent([String: [String: UsageNameTotal]].self, forKey: .eventTotals) ?? [:]
        weeks = try c.decodeIfPresent([String: [String: UsagePeriodBucket]].self, forKey: .weeks) ?? [:]
        months = try c.decodeIfPresent([String: [String: UsagePeriodBucket]].self, forKey: .months) ?? [:]
        years = try c.decodeIfPresent([String: [String: UsagePeriodBucket]].self, forKey: .years) ?? [:]
        dirtyDays = try c.decodeIfPresent([String: Set<String>].self, forKey: .dirtyDays) ?? [:]
        ladderCalendar = try c.decodeIfPresent(String.self, forKey: .ladderCalendar) ?? ""
    }

    // MARK: - Period keys

    /// What the ladder's shape depends on. Not the time zone: day keys are
    /// already written down, and which week a given calendar date falls in
    /// depends on the region's first weekday, not on where the device is.
    static func calendarSignature(_ calendar: Calendar = .current) -> String {
        "\(calendar.identifier)|\(calendar.firstWeekday)"
    }

    /// Which rung of the ladder a number is being asked for.
    enum Granularity: String, Codable, CaseIterable {
        case day, week, month, year
    }

    /// "2026-W35". The ISO-style pair, so a week that straddles New Year keeps
    /// one key rather than splitting across two years.
    static func weekKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// "2026-08" and "2026" are prefixes of a day key, which is why day keys
    /// are written the way they are — no date arithmetic to climb two rungs.
    static func monthKey(fromDayKey day: String) -> String { String(day.prefix(7)) }
    static func yearKey(fromDayKey day: String) -> String { String(day.prefix(4)) }

    /// The start of the period a key names, for a chart axis.
    static func date(fromKey key: String, granularity: Granularity,
                     calendar: Calendar = .current) -> Date? {
        switch granularity {
        case .day:
            return date(fromDayKey: key, calendar: calendar)
        case .week:
            let parts = key.split(separator: "W")
            guard parts.count == 2, let year = Int(parts[0].dropLast()), let week = Int(parts[1]) else { return nil }
            return calendar.date(from: DateComponents(weekOfYear: week, yearForWeekOfYear: year))
        case .month:
            let parts = key.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month))
        case .year:
            guard let year = Int(key) else { return nil }
            return calendar.date(from: DateComponents(year: year))
        }
    }

    // MARK: - Day keys

    /// "yyyy-MM-dd" in the device's calendar. Built from components rather than
    /// a `DateFormatter` because this runs once per event on every read.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The start of the day a key names, for anything that needs a real `Date`
    /// back (chart axes, the sparkline).
    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The day keys for the last `days` days, oldest first — the axis a
    /// sparkline draws along, gaps included as zero.
    static func recentDayKeys(_ days: Int, calendar: Calendar = .current,
                              endingAt end: Date = Date()) -> [(key: String, date: Date)] {
        let today = calendar.startOfDay(for: end)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (key: dayKey(date, calendar: calendar), date: date)
        }
    }

    // MARK: - Folding

    /// Add freshly-read events to their days. Events already counted are
    /// skipped, so calling this with an overlapping read — or with the same
    /// read twice — changes nothing.
    ///
    /// - Returns: how many events were actually new, so a refresh that found
    ///   nothing can skip the disk write that would otherwise follow.
    @discardableResult
    mutating func fold(_ events: [UsageEvent], calendar: Calendar = .current) -> Int {
        guard !events.isEmpty else { return 0 }
        var folded = 0

        for event in events {
            let project = event.projectKey
            let key = Self.dayKey(event.occurredAt, calendar: calendar)

            var days = projects[project] ?? [:]
            var bucket = days[key] ?? UsageDayBucket(foldedIDs: [])

            // A closed day has lost the names it counted, so it can no longer
            // tell a new event from one it already has. Dropping is the safe
            // side of that trade: the alternative inflates history silently.
            guard var ids = bucket.foldedIDs else { continue }
            guard ids.insert(event.id).inserted else { continue }
            bucket.foldedIDs = ids

            bucket.events += 1
            bucket.byEvent[event.name, default: 0] += 1
            if let install = event.installID { bucket.installs.insert(install) }
            if (bucket.lastAt ?? .distantPast) < event.occurredAt { bucket.lastAt = event.occurredAt }

            days[key] = bucket
            projects[project] = days

            var totals = eventTotals[project] ?? [:]
            var total = totals[event.name] ?? UsageNameTotal()
            total.count += 1
            if let install = event.installID { total.installs.insert(install) }
            if (total.lastAt ?? .distantPast) < event.occurredAt { total.lastAt = event.occurredAt }
            totals[event.name] = total
            eventTotals[project] = totals

            // The day moved, so the week, month and year it sits in are no
            // longer their days added up. Noted rather than fixed here: one
            // day is touched by hundreds of events in a batch, and re-summing
            // its periods once at the end is the whole saving.
            dirtyDays[project, default: []].insert(key)
            folded += 1
        }
        return folded
    }

    // MARK: - The ladder

    /// Re-sum only the periods a fold touched, and nothing else.
    ///
    /// A refresh normally lands events for today and perhaps yesterday, so this
    /// re-sums one week, one month and one year per project no matter how far
    /// back the hub's history goes. That is the point: the cost of an update
    /// follows what changed, not what is stored.
    ///
    /// - Returns: whether anything moved, so a caller can skip the disk write.
    @discardableResult
    mutating func rebuildDirtyPeriods(calendar: Calendar = .current) -> Bool {
        // A region change moves every week boundary at once, so there is no
        // "part" left to update — the whole ladder is rebuilt from the days.
        guard ladderCalendar == Self.calendarSignature(calendar) else {
            rebuildLadder(calendar: calendar)
            return true
        }
        guard !dirtyDays.isEmpty else { return false }

        for (project, dirty) in dirtyDays {
            defer { dirtyDays[project] = nil }
            guard let days = projects[project] else {
                weeks[project] = nil; months[project] = nil; years[project] = nil
                continue
            }
            resum(project: project, days: days, touching: dirty, calendar: calendar)
        }
        return true
    }

    /// Build every rung from scratch. For a file written before the ladder
    /// existed, and for a device that changed region.
    mutating func rebuildLadder(calendar: Calendar = .current) {
        weeks = [:]; months = [:]; years = [:]
        for (project, days) in projects {
            resum(project: project, days: days, touching: Set(days.keys), calendar: calendar)
        }
        dirtyDays = [:]
        ladderCalendar = Self.calendarSignature(calendar)
    }

    /// Re-sum one project's periods, but only the ones `touching` names.
    ///
    /// One pass over that project's days, because a period has to be summed
    /// from *all* of its days, not only the dirty ones — a week whose Tuesday
    /// moved is still Monday through Sunday. Months and years are recognised by
    /// the day key's own prefix; only weeks need a real date, and only for days
    /// that could plausibly fall in a dirty week.
    private mutating func resum(project: String,
                                days: [String: UsageDayBucket],
                                touching dirty: Set<String>,
                                calendar: Calendar) {
        var weekKeys: Set<String> = []
        var monthKeys: Set<String> = []
        var yearKeys: Set<String> = []
        for day in dirty {
            monthKeys.insert(Self.monthKey(fromDayKey: day))
            yearKeys.insert(Self.yearKey(fromDayKey: day))
            if let date = Self.date(fromDayKey: day, calendar: calendar) {
                weekKeys.insert(Self.weekKey(date, calendar: calendar))
            }
        }
        // A dirty week reaches at most six days either side of a dirty day, so
        // days outside that range never need their date parsed.
        var weekLow = "9999", weekHigh = ""
        for day in dirty {
            guard let date = Self.date(fromDayKey: day, calendar: calendar),
                  let from = calendar.date(byAdding: .day, value: -7, to: date),
                  let to = calendar.date(byAdding: .day, value: 7, to: date) else { continue }
            weekLow = min(weekLow, Self.dayKey(from, calendar: calendar))
            weekHigh = max(weekHigh, Self.dayKey(to, calendar: calendar))
        }

        var week: [String: UsagePeriodBucket] = [:]
        var month: [String: UsagePeriodBucket] = [:]
        var year: [String: UsagePeriodBucket] = [:]
        for (day, bucket) in days {
            let monthKey = Self.monthKey(fromDayKey: day)
            if monthKeys.contains(monthKey) { month[monthKey, default: UsagePeriodBucket()].add(bucket) }
            let yearKey = Self.yearKey(fromDayKey: day)
            if yearKeys.contains(yearKey) { year[yearKey, default: UsagePeriodBucket()].add(bucket) }
            guard !weekKeys.isEmpty, day >= weekLow, day <= weekHigh,
                  let date = Self.date(fromDayKey: day, calendar: calendar) else { continue }
            let weekKey = Self.weekKey(date, calendar: calendar)
            if weekKeys.contains(weekKey) { week[weekKey, default: UsagePeriodBucket()].add(bucket) }
        }

        // Assign only the rebuilt keys. A dirty period that came out empty had
        // its last day removed, so it is taken out rather than left stale.
        var storedWeeks = weeks[project] ?? [:]
        for key in weekKeys { storedWeeks[key] = week[key] }
        weeks[project] = storedWeeks
        var storedMonths = months[project] ?? [:]
        for key in monthKeys { storedMonths[key] = month[key] }
        months[project] = storedMonths
        var storedYears = years[project] ?? [:]
        for key in yearKeys { storedYears[key] = year[key] }
        years[project] = storedYears
    }

    /// Bring a just-loaded file up to date: rebuild the ladder if it is missing
    /// or was drawn in another calendar, otherwise finish whatever a previous
    /// run left dirty.
    ///
    /// - Returns: whether the file on disk is now behind what is in memory.
    @discardableResult
    mutating func prepareLadder(calendar: Calendar = .current) -> Bool {
        if version < Self.currentVersion
            || ladderCalendar != Self.calendarSignature(calendar)
            || (weeks.isEmpty && !projects.isEmpty) {
            rebuildLadder(calendar: calendar)
            version = Self.currentVersion
            return true
        }
        return rebuildDirtyPeriods(calendar: calendar)
    }

    // MARK: - Merging two devices' sums

    /// Fold another device's day buckets into these.
    ///
    /// Two devices read the same event stream, so neither's sums are wrong —
    /// they are each *partial*, in different places. A Mac left open all summer
    /// holds days a phone installed last week never saw; a phone that finished
    /// a read the Mac abandoned holds the tail of a day the Mac stopped short
    /// of. Adding them would count the overlap twice, so nothing here adds.
    /// Every cell takes the more complete of the two:
    ///
    ///  · **활동한 설치**는 합집합이다. 같은 installID를 양쪽이 봤어도 한 명이다.
    ///  · **건수**는 큰 쪽이다. 두 기기가 같은 스트림의 앞뒤를 겹쳐 읽으므로,
    ///    더 많이 읽은 쪽이 덜 읽은 쪽을 거의 언제나 포함한다. 겹치지 않는
    ///    구간이 있으면 이 규칙은 적게 세지만, 합이 부풀리는 것보다는 낫다 —
    ///    다음 새로고침이 못 본 구간을 읽어 오면 그때 올라간다.
    ///  · **이벤트명별 건수**도 같은 이유로 이름마다 큰 쪽이다.
    ///
    /// `foldedIDs`가 열려 있는 하루끼리는 합집합이 곧 정확한 건수다 — 접기는
    /// 이름 하나에 건수 하나씩 올리므로. 한쪽이라도 닫혀 있으면(오래돼서 이름을
    /// 버린 날) 더 이상 중복을 가려낼 수 없으므로 그 하루는 닫는다. 열어 둔 채
    /// 큰 건수만 받아 오면, 그 하루의 이벤트를 다시 읽었을 때 이미 세어 둔
    /// 것을 또 세게 된다.
    ///
    /// 주·월·년 사다리는 여기서 손대지 않는다. 하루가 임의로 바뀌었으니
    /// 부분 재계산이 성립하지 않는다 — 호출한 쪽이 `rebuildLadder()`로
    /// 통째로 다시 세운다.
    ///
    /// - Returns: 이 쪽이 실제로 달라졌는지. 안 달라졌으면 디스크에 쓸 것도 없다.
    @discardableResult
    mutating func merge(_ other: UsageRollups) -> Bool {
        var changed = false

        for (project, otherDays) in other.projects {
            var days = projects[project] ?? [:]
            for (key, incoming) in otherDays {
                guard var mine = days[key] else {
                    days[key] = incoming
                    changed = true
                    continue
                }
                let before = mine
                switch (mine.foldedIDs, incoming.foldedIDs) {
                case let (ids?, other?):
                    // 둘 다 열려 있다: 이름의 합집합이 곧 건수다.
                    let union = ids.union(other)
                    mine.foldedIDs = union
                    mine.events = max(mine.events, union.count)
                default:
                    // 한쪽이라도 닫혔다: 중복을 가려낼 방법이 없으니 이 하루도
                    // 닫고, 더 많이 본 쪽의 건수를 받는다.
                    mine.foldedIDs = nil
                    mine.events = max(mine.events, incoming.events)
                }
                mine.installs.formUnion(incoming.installs)
                for (name, count) in incoming.byEvent {
                    mine.byEvent[name] = max(mine.byEvent[name] ?? 0, count)
                }
                if (mine.lastAt ?? .distantPast) < (incoming.lastAt ?? .distantPast) {
                    mine.lastAt = incoming.lastAt
                }
                if !mine.isSameSums(as: before) { changed = true }
                days[key] = mine
            }
            projects[project] = days
        }

        for (project, otherTotals) in other.eventTotals {
            var totals = eventTotals[project] ?? [:]
            for (name, incoming) in otherTotals {
                guard var mine = totals[name] else {
                    totals[name] = incoming
                    changed = true
                    continue
                }
                let before = mine
                mine.count = max(mine.count, incoming.count)
                mine.installs.formUnion(incoming.installs)
                if (mine.lastAt ?? .distantPast) < (incoming.lastAt ?? .distantPast) {
                    mine.lastAt = incoming.lastAt
                }
                if mine.count != before.count || mine.installs != before.installs { changed = true }
                totals[name] = mine
            }
            eventTotals[project] = totals
        }

        return changed
    }

    /// Close days older than `idRetentionDays`: their counts stay, the record
    /// names they were built from go. This is what keeps the file from growing
    /// in step with the event stream.
    mutating func pruneIdentifiers(calendar: Calendar = .current, now: Date = Date()) {
        guard let cutoffDate = calendar.date(byAdding: .day, value: -Self.idRetentionDays,
                                             to: calendar.startOfDay(for: now)) else { return }
        let cutoff = Self.dayKey(cutoffDate, calendar: calendar)
        for (project, days) in projects {
            var updated = days
            var touched = false
            for (key, bucket) in days where key < cutoff && !bucket.isClosed {
                var closed = bucket
                closed.foldedIDs = nil
                updated[key] = closed
                touched = true
            }
            if touched { projects[project] = updated }
        }
    }

    /// The record names a read is told it can stop at — the newest ones, and
    /// only as many of them as it takes.
    ///
    /// A read runs newest-first and stops at a short run of records this device
    /// already holds, so the only names it can ever compare against are the
    /// ones at the frontier: the newest days. Handing it all of them meant
    /// rebuilding a set of every event the hub had ever seen on every refresh —
    /// 8,000 strings on this device today, and the same history over a busy
    /// year is nearer 600,000, rebuilt once a minute by the auto-refresh.
    ///
    /// So the walk goes newest day first and stops once it holds comfortably
    /// more than the run a read needs. Stopping early is safe rather than
    /// wrong: a name left out means the record is read once more and folded
    /// once more, and folding is idempotent — it changes no number. The only
    /// cost of falling short is a few more pages read, which is why `minimum`
    /// sits far above `CloudKitService.knownRunToStop` rather than near it.
    ///
    /// Closed days contribute nothing, which is fine: reads never get that far.
    func knownEventIDs(atLeast minimum: Int = 200) -> Set<String> {
        var byDay: [String: [Set<String>]] = [:]
        for days in projects.values {
            for (day, bucket) in days {
                guard let folded = bucket.foldedIDs, !folded.isEmpty else { continue }
                byDay[day, default: []].append(folded)
            }
        }
        var ids: Set<String> = []
        // Newest day first. A whole day is taken at a time — a boundary that
        // cut into the middle of one would depend on an ordering CloudKit does
        // not promise for records written in the same batch.
        for day in byDay.keys.sorted(by: >) {
            for folded in byDay[day, default: []] { ids.formUnion(folded) }
            if ids.count >= minimum { break }
        }
        return ids
    }

    // MARK: - Reading

    /// The day buckets for one scope, merged. `nil` means every project;
    /// `excluding` takes out the projects the user has hidden.
    ///
    /// Merging unions the daily install sets, so "활동 사용자" across the whole
    /// hub counts an install once even when it appears under two apps.
    func days(for project: String?, excluding hidden: Set<String> = []) -> [String: UsageDayBucket] {
        if let project {
            guard !hidden.contains(project) else { return [:] }
            return projects[project] ?? [:]
        }
        var merged: [String: UsageDayBucket] = [:]
        for (key, days) in projects where !hidden.contains(key) {
            for (day, bucket) in days {
                guard var existing = merged[day] else { merged[day] = bucket; continue }
                existing.events += bucket.events
                existing.installs.formUnion(bucket.installs)
                for (name, count) in bucket.byEvent { existing.byEvent[name, default: 0] += count }
                if (existing.lastAt ?? .distantPast) < (bucket.lastAt ?? .distantPast) {
                    existing.lastAt = bucket.lastAt
                }
                existing.foldedIDs = nil    // never read from a merged bucket
                merged[day] = existing
            }
        }
        return merged
    }

    /// One rung of the ladder for one scope, merged across projects the same
    /// way `days(for:excluding:)` merges days.
    ///
    /// `.day` is projected from the day buckets; the rest are read straight
    /// out of the ladder, which is what makes a monthly or yearly chart cost
    /// the same whether the hub holds a month of history or five years of it.
    func buckets(_ granularity: Granularity, for project: String?,
                 excluding hidden: Set<String> = []) -> [String: UsagePeriodBucket] {
        guard granularity != .day else {
            return days(for: project, excluding: hidden).mapValues(UsagePeriodBucket.init)
        }
        let source: [String: [String: UsagePeriodBucket]]
        switch granularity {
        case .week:  source = weeks
        case .month: source = months
        default:     source = years
        }
        if let project {
            guard !hidden.contains(project) else { return [:] }
            return source[project] ?? [:]
        }
        var merged: [String: UsagePeriodBucket] = [:]
        for (key, buckets) in source where !hidden.contains(key) {
            for (period, bucket) in buckets { merged[period, default: UsagePeriodBucket()].add(bucket) }
        }
        return merged
    }

    /// All-time totals per event name for one scope, merged the same way.
    func totals(for project: String?, excluding hidden: Set<String> = []) -> [String: UsageNameTotal] {
        if let project {
            guard !hidden.contains(project) else { return [:] }
            return eventTotals[project] ?? [:]
        }
        var merged: [String: UsageNameTotal] = [:]
        for (key, totals) in eventTotals where !hidden.contains(key) {
            for (name, total) in totals {
                guard var existing = merged[name] else { merged[name] = total; continue }
                existing.count += total.count
                existing.installs.formUnion(total.installs)
                if (existing.lastAt ?? .distantPast) < (total.lastAt ?? .distantPast) {
                    existing.lastAt = total.lastAt
                }
                merged[name] = existing
            }
        }
        return merged
    }

    /// A window of days, as a summary. `days` is a merged bucket map from
    /// `days(for:excluding:)`; `keys` the axis to add up.
    ///
    /// Windows here are whole days, not a rolling `now - 7 × 86,400`: the
    /// numbers come from day buckets, so "최근 7일" is today plus the six days
    /// before it. That also stops the figure drifting between two renders a few
    /// seconds apart.
    static func window(_ days: [String: UsageDayBucket], keys: [String]) -> (events: Int, installs: Int) {
        var events = 0
        var installs: Set<String> = []
        for key in keys {
            guard let bucket = days[key] else { continue }
            events += bucket.events
            installs.formUnion(bucket.installs)
        }
        return (events, installs.count)
    }

    /// The last `count` days ending today, oldest first, as day keys.
    static func windowKeys(days count: Int, endingDaysAgo offset: Int = 0,
                           calendar: Calendar = .current, now: Date = Date()) -> [String] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: -(index + offset), to: today) else { return nil }
            return dayKey(date, calendar: calendar)
        }
    }
}

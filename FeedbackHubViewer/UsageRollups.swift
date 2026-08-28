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

    /// Bumped when the shape below changes; a mismatch throws the file away and
    /// the next full read rebuilds it.
    static let currentVersion = 1

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

    var isEmpty: Bool { projects.isEmpty }

    /// Every project that has ever reported an event, including ones whose raw
    /// events have since aged out of the record cache.
    var projectKeys: Set<String> { Set(projects.keys) }

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

            folded += 1
        }
        return folded
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

    /// Every record name still remembered — what a read is told it can stop at.
    /// Closed days contribute nothing, which is fine: reads run newest-first,
    /// so they never get that far.
    var knownEventIDs: Set<String> {
        var ids: Set<String> = []
        for days in projects.values {
            for bucket in days.values {
                if let folded = bucket.foldedIDs { ids.formUnion(folded) }
            }
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

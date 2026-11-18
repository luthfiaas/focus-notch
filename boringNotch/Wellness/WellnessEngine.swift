//
//  WellnessEngine.swift
//  boringNotch
//
//  The rules behind the focus timer, rest reminders, prayer times and statistics.
//  Ported from the earlier Focus Notch app; MECHANICS.md there describes every rule.
//

import Foundation

// MARK: - Time helpers

enum WTime {
    static func now() -> Double { Date().timeIntervalSince1970 }

    /// The zone chosen in settings ("System" = this computer's).
    static func zone(_ g: WellnessGeneral) -> TimeZone {
        if g.timezone != "System", let z = TimeZone(identifier: g.timezone) { return z }
        return .current
    }

    static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2 // Monday
        return c
    }

    private static func dayFormatter(_ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar(zone)
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Local date key ("yyyy-MM-dd") of a unix time.
    static func day(_ ts: Double, _ zone: TimeZone) -> String {
        dayFormatter(zone).string(from: Date(timeIntervalSince1970: ts))
    }

    /// Unix time of local midnight of a date key.
    static func dayStart(_ day: String, _ zone: TimeZone) -> Double {
        dayFormatter(zone).date(from: day)?.timeIntervalSince1970 ?? 0
    }

    static func addDays(_ day: String, _ n: Int, _ zone: TimeZone) -> String {
        let cal = calendar(zone)
        let start = Date(timeIntervalSince1970: dayStart(day, zone))
        let d = cal.date(byAdding: .day, value: n, to: start) ?? start
        return dayFormatter(zone).string(from: d)
    }

    /// Monday of the week containing `day`.
    static func weekStart(_ day: String, _ zone: TimeZone) -> String {
        let cal = calendar(zone)
        let d = Date(timeIntervalSince1970: dayStart(day, zone))
        let weekday = cal.component(.weekday, from: d) // 1 = Sunday
        let back = (weekday + 5) % 7
        return addDays(day, -back, zone)
    }

    /// Minutes since local midnight.
    static func minuteOfDay(_ ts: Double, _ zone: TimeZone) -> Int {
        let cal = calendar(zone)
        let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ts))
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func inWindow(_ minute: Int, _ start: Int, _ end: Int) -> Bool {
        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    /// "16:47" for a countdown.
    static func clock(_ secs: Double) -> String {
        let s = max(0, Int(secs.rounded(.up)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "1h 23m" / "25m" / "40s".
    static func duration(_ secs: Double) -> String {
        let s = Int(secs)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// Time of day for a unix time ("15:00" or "3:00 PM").
    static func timeOfDay(_ ts: Double, _ g: WellnessGeneral) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone(g)
        f.dateFormat = g.time24h ? "HH:mm" : "h:mm a"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}

// MARK: - Focus timer

enum PomoEvent {
    case focusDone
    case breakDone(PomoPhase)
}

extension PomoState {
    /// Interrupted focus shorter than this is treated as an accidental start and not recorded.
    static let minRecordedSecs: Double = 60
    /// If the app notices a phase ended later than this (closed or asleep), the next phase waits.
    static let autoStartGraceSecs: Double = 60

    var isRunning: Bool { runningSince != nil }
    var isIdle: Bool { phaseStart == nil }

    func elapsed(_ now: Double) -> Double {
        elapsedBefore + (runningSince.map { max(0, now - $0) } ?? 0)
    }
    func remaining(_ now: Double) -> Double { max(0, plannedSecs - elapsed(now)) }
    func progress(_ now: Double) -> Double { min(1, max(0, elapsed(now) / max(1, plannedSecs))) }

    /// Focus seconds of the session in progress (not yet recorded anywhere).
    func liveFocus(_ now: Double) -> Double {
        (phase == .focus && !isIdle) ? min(elapsed(now), plannedSecs) : 0
    }

    /// Keep an idle phase in step with changed settings.
    mutating func syncSettings(_ s: PomodoroSettings) {
        if isIdle { plannedSecs = Double(phase.minutes(s) * 60) }
    }

    mutating func start(_ now: Double) {
        guard runningSince == nil else { return }
        if phaseStart == nil { phaseStart = now }
        runningSince = now
    }

    mutating func pause(_ now: Double) {
        if let since = runningSince {
            elapsedBefore += max(0, now - since)
            runningSince = nil
        }
    }

    private mutating func enter(_ p: PomoPhase, _ s: PomodoroSettings) {
        phase = p
        plannedSecs = Double(p.minutes(s) * 60)
        elapsedBefore = 0
        runningSince = nil
        phaseStart = nil
    }

    /// Record the focus done so far as interrupted (if long enough to count).
    private func recordInterrupted(_ now: Double, _ log: inout [FocusSession], _ zone: TimeZone) {
        guard phase == .focus, let start = phaseStart else { return }
        let focus = min(elapsed(now), plannedSecs)
        guard focus >= Self.minRecordedSecs else { return }
        log.append(FocusSession(startTs: start, endTs: now, focusSecs: focus, plannedSecs: plannedSecs,
                                status: .interrupted, date: WTime.day(start, zone)))
    }

    /// Stop the current phase and set its timer back to full.
    mutating func reset(_ now: Double, _ s: PomodoroSettings, _ log: inout [FocusSession], _ zone: TimeZone) {
        recordInterrupted(now, &log, zone)
        enter(phase, s)
    }

    /// Back to the first focus session of a new cycle.
    mutating func resetCycle(_ now: Double, _ s: PomodoroSettings, _ log: inout [FocusSession], _ zone: TimeZone) {
        recordInterrupted(now, &log, zone)
        completedInCycle = 0
        enter(.focus, s)
    }

    /// Jump to the next phase. Skipped focus counts as interrupted, never as completed.
    mutating func skip(_ now: Double, _ s: PomodoroSettings, _ log: inout [FocusSession], _ zone: TimeZone) {
        recordInterrupted(now, &log, zone)
        enter(phase == .focus ? .shortBreak : .focus, s)
    }

    /// Choose a phase by hand.
    mutating func choose(_ p: PomoPhase, _ now: Double, _ s: PomodoroSettings, _ log: inout [FocusSession], _ zone: TimeZone) {
        guard p != phase else { return }
        recordInterrupted(now, &log, zone)
        enter(p, s)
    }

    /// Advance the timer; returns what finished.
    mutating func tick(_ now: Double, _ s: PomodoroSettings, _ log: inout [FocusSession], _ zone: TimeZone) -> PomoEvent? {
        guard let since = runningSince, elapsed(now) >= plannedSecs else { return nil }
        // The exact moment the phase ran out, even if noticed late.
        let end = since + max(0, plannedSecs - elapsedBefore)
        let finished = phase
        let event: PomoEvent
        if finished == .focus {
            let start = phaseStart ?? since
            log.append(FocusSession(startTs: start, endTs: end, focusSecs: plannedSecs, plannedSecs: plannedSecs,
                                    status: .completed, date: WTime.day(start, zone)))
            completedInCycle += 1
            if completedInCycle >= max(1, s.longEvery) {
                completedInCycle = 0
                enter(.longBreak, s)
            } else {
                enter(.shortBreak, s)
            }
            event = .focusDone
        } else {
            enter(.focus, s)
            event = .breakDone(finished)
        }
        let auto = finished == .focus ? s.autoStartBreaks : s.autoStartFocus
        if auto && now - end <= Self.autoStartGraceSecs {
            phaseStart = end
            runningSince = end
        }
        return event
    }
}

// MARK: - Rest reminders

enum RestReminders {
    private static func hours(_ d: WellnessData, _ cfg: ReminderSettings) -> (Int, Int) {
        cfg.customHours ? (cfg.start, cfg.end) : (d.general.workStart, d.general.workEnd)
    }

    static func allowedNow(_ d: WellnessData, _ kind: ReminderKind, _ now: Double) -> Bool {
        let cfg = d.reminder(kind)
        guard cfg.useWorkHours else { return true }
        let (s, e) = hours(d, cfg)
        return WTime.inWindow(WTime.minuteOfDay(now, WTime.zone(d.general)), s, e)
    }

    /// The next moment working hours begin (today or tomorrow).
    private static func nextWindowStart(_ d: WellnessData, _ kind: ReminderKind, _ now: Double) -> Double {
        let zone = WTime.zone(d.general)
        let (s, _) = hours(d, d.reminder(kind))
        let today = WTime.day(now, zone)
        var at = WTime.dayStart(today, zone) + Double(s * 60)
        if at <= now { at = WTime.dayStart(WTime.addDays(today, 1, zone), zone) + Double(s * 60) }
        return at
    }

    static func intervalSecs(_ cfg: ReminderSettings) -> Double { Double(max(1, cfg.intervalMin) * 60) }

    private static func isBusy(_ rt: ReminderRuntime, _ kind: ReminderKind) -> Bool {
        rt.queue.contains { $0.kind == kind } || rt.snoozed.contains { $0.kind == kind }
    }

    /// After the app was closed: don't fire reminders that went stale while it was away.
    static func onLaunch(_ d: inout WellnessData, _ now: Double) {
        for kind in ReminderKind.allCases {
            let int = intervalSecs(d.reminder(kind))
            let due = d.reminderRt.nextDue[kind.index]
            if due > 0 && now - due > int { d.reminderRt.nextDue[kind.index] = now + int }
        }
        // A countdown that ran out while the app was closed did finish.
        let finished: [(Int, Double)] = d.reminderRt.queue.compactMap { a in
            guard let start = a.countdownStart else { return nil }
            let dur = Double(d.reminder(a.kind).durationSecs)
            return now - start >= dur ? (a.eventId, start + dur) : nil
        }
        for (id, at) in finished { resolve(&d, id, .completed, at, now) }
    }

    /// Run once a second: schedule, trigger and queue reminders. Returns kinds newly shown.
    static func tick(_ d: inout WellnessData, _ now: Double) -> [ReminderKind] {
        var shown: [ReminderKind] = []
        for kind in ReminderKind.allCases {
            let cfg = d.reminder(kind)
            let i = kind.index
            if !cfg.enabled {
                // Turned off: forget anything waiting.
                let ids = d.reminderRt.queue.filter { $0.kind == kind }.map(\.eventId)
                d.reminderRt.queue.removeAll { $0.kind == kind }
                d.reminderRt.snoozed.removeAll { $0.kind == kind }
                d.reminderEvents.removeAll { ids.contains($0.id) && $0.outcome == .pending }
                d.reminderRt.nextDue[i] = 0
                continue
            }
            if isBusy(d.reminderRt, kind) { continue }
            if d.reminderRt.nextDue[i] <= 0 {
                d.reminderRt.nextDue[i] = now + intervalSecs(cfg)
                continue
            }
            if now < d.reminderRt.nextDue[i] { continue }
            if !allowedNow(d, kind, now) {
                d.reminderRt.nextDue[i] = nextWindowStart(d, kind, now) + intervalSecs(cfg)
                continue
            }
            trigger(&d, kind, now)
        }
        // Snoozed reminders come back into the queue.
        let back = d.reminderRt.snoozed.filter { $0.until <= now }
        d.reminderRt.snoozed.removeAll { $0.until <= now }
        for s in back {
            d.reminderRt.queue.append(ActiveReminder(eventId: s.eventId, kind: s.kind, shownTs: nil, countdownStart: nil))
        }
        // The front of the queue is the one on screen.
        if !d.reminderRt.queue.isEmpty, d.reminderRt.queue[0].shownTs == nil {
            d.reminderRt.queue[0].shownTs = now
            shown.append(d.reminderRt.queue[0].kind)
        }
        // A running countdown that reached zero marks the reminder done.
        if let front = d.reminderRt.queue.first, let start = front.countdownStart {
            let dur = Double(d.reminder(front.kind).durationSecs)
            if now - start >= dur { resolve(&d, front.eventId, .completed, start + dur, now) }
        }
        return shown
    }

    /// Fire a reminder now (also used by "Try it now").
    static func trigger(_ d: inout WellnessData, _ kind: ReminderKind, _ now: Double) {
        guard !isBusy(d.reminderRt, kind) else { return }
        d.nextEventId += 1
        let id = d.nextEventId
        d.reminderEvents.append(ReminderEvent(id: id, kind: kind, triggeredTs: now, resolvedTs: nil, outcome: .pending, snoozes: 0))
        d.reminderRt.queue.append(ActiveReminder(eventId: id, kind: kind, shownTs: nil, countdownStart: nil))
        d.reminderRt.nextDue[kind.index] = Double.greatestFiniteMagnitude
    }

    static func startCountdown(_ d: inout WellnessData, _ eventId: Int, _ now: Double) {
        if let i = d.reminderRt.queue.firstIndex(where: { $0.eventId == eventId }), d.reminderRt.queue[i].countdownStart == nil {
            d.reminderRt.queue[i].countdownStart = now
        }
    }

    static func snooze(_ d: inout WellnessData, _ eventId: Int, _ now: Double) {
        guard let pos = d.reminderRt.queue.firstIndex(where: { $0.eventId == eventId }) else { return }
        let a = d.reminderRt.queue.remove(at: pos)
        let mins = Double(max(1, d.reminder(a.kind).snoozeMin))
        d.reminderRt.snoozed.append(SnoozedReminder(eventId: a.eventId, kind: a.kind, until: now + mins * 60))
        if let e = d.reminderEvents.firstIndex(where: { $0.id == eventId }) { d.reminderEvents[e].snoozes += 1 }
    }

    static func resolve(_ d: inout WellnessData, _ eventId: Int, _ outcome: ReminderOutcome, _ at: Double, _ now: Double) {
        var kind: ReminderKind?
        if let i = d.reminderRt.queue.firstIndex(where: { $0.eventId == eventId }) {
            kind = d.reminderRt.queue[i].kind
            d.reminderRt.queue.remove(at: i)
        }
        if let e = d.reminderEvents.firstIndex(where: { $0.id == eventId }) {
            d.reminderEvents[e].outcome = outcome
            d.reminderEvents[e].resolvedTs = at
            kind = d.reminderEvents[e].kind
        }
        if let k = kind {
            let int = intervalSecs(d.reminder(k))
            d.reminderRt.nextDue[k.index] = max(at, now - int) + int
        }
    }

    static func nextDue(_ d: WellnessData, _ kind: ReminderKind) -> Double? {
        let v = d.reminderRt.nextDue[kind.index]
        return (v > 0 && v < Double.greatestFiniteMagnitude / 2) ? v : nil
    }

    struct Counts {
        var triggered = 0, completed = 0, skipped = 0
    }

    static func counts(_ d: WellnessData, _ kind: ReminderKind?, from: Double, to: Double) -> Counts {
        var c = Counts()
        for e in d.reminderEvents where (kind == nil || kind == e.kind) && e.triggeredTs >= from && e.triggeredTs < to {
            c.triggered += 1
            if e.outcome == .completed { c.completed += 1 }
            if e.outcome == .skipped { c.skipped += 1 }
        }
        return c
    }
}

// MARK: - Prayer times (astronomical method, as on PrayTimes.org)

enum PrayerTimes {
    static let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    static let localNames = ["Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"]

    private enum IshaRule { case angle(Double), minutes(Double) }

    /// Fajr angle, Isha rule, Maghrib angle (nil = sunset).
    private static func params(_ m: PrayerMethod) -> (Double, IshaRule, Double?) {
        switch m {
        case .auto, .mwl, .turkey: return (18, .angle(17), nil)
        case .isna: return (15, .angle(15), nil)
        case .egypt: return (19.5, .angle(17.5), nil)
        case .makkah: return (18.5, .minutes(90), nil)
        case .karachi: return (18, .angle(18), nil)
        case .tehran: return (17.7, .angle(14), 4.5)
        case .kemenag, .jakim, .singapore: return (20, .angle(18), nil)
        case .dubai: return (18.2, .angle(18.2), nil)
        case .qatar: return (18, .minutes(90), nil)
        case .kuwait: return (18, .angle(17.5), nil)
        case .france: return (12, .angle(12), nil)
        case .russia: return (16, .angle(15), nil)
        }
    }

    /// The method a country's authorities use; Muslim World League elsewhere.
    static func method(forCountry code: String) -> PrayerMethod {
        switch code.uppercased() {
        case "ID": return .kemenag
        case "MY", "BN": return .jakim
        case "SG": return .singapore
        case "TR": return .turkey
        case "SA", "YE": return .makkah
        case "EG", "SY", "IQ", "LB", "LY", "SD": return .egypt
        case "PK", "IN", "BD", "AF": return .karachi
        case "US", "CA": return .isna
        case "IR": return .tehran
        case "AE", "OM": return .dubai
        case "QA", "BH": return .qatar
        case "KW": return .kuwait
        case "FR": return .france
        case "RU": return .russia
        default: return .mwl
        }
    }

    static func resolve(_ m: PrayerMethod, _ loc: PrayerLocation?) -> PrayerMethod {
        guard m == .auto else { return m }
        return loc.map { method(forCountry: $0.countryCode) } ?? .mwl
    }

    private static func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private static func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private static func darctan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
    private static func fix(_ a: Double, _ b: Double) -> Double {
        let r = a - b * floor(a / b)
        return r < 0 ? r + b : r
    }

    private static func julian(_ y: Int, _ m: Int, _ d: Int) -> Double {
        var y = Double(y), m = Double(m)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(d) + b - 1524.5
    }

    private static func sunPosition(_ jd: Double) -> (decl: Double, eqt: Double) {
        let d = jd - 2451545.0
        let g = fix(357.529 + 0.98560028 * d, 360)
        let q = fix(280.459 + 0.98564736 * d, 360)
        let l = fix(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g), 360)
        let e = 23.439 - 0.00000036 * d
        let ra = darctan2(dcos(e) * dsin(l), dcos(l)) / 15
        return (darcsin(dsin(e) * dsin(l)), q / 15 - fix(ra, 24))
    }

    private struct Calc {
        let jd: Double
        let lat: Double
        func midDay(_ t: Double) -> Double { PrayerTimes.fix(12 - PrayerTimes.sunPosition(jd + t).eqt, 24) }
        func sunAngleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double {
            let decl = PrayerTimes.sunPosition(jd + t).decl
            let noon = midDay(t)
            let x = (-PrayerTimes.dsin(angle) - PrayerTimes.dsin(decl) * PrayerTimes.dsin(lat))
                / (PrayerTimes.dcos(decl) * PrayerTimes.dcos(lat))
            let tt = PrayerTimes.darccos(x) / 15
            return noon + (ccw ? -tt : tt)
        }
        func asrTime(_ factor: Double, _ t: Double) -> Double {
            let decl = PrayerTimes.sunPosition(jd + t).decl
            let angle = -PrayerTimes.darccot(factor + PrayerTimes.dtan(abs(lat - decl)))
            return sunAngleTime(angle, t, ccw: false)
        }
    }

    /// Hours after local midnight: [Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha].
    static func computeHours(year: Int, month: Int, day: Int, lat: Double, lon: Double, tzHours: Double,
                             method: PrayerMethod, asr: AsrMethod) -> [Double] {
        let (fajrAngle, ishaRule, maghribAngle) = params(method)
        let calc = Calc(jd: julian(year, month, day) - lon / (15 * 24), lat: lat)
        let riseset = 0.833
        var t: [Double] = [5, 6, 12, 13, 18, 18, 18]
        for _ in 0..<2 {
            let p = t.map { $0 / 24 }
            let ishaT: Double
            switch ishaRule {
            case .angle(let a): ishaT = calc.sunAngleTime(a, p[6], ccw: false)
            case .minutes: ishaT = 18
            }
            t = [
                calc.sunAngleTime(fajrAngle, p[0], ccw: true),
                calc.sunAngleTime(riseset, p[1], ccw: true),
                calc.midDay(p[2]),
                calc.asrTime(asr.factor, p[3]),
                calc.sunAngleTime(riseset, p[4], ccw: false),
                calc.sunAngleTime(maghribAngle ?? riseset, p[5], ccw: false),
                ishaT,
            ]
        }
        let adj = tzHours - lon / 15
        t = t.map { $0 + adj }
        let sunrise = t[1], sunset = t[4]
        // Higher latitudes: keep Fajr and Isha within a share of the night.
        let night = fix(sunrise - sunset, 24)
        let fajrCap = fajrAngle / 60 * night
        if t[0].isNaN || fix(sunrise - t[0], 24) > fajrCap { t[0] = sunrise - fajrCap }
        if case .angle(let a) = ishaRule {
            let cap = a / 60 * night
            if t[6].isNaN || fix(t[6] - sunset, 24) > cap { t[6] = sunset + cap }
        }
        if let a = maghribAngle {
            let cap = a / 60 * night
            if t[5].isNaN || fix(t[5] - sunset, 24) > cap { t[5] = sunset + cap }
        }
        let maghrib = t[5]
        let isha: Double
        switch ishaRule {
        case .minutes(let m): isha = maghrib + m / 60
        case .angle: isha = t[6]
        }
        return [t[0], t[1], t[2], t[3], maghrib, isha]
    }

    struct Day {
        let date: String
        /// Unix times for Fajr, Dhuhr, Asr, Maghrib, Isha.
        let times: [Double]
        let sunrise: Double
        let method: PrayerMethod
    }

    /// The day's schedule for a date key, in the location's own time zone.
    static func schedule(_ date: String, _ loc: PrayerLocation, _ s: PrayerSettings) -> Day {
        let zone = TimeZone(identifier: loc.timezone) ?? .current
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let (y, mo, d) = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (2000, 1, 1)
        let midnight = WTime.dayStart(date, zone)
        let tz = Double(zone.secondsFromGMT(for: Date(timeIntervalSince1970: midnight + 12 * 3600))) / 3600
        let m = resolve(s.method, loc)
        let h = computeHours(year: y, month: mo, day: d, lat: loc.lat, lon: loc.lon, tzHours: tz, method: m, asr: s.asr)
        // Hours after local midnight → unix time (offset fixed for the day).
        let at = { (hours: Double) -> Double in midnight + hours * 3600 }
        let idx = [0, 2, 3, 4, 5]
        let times = idx.enumerated().map { i, k in at(h[k]) + Double(s.adjust[i] * 60) }
        return Day(date: date, times: times, sunrise: at(h[1]), method: m)
    }

    /// Places offered without an internet connection.
    static let builtinCities: [PrayerLocation] = [
        ("Jakarta", "DKI Jakarta", "Indonesia", "ID", -6.2088, 106.8456, "Asia/Jakarta"),
        ("Bandung", "West Java", "Indonesia", "ID", -6.9175, 107.6191, "Asia/Jakarta"),
        ("Surabaya", "East Java", "Indonesia", "ID", -7.2575, 112.7521, "Asia/Jakarta"),
        ("Semarang", "Central Java", "Indonesia", "ID", -6.9667, 110.4167, "Asia/Jakarta"),
        ("Yogyakarta", "Yogyakarta", "Indonesia", "ID", -7.7956, 110.3695, "Asia/Jakarta"),
        ("Medan", "North Sumatra", "Indonesia", "ID", 3.5952, 98.6722, "Asia/Jakarta"),
        ("Palembang", "South Sumatra", "Indonesia", "ID", -2.9761, 104.7754, "Asia/Jakarta"),
        ("Padang", "West Sumatra", "Indonesia", "ID", -0.9471, 100.4172, "Asia/Jakarta"),
        ("Banda Aceh", "Aceh", "Indonesia", "ID", 5.5483, 95.3238, "Asia/Jakarta"),
        ("Pekanbaru", "Riau", "Indonesia", "ID", 0.5071, 101.4478, "Asia/Jakarta"),
        ("Pontianak", "West Kalimantan", "Indonesia", "ID", -0.0263, 109.3425, "Asia/Pontianak"),
        ("Denpasar", "Bali", "Indonesia", "ID", -8.6705, 115.2126, "Asia/Makassar"),
        ("Makassar", "South Sulawesi", "Indonesia", "ID", -5.1477, 119.4327, "Asia/Makassar"),
        ("Balikpapan", "East Kalimantan", "Indonesia", "ID", -1.2379, 116.8529, "Asia/Makassar"),
        ("Manado", "North Sulawesi", "Indonesia", "ID", 1.4748, 124.8421, "Asia/Makassar"),
        ("Jayapura", "Papua", "Indonesia", "ID", -2.5337, 140.7181, "Asia/Jayapura"),
        ("Kuala Lumpur", "", "Malaysia", "MY", 3.139, 101.6869, "Asia/Kuala_Lumpur"),
        ("Singapore", "", "Singapore", "SG", 1.3521, 103.8198, "Asia/Singapore"),
        ("Bandar Seri Begawan", "", "Brunei", "BN", 4.9031, 114.9398, "Asia/Brunei"),
        ("Bangkok", "", "Thailand", "TH", 13.7563, 100.5018, "Asia/Bangkok"),
        ("Manila", "", "Philippines", "PH", 14.5995, 120.9842, "Asia/Manila"),
        ("Makkah", "", "Saudi Arabia", "SA", 21.3891, 39.8579, "Asia/Riyadh"),
        ("Madinah", "", "Saudi Arabia", "SA", 24.5247, 39.5692, "Asia/Riyadh"),
        ("Riyadh", "", "Saudi Arabia", "SA", 24.7136, 46.6753, "Asia/Riyadh"),
        ("Dubai", "", "United Arab Emirates", "AE", 25.2048, 55.2708, "Asia/Dubai"),
        ("Doha", "", "Qatar", "QA", 25.2854, 51.531, "Asia/Qatar"),
        ("Kuwait City", "", "Kuwait", "KW", 29.3759, 47.9774, "Asia/Kuwait"),
        ("Cairo", "", "Egypt", "EG", 30.0444, 31.2357, "Africa/Cairo"),
        ("Istanbul", "", "Turkey", "TR", 41.0082, 28.9784, "Europe/Istanbul"),
        ("Tehran", "", "Iran", "IR", 35.6892, 51.389, "Asia/Tehran"),
        ("Karachi", "", "Pakistan", "PK", 24.8607, 67.0011, "Asia/Karachi"),
        ("Lahore", "", "Pakistan", "PK", 31.5204, 74.3587, "Asia/Karachi"),
        ("Dhaka", "", "Bangladesh", "BD", 23.8103, 90.4125, "Asia/Dhaka"),
        ("Delhi", "", "India", "IN", 28.7041, 77.1025, "Asia/Kolkata"),
        ("Mumbai", "", "India", "IN", 19.076, 72.8777, "Asia/Kolkata"),
        ("Casablanca", "", "Morocco", "MA", 33.5731, -7.5898, "Africa/Casablanca"),
        ("Lagos", "", "Nigeria", "NG", 6.5244, 3.3792, "Africa/Lagos"),
        ("Johannesburg", "", "South Africa", "ZA", -26.2041, 28.0473, "Africa/Johannesburg"),
        ("London", "", "United Kingdom", "GB", 51.5074, -0.1278, "Europe/London"),
        ("Paris", "", "France", "FR", 48.8566, 2.3522, "Europe/Paris"),
        ("Berlin", "", "Germany", "DE", 52.52, 13.405, "Europe/Berlin"),
        ("Amsterdam", "", "Netherlands", "NL", 52.3676, 4.9041, "Europe/Amsterdam"),
        ("Moscow", "", "Russia", "RU", 55.7558, 37.6173, "Europe/Moscow"),
        ("New York", "New York", "United States", "US", 40.7128, -74.006, "America/New_York"),
        ("Chicago", "Illinois", "United States", "US", 41.8781, -87.6298, "America/Chicago"),
        ("Los Angeles", "California", "United States", "US", 34.0522, -118.2437, "America/Los_Angeles"),
        ("Toronto", "Ontario", "Canada", "CA", 43.6532, -79.3832, "America/Toronto"),
        ("Sydney", "New South Wales", "Australia", "AU", -33.8688, 151.2093, "Australia/Sydney"),
        ("Melbourne", "Victoria", "Australia", "AU", -37.8136, 144.9631, "Australia/Melbourne"),
        ("Tokyo", "", "Japan", "JP", 35.6762, 139.6503, "Asia/Tokyo"),
    ].map { PrayerLocation(name: $0.0, region: $0.1, country: $0.2, countryCode: $0.3, lat: $0.4, lon: $0.5, timezone: $0.6) }

    /// Search any city by name with the free Open-Meteo geocoding service.
    static func searchOnline(_ q: String) async throws -> [PrayerLocation] {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            .init(name: "name", value: q.trimmingCharacters(in: .whitespaces)),
            .init(name: "count", value: "12"), .init(name: "language", value: "en"), .init(name: "format", value: "json"),
        ]
        let (bytes, _) = try await URLSession.shared.data(from: comps.url!)
        guard let obj = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
            let s = { (k: String) in (r[k] as? String) ?? "" }
            return PrayerLocation(name: s("name"), region: s("admin1"), country: s("country"),
                                  countryCode: s("country_code"), lat: lat, lon: lon, timezone: s("timezone"))
        }
    }

    /// Approximate location from this computer's internet connection (city level).
    static func locateByNetwork() async throws -> PrayerLocation {
        if let (bytes, _) = try? await URLSession.shared.data(from: URL(string: "https://ipapi.co/json/")!),
           let v = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let lat = v["latitude"] as? Double, let lon = v["longitude"] as? Double {
            let s = { (k: String) in (v[k] as? String) ?? "" }
            return PrayerLocation(name: s("city"), region: s("region"), country: s("country_name"),
                                  countryCode: s("country_code"), lat: lat, lon: lon, timezone: s("timezone"))
        }
        let url = URL(string: "http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,lat,lon,timezone")!
        let (bytes, _) = try await URLSession.shared.data(from: url)
        guard let v = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              (v["status"] as? String) == "success" else {
            throw NSError(domain: "FocusNotch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The location service could not place this connection."])
        }
        let s = { (k: String) in (v[k] as? String) ?? "" }
        return PrayerLocation(name: s("city"), region: s("regionName"), country: s("country"),
                              countryCode: s("countryCode"), lat: (v["lat"] as? Double) ?? 0,
                              lon: (v["lon"] as? Double) ?? 0, timezone: s("timezone"))
    }
}

// MARK: - Statistics

enum WellnessStats {
    struct Focus {
        /// All focus time, completed and interrupted (each second counted once).
        var totalSecs: Double = 0
        var completed = 0
        var completedSecs: Double = 0
        var interrupted = 0
        var interruptedSecs: Double = 0
        /// Focus of the session still running (already inside `totalSecs`).
        var liveSecs: Double = 0
        var sessions: Int { completed + interrupted }
        var averageSecs: Double { sessions == 0 ? 0 : (totalSecs - liveSecs) / Double(sessions) }
    }

    /// Focus between two date keys (end exclusive), including the session in progress.
    static func focus(_ d: WellnessData, from: String, to: String, now: Double) -> Focus {
        var f = Focus()
        for s in d.sessions where s.date >= from && s.date < to {
            f.totalSecs += s.focusSecs
            if s.status == .completed { f.completed += 1; f.completedSecs += s.focusSecs }
            else { f.interrupted += 1; f.interruptedSecs += s.focusSecs }
        }
        let live = d.pomo.liveFocus(now)
        if live > 0 {
            let day = WTime.day(d.pomo.phaseStart ?? now, WTime.zone(d.general))
            if day >= from && day < to {
                f.totalSecs += live
                f.liveSecs = live
            }
        }
        return f
    }

    static func waterOn(_ d: WellnessData, _ day: String) -> Int {
        let zone = WTime.zone(d.general)
        return d.waterLog.filter { WTime.day($0.ts, zone) == day }.reduce(0) { $0 + $1.ml }
    }

    static func prayersDone(_ d: WellnessData, _ day: String) -> Int {
        (d.prayersDone[day] ?? []).filter { $0 }.count
    }
}

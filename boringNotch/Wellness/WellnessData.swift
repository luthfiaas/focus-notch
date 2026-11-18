//
//  WellnessData.swift
//  boringNotch
//
//  Everything the focus / water / rest / prayer features remember, saved as one JSON file.
//  The format is the same as the earlier Focus Notch (Rust) app's data.json.
//

import Foundation

// MARK: - Lenient decoding helpers

extension KeyedDecodingContainer {
    /// Decode a value, falling back to a default when it is missing or unreadable.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    /// Decode an optional value (missing, null or unreadable → nil).
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

/// Any JSON value, kept as-is so fields this app does not use survive a save.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Enums (raw values match the earlier app's file)

enum PomoPhase: String, Codable, CaseIterable {
    case focus = "Focus"
    case shortBreak = "ShortBreak"
    case longBreak = "LongBreak"

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    func minutes(_ s: PomodoroSettings) -> Int {
        switch self {
        case .focus: return max(1, s.focusMin)
        case .shortBreak: return max(1, s.shortMin)
        case .longBreak: return max(1, s.longMin)
        }
    }
}

enum SessionStatus: String, Codable {
    case completed = "Completed"
    case interrupted = "Interrupted"
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case eye = "Eye"
    case stretch = "Stretch"
    case stand = "Stand"

    var id: String { rawValue }
    var index: Int {
        switch self {
        case .eye: return 0
        case .stretch: return 1
        case .stand: return 2
        }
    }
    var title: String {
        switch self {
        case .eye: return "Eye rest"
        case .stretch: return "Stretch break"
        case .stand: return "Stand up"
        }
    }
    var symbol: String {
        switch self {
        case .eye: return "eye"
        case .stretch: return "figure.flexibility"
        case .stand: return "figure.walk"
        }
    }
    func message(_ secs: Int) -> String {
        let d = (secs >= 60 && secs % 60 == 0) ? "\(secs / 60) minutes" : "\(secs) seconds"
        switch self {
        case .eye: return "Look at something about 20 feet (6 m) away for \(d)."
        case .stretch: return "Time for a short stretch: \(d)."
        case .stand: return "Stand up and move around for \(d)."
        }
    }
}

enum ReminderOutcome: String, Codable {
    case pending = "Pending"
    case completed = "Completed"
    case skipped = "Skipped"
}

enum PrayerMethod: String, Codable, CaseIterable, Identifiable {
    case auto = "Auto", mwl = "Mwl", isna = "Isna", egypt = "Egypt", makkah = "Makkah"
    case karachi = "Karachi", tehran = "Tehran", kemenag = "Kemenag", jakim = "Jakim"
    case singapore = "Singapore", turkey = "Turkey", dubai = "Dubai", qatar = "Qatar"
    case kuwait = "Kuwait", france = "France", russia = "Russia"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic (by country)"
        case .mwl: return "Muslim World League"
        case .isna: return "Islamic Society of North America"
        case .egypt: return "Egyptian General Authority"
        case .makkah: return "Umm al-Qura, Makkah"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .tehran: return "Institute of Geophysics, Tehran"
        case .kemenag: return "Kemenag (Indonesia)"
        case .jakim: return "JAKIM (Malaysia)"
        case .singapore: return "MUIS (Singapore)"
        case .turkey: return "Diyanet (Turkey)"
        case .dubai: return "Dubai"
        case .qatar: return "Qatar"
        case .kuwait: return "Kuwait"
        case .france: return "UOIF (France)"
        case .russia: return "Spiritual Administration of Russia"
        }
    }
}

enum AsrMethod: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard"
    case hanafi = "Hanafi"
    var id: String { rawValue }
    var label: String { self == .standard ? "Standard (Shafi'i, Maliki, Hanbali)" : "Hanafi" }
    var factor: Double { self == .standard ? 1 : 2 }
}

// MARK: - Settings

struct WellnessGeneral: Codable {
    var name = ""
    var timezone = "System"
    var time24h = true
    var dateFormat = "Long"
    var theme = "System"
    var workStart = 9 * 60
    var workEnd = 17 * 60
    var desktopNotifications = true
    var soundName = "Glass"

    enum CodingKeys: String, CodingKey {
        case name, timezone, theme
        case time24h = "time_24h", dateFormat = "date_format", workStart = "work_start", workEnd = "work_end"
        case desktopNotifications = "desktop_notifications", soundName = "sound_name"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WellnessGeneral()
        name = c.value(.name, d.name)
        timezone = c.value(.timezone, d.timezone)
        time24h = c.value(.time24h, d.time24h)
        dateFormat = c.value(.dateFormat, d.dateFormat)
        theme = c.value(.theme, d.theme)
        workStart = c.value(.workStart, d.workStart)
        workEnd = c.value(.workEnd, d.workEnd)
        desktopNotifications = c.value(.desktopNotifications, d.desktopNotifications)
        soundName = c.value(.soundName, d.soundName)
    }
}

struct PomodoroSettings: Codable {
    var focusMin = 25
    var shortMin = 5
    var longMin = 15
    var longEvery = 4
    var autoStartBreaks = true
    var autoStartFocus = true
    var notify = true
    var sound = true

    enum CodingKeys: String, CodingKey {
        case focusMin = "focus_min", shortMin = "short_min", longMin = "long_min", longEvery = "long_every"
        case autoStartBreaks = "auto_start_breaks", autoStartFocus = "auto_start_focus", notify, sound
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroSettings()
        focusMin = c.value(.focusMin, d.focusMin)
        shortMin = c.value(.shortMin, d.shortMin)
        longMin = c.value(.longMin, d.longMin)
        longEvery = c.value(.longEvery, d.longEvery)
        autoStartBreaks = c.value(.autoStartBreaks, d.autoStartBreaks)
        autoStartFocus = c.value(.autoStartFocus, d.autoStartFocus)
        notify = c.value(.notify, d.notify)
        sound = c.value(.sound, d.sound)
    }
}

struct WaterSettings: Codable {
    var goalMl = 2000
    var quick = [150, 250, 350, 500]

    enum CodingKeys: String, CodingKey { case goalMl = "goal_ml", quick }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalMl = c.value(.goalMl, 2000)
        quick = c.value(.quick, [150, 250, 350, 500])
    }
}

struct ReminderSettings: Codable {
    var enabled = true
    var intervalMin = 20
    var durationSecs = 20
    var snoozeMin = 5
    /// Only remind inside working hours.
    var useWorkHours = true
    /// Own working hours instead of the general ones.
    var customHours = false
    var start = 9 * 60
    var end = 17 * 60
    var sound = true
    var desktopNotify = true

    static func defaults(for kind: ReminderKind) -> ReminderSettings {
        var s = ReminderSettings()
        switch kind {
        case .eye: s.intervalMin = 20; s.durationSecs = 20
        case .stretch: s.intervalMin = 50; s.durationSecs = 30
        case .stand: s.intervalMin = 60; s.durationSecs = 120
        }
        return s
    }

    enum CodingKeys: String, CodingKey {
        case enabled, start, end, sound
        case intervalMin = "interval_min", durationSecs = "duration_secs", snoozeMin = "snooze_min"
        case useWorkHours = "use_work_hours", customHours = "custom_hours", desktopNotify = "desktop_notify"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        enabled = c.value(.enabled, d.enabled)
        intervalMin = c.value(.intervalMin, d.intervalMin)
        durationSecs = c.value(.durationSecs, d.durationSecs)
        snoozeMin = c.value(.snoozeMin, d.snoozeMin)
        useWorkHours = c.value(.useWorkHours, d.useWorkHours)
        customHours = c.value(.customHours, d.customHours)
        start = c.value(.start, d.start)
        end = c.value(.end, d.end)
        sound = c.value(.sound, d.sound)
        desktopNotify = c.value(.desktopNotify, d.desktopNotify)
    }
}

struct PrayerLocation: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var region: String
    var country: String
    var countryCode: String
    var lat: Double
    var lon: Double
    var timezone: String

    var id: String { "\(name)|\(region)|\(country)|\(lat)|\(lon)" }
    var label: String {
        var parts = [name]
        if !region.isEmpty && region != name { parts.append(region) }
        if !country.isEmpty { parts.append(country) }
        return parts.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case name, region, country, lat, lon, timezone
        case countryCode = "country_code"
    }
}

struct PrayerSettings: Codable {
    var enabled = false
    var location: PrayerLocation?
    var locationAuto = false
    var method: PrayerMethod = .auto
    var asr: AsrMethod = .standard
    /// Manual minute adjustments: Fajr, Dhuhr, Asr, Maghrib, Isha.
    var adjust = [0, 0, 0, 0, 0]
    var notify = [true, true, true, true, true]
    /// 0, 5 or 10 minutes before.
    var beforeMin = 10
    var sound = true
    var tracking = true
    var askedLocation = false

    enum CodingKeys: String, CodingKey {
        case enabled, location, method, asr, adjust, notify, sound, tracking
        case locationAuto = "location_auto", beforeMin = "before_min", askedLocation = "asked_location"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrayerSettings()
        enabled = c.value(.enabled, d.enabled)
        location = c.optional(.location)
        locationAuto = c.value(.locationAuto, d.locationAuto)
        method = c.value(.method, d.method)
        asr = c.value(.asr, d.asr)
        adjust = c.value(.adjust, d.adjust)
        notify = c.value(.notify, d.notify)
        beforeMin = c.value(.beforeMin, d.beforeMin)
        sound = c.value(.sound, d.sound)
        tracking = c.value(.tracking, d.tracking)
        askedLocation = c.value(.askedLocation, d.askedLocation)
        if adjust.count != 5 { adjust = d.adjust }
        if notify.count != 5 { notify = d.notify }
    }
}

// MARK: - Records

struct FocusSession: Codable {
    var startTs: Double
    var endTs: Double
    /// Seconds actually spent focusing (pauses excluded).
    var focusSecs: Double
    var plannedSecs: Double
    var status: SessionStatus
    /// Local date ("yyyy-MM-dd") of the session's start.
    var date: String

    enum CodingKeys: String, CodingKey {
        case status, date
        case startTs = "start_ts", endTs = "end_ts", focusSecs = "focus_secs", plannedSecs = "planned_secs"
    }
}

struct WaterEntry: Codable {
    var ts: Double
    var ml: Int
}

struct ReminderEvent: Codable {
    var id: Int
    var kind: ReminderKind
    var triggeredTs: Double
    var resolvedTs: Double?
    var outcome: ReminderOutcome
    var snoozes: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, outcome, snoozes
        case triggeredTs = "triggered_ts", resolvedTs = "resolved_ts"
    }
}

struct ActiveReminder: Codable {
    var eventId: Int
    var kind: ReminderKind
    /// Set the first time this reminder reaches the front of the queue.
    var shownTs: Double?
    /// Set when the person presses Start.
    var countdownStart: Double?

    enum CodingKeys: String, CodingKey {
        case kind
        case eventId = "event_id", shownTs = "shown_ts", countdownStart = "countdown_start"
    }
}

/// A snoozed reminder: (event id, kind, when it comes back), stored as a 3-element array.
struct SnoozedReminder: Codable {
    var eventId: Int
    var kind: ReminderKind
    var until: Double

    init(eventId: Int, kind: ReminderKind, until: Double) {
        self.eventId = eventId
        self.kind = kind
        self.until = until
    }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        eventId = try c.decode(Int.self)
        kind = try c.decode(ReminderKind.self)
        until = try c.decode(Double.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(eventId)
        try c.encode(kind)
        try c.encode(until)
    }
}

struct ReminderRuntime: Codable {
    /// Next due time per kind (Eye, Stretch, Stand); 0 means "not scheduled yet".
    var nextDue: [Double] = [0, 0, 0]
    var queue: [ActiveReminder] = []
    var snoozed: [SnoozedReminder] = []

    enum CodingKeys: String, CodingKey { case nextDue = "next_due", queue, snoozed }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextDue = c.value(.nextDue, [0, 0, 0])
        if nextDue.count != 3 { nextDue = [0, 0, 0] }
        queue = c.value(.queue, [])
        snoozed = c.value(.snoozed, [])
    }
}

struct PomoState: Codable {
    var phase: PomoPhase = .focus
    var plannedSecs: Double = 25 * 60
    /// Time counted before the current run (sum of earlier runs, so pauses never count).
    var elapsedBefore: Double = 0
    /// When the current run started; nil while paused or idle.
    var runningSince: Double?
    /// When this phase was first started.
    var phaseStart: Double?
    /// Completed focus sessions since the last long break.
    var completedInCycle = 0

    enum CodingKeys: String, CodingKey {
        case phase
        case plannedSecs = "planned_secs", elapsedBefore = "elapsed_before", runningSince = "running_since"
        case phaseStart = "phase_start", completedInCycle = "completed_in_cycle"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = c.value(.phase, .focus)
        plannedSecs = c.value(.plannedSecs, 25 * 60)
        elapsedBefore = c.value(.elapsedBefore, 0)
        runningSince = c.optional(.runningSince)
        phaseStart = c.optional(.phaseStart)
        completedInCycle = c.value(.completedInCycle, 0)
    }
    func encode(to encoder: Encoder) throws {
        // Write nulls explicitly, like the earlier app.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase, forKey: .phase)
        try c.encode(plannedSecs, forKey: .plannedSecs)
        try c.encode(elapsedBefore, forKey: .elapsedBefore)
        try c.encode(runningSince, forKey: .runningSince)
        try c.encode(phaseStart, forKey: .phaseStart)
        try c.encode(completedInCycle, forKey: .completedInCycle)
    }
}

// MARK: - Screen time

struct ScreenDay: Codable {
    /// Seconds the screen was in use (unlocked, awake and not idle).
    var total: Double = 0
    /// Seconds per app (bundle identifier).
    var apps: [String: Double] = [:]
    /// Seconds in each local hour, 0–23.
    var hours: [Double] = Array(repeating: 0, count: 24)
    /// Number of times the screen was unlocked or woke up.
    var pickups = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.value(.total, 0)
        apps = c.value(.apps, [:])
        hours = c.value(.hours, Array(repeating: 0, count: 24))
        if hours.count != 24 { hours = Array(repeating: 0, count: 24) }
        pickups = c.value(.pickups, 0)
    }
}

struct ScreenTimeSettings: Codable {
    var enabled = true
    /// No keyboard or mouse input for this long counts as away.
    var idleSecs = 120
    /// Daily limit in minutes (0 = none); a notice shows once when it is passed.
    var dailyLimitMin = 0

    enum CodingKeys: String, CodingKey { case enabled, idleSecs = "idle_secs", dailyLimitMin = "daily_limit_min" }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, true)
        idleSecs = c.value(.idleSecs, 120)
        dailyLimitMin = c.value(.dailyLimitMin, 0)
    }
}

// MARK: - The whole file

struct WellnessData: Codable {
    var general = WellnessGeneral()
    var pomodoro = PomodoroSettings()
    var water = WaterSettings()
    var eye = ReminderSettings.defaults(for: .eye)
    var stretch = ReminderSettings.defaults(for: .stretch)
    var stand = ReminderSettings.defaults(for: .stand)
    var prayer = PrayerSettings()
    /// The earlier app's notch settings; kept untouched (the notch itself is Boring Notch's now).
    var notch: JSONValue = .null

    var pomo = PomoState()
    var sessions: [FocusSession] = []
    var waterLog: [WaterEntry] = []
    /// The goal that applied on each day, so changing the goal never rewrites history.
    var waterGoals: [String: Int] = [:]
    var reminderEvents: [ReminderEvent] = []
    var reminderRt = ReminderRuntime()
    var prayersDone: [String: [Bool]] = [:]
    var prayerNotified: [String] = []
    var nextEventId = 0
    /// Screen time per local day ("yyyy-MM-dd"), kept for the last 60 days.
    var screenTime: [String: ScreenDay] = [:]
    /// App names by bundle identifier, for showing screen time.
    var appNames: [String: String] = [:]
    var screenTimeSettings = ScreenTimeSettings()
    var countdown = CountdownState()

    enum CodingKeys: String, CodingKey {
        case general, pomodoro, water, eye, stretch, stand, prayer, notch, pomo, sessions
        case waterLog = "water_log", waterGoals = "water_goals", reminderEvents = "reminder_events"
        case reminderRt = "reminder_rt", prayersDone = "prayers_done", prayerNotified = "prayer_notified"
        case nextEventId = "next_event_id"
        case screenTime = "screen_time", appNames = "app_names", screenTimeSettings = "screen_time_settings"
        case countdown
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WellnessData()
        general = c.value(.general, d.general)
        pomodoro = c.value(.pomodoro, d.pomodoro)
        water = c.value(.water, d.water)
        eye = c.value(.eye, d.eye)
        stretch = c.value(.stretch, d.stretch)
        stand = c.value(.stand, d.stand)
        prayer = c.value(.prayer, d.prayer)
        notch = c.value(.notch, .null)
        pomo = c.value(.pomo, d.pomo)
        sessions = c.value(.sessions, [])
        waterLog = c.value(.waterLog, [])
        waterGoals = c.value(.waterGoals, [:])
        reminderEvents = c.value(.reminderEvents, [])
        reminderRt = c.value(.reminderRt, d.reminderRt)
        prayersDone = c.value(.prayersDone, [:])
        prayerNotified = c.value(.prayerNotified, [])
        nextEventId = c.value(.nextEventId, 0)
        screenTime = c.value(.screenTime, [:])
        appNames = c.value(.appNames, [:])
        screenTimeSettings = c.value(.screenTimeSettings, ScreenTimeSettings())
        countdown = c.value(.countdown, CountdownState())
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(general, forKey: .general)
        try c.encode(pomodoro, forKey: .pomodoro)
        try c.encode(water, forKey: .water)
        try c.encode(eye, forKey: .eye)
        try c.encode(stretch, forKey: .stretch)
        try c.encode(stand, forKey: .stand)
        try c.encode(prayer, forKey: .prayer)
        if notch != .null { try c.encode(notch, forKey: .notch) }
        try c.encode(pomo, forKey: .pomo)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(waterLog, forKey: .waterLog)
        try c.encode(waterGoals, forKey: .waterGoals)
        try c.encode(reminderEvents, forKey: .reminderEvents)
        try c.encode(reminderRt, forKey: .reminderRt)
        try c.encode(prayersDone, forKey: .prayersDone)
        try c.encode(prayerNotified, forKey: .prayerNotified)
        try c.encode(nextEventId, forKey: .nextEventId)
        try c.encode(screenTime, forKey: .screenTime)
        try c.encode(appNames, forKey: .appNames)
        try c.encode(screenTimeSettings, forKey: .screenTimeSettings)
        try c.encode(countdown, forKey: .countdown)
    }

    func reminder(_ kind: ReminderKind) -> ReminderSettings {
        switch kind {
        case .eye: return eye
        case .stretch: return stretch
        case .stand: return stand
        }
    }

    mutating func setReminder(_ kind: ReminderKind, _ s: ReminderSettings) {
        switch kind {
        case .eye: eye = s
        case .stretch: stretch = s
        case .stand: stand = s
        }
    }

    func waterGoal(on day: String) -> Int {
        if let g = waterGoals[day] { return g }
        // Days before any recorded goal use the closest earlier goal, else the current one.
        if let earlier = waterGoals.keys.filter({ $0 < day }).max(), let g = waterGoals[earlier] { return g }
        return water.goalMl
    }

    // MARK: Storage

    static var fileURL: URL {
        // The app is sandboxed, so this is inside its own container.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FocusNotch", isDirectory: true).appendingPathComponent("data.json")
    }

    static func load() -> WellnessData {
        let url = fileURL
        guard let bytes = try? Data(contentsOf: url) else { return WellnessData() }
        do {
            return try JSONDecoder().decode(WellnessData.self, from: bytes)
        } catch {
            // Keep the unreadable file aside instead of losing it.
            let aside = url.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return WellnessData()
        }
    }

    func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let bytes = try? enc.encode(self) else { return }
        // Write next to the file, then swap it in (same as the earlier app).
        let tmp = url.deletingPathExtension().appendingPathExtension("tmp")
        do {
            try bytes.write(to: tmp)
            _ = rename(tmp.path, url.path)
        } catch {
            try? bytes.write(to: url)
        }
    }
}

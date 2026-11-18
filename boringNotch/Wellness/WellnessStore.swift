//
//  WellnessStore.swift
//  boringNotch
//
//  The live state behind the Focus, Water, Rest and Prayer tabs: runs once a second,
//  saves the data file, and announces events in the notch and as desktop notifications.
//

import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class WellnessStore: ObservableObject {
    static let shared = WellnessStore()

    /// Everything saved to disk. Changing it marks the file for saving.
    @Published var data: WellnessData { didSet { dirty = true } }
    /// Ticks once a second so countdowns redraw.
    @Published private(set) var now: Double = WTime.now()
    /// A short message shown in the closed notch for `peekDuration` seconds.
    @Published private(set) var peek: Peek?

    struct Peek: Equatable {
        let symbol: String
        let text: String
        let color: Color
        let until: Double
    }

    /// How long an event shows in the closed notch (Boring Notch's waitInterval default: 3 s).
    static let peekDuration: Double = 3

    static let focusColor = Color(red: 1.0, green: 0.42, blue: 0.29)
    static let breakColor = Color(red: 0.30, green: 0.80, blue: 0.55)
    static let longBreakColor = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let waterColor = Color(red: 0.16, green: 0.55, blue: 1.0)
    static let restColor = Color(red: 0.70, green: 0.42, blue: 1.0)
    static let prayerColor = Color(red: 1.0, green: 0.80, blue: 0.0)
    static let screenColor = Color(red: 0.25, green: 0.85, blue: 0.85)

    private var dirty = false
    /// When the countdown's ring last sounded.
    var lastRing: Double = 0
    private var timer: Timer?
    private var lastSave: Double = 0
    private var started = false

    private init() {
        data = WellnessData.load()
        dirty = false
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        let n = WTime.now()
        data.pomo.syncSettings(data.pomodoro)
        RestReminders.onLaunch(&data, n)
        ScreenTimeTracker.shared.start()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        tick()
    }

    func saveNow() {
        data.save()
        dirty = false
        lastSave = WTime.now()
    }

    var zone: TimeZone { WTime.zone(data.general) }
    var today: String { WTime.day(now, zone) }

    // MARK: Once a second

    private func tick() {
        let n = WTime.now()
        now = n
        let zone = self.zone

        // Focus timer.
        var pomo = data.pomo
        var sessions = data.sessions
        if let event = pomo.tick(n, data.pomodoro, &sessions, zone) {
            data.pomo = pomo
            data.sessions = sessions
            announcePomo(event)
        }

        // Rest reminders.
        var d = data
        let shown = RestReminders.tick(&d, n)
        if d.reminderRt.nextDue != data.reminderRt.nextDue || d.reminderRt.queue.count != data.reminderRt.queue.count
            || d.reminderRt.snoozed.count != data.reminderRt.snoozed.count || !shown.isEmpty
            || d.reminderRt.queue.first?.countdownStart != data.reminderRt.queue.first?.countdownStart {
            data = d
        }
        for kind in shown { announceReminder(kind) }

        // Countdown timer.
        tickCountdown(n)

        // Prayer notifications.
        checkPrayers(n)

        // Screen time.
        var st = data
        if ScreenTimeTracker.shared.tick(&st, now: n) {
            data = st
            checkScreenLimit()
        }

        if let p = peek, n >= p.until { withAnimation(.smooth) { peek = nil } }

        // Save at most every 5 s while things change (and on quit).
        if dirty && n - lastSave >= 5 { saveNow() }
    }

    // MARK: Focus timer actions

    func toggleTimer() {
        let n = WTime.now()
        if data.pomo.isRunning { data.pomo.pause(n) } else { data.pomo.start(n) }
        now = n
    }

    func resetTimer() {
        let n = WTime.now()
        var p = data.pomo, log = data.sessions
        p.reset(n, data.pomodoro, &log, zone)
        data.pomo = p
        data.sessions = log
    }

    func skipPhase() {
        let n = WTime.now()
        var p = data.pomo, log = data.sessions
        p.skip(n, data.pomodoro, &log, zone)
        data.pomo = p
        data.sessions = log
    }

    func choosePhase(_ phase: PomoPhase) {
        let n = WTime.now()
        var p = data.pomo, log = data.sessions
        p.choose(phase, n, data.pomodoro, &log, zone)
        data.pomo = p
        data.sessions = log
    }

    func pomodoroSettingsChanged() {
        data.pomo.syncSettings(data.pomodoro)
    }

    static func color(_ phase: PomoPhase) -> Color {
        switch phase {
        case .focus: return focusColor
        case .shortBreak: return breakColor
        case .longBreak: return longBreakColor
        }
    }

    // MARK: Water

    var waterToday: Int { WellnessStats.waterOn(data, today) }
    var waterGoalToday: Int { data.waterGoal(on: today) }

    func addWater(_ ml: Int) {
        guard ml > 0 else { return }
        let before = waterToday
        let goal = waterGoalToday
        data.waterGoals[today] = goal
        data.waterLog.append(WaterEntry(ts: WTime.now(), ml: min(ml, 5000)))
        if before < goal && waterToday >= goal {
            showPeek(symbol: "drop.fill", text: "Water goal reached", color: Self.waterColor)
            notify(title: "Water goal reached", body: "\(Self.liters(waterToday)) today. Nice work.", sound: true)
        }
    }

    func undoWater() {
        let zone = self.zone
        if let i = data.waterLog.lastIndex(where: { WTime.day($0.ts, zone) == today }) {
            data.waterLog.remove(at: i)
        }
    }

    func setWaterGoal(_ ml: Int) {
        data.water.goalMl = max(250, min(10000, ml))
        data.waterGoals[today] = data.water.goalMl
    }

    static func liters(_ ml: Int) -> String {
        // 2000 → "2 L", 1500 → "1.5 L", 1350 → "1.35 L"
        var s = String(format: "%.2f", Double(ml) / 1000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + " L"
    }

    // MARK: Rest reminders

    var activeReminder: ActiveReminder? { data.reminderRt.queue.first }

    func startReminder() {
        guard let a = activeReminder else { return }
        RestReminders.startCountdown(&data, a.eventId, WTime.now())
    }

    func snoozeReminder() {
        guard let a = activeReminder else { return }
        RestReminders.snooze(&data, a.eventId, WTime.now())
    }

    func skipReminder() {
        guard let a = activeReminder else { return }
        let n = WTime.now()
        RestReminders.resolve(&data, a.eventId, .skipped, n, n)
    }

    func doneReminder() {
        guard let a = activeReminder else { return }
        let n = WTime.now()
        RestReminders.resolve(&data, a.eventId, .completed, n, n)
    }

    func tryReminder(_ kind: ReminderKind) {
        RestReminders.trigger(&data, kind, WTime.now())
        tick()
    }

    func setReminderEnabled(_ kind: ReminderKind, _ on: Bool) {
        var s = data.reminder(kind)
        s.enabled = on
        data.setReminder(kind, s)
    }

    // MARK: Prayer

    var prayerDay: PrayerTimes.Day? {
        guard let loc = data.prayer.location else { return nil }
        return PrayerTimes.schedule(WTime.day(now, TimeZone(identifier: loc.timezone) ?? zone), loc, data.prayer)
    }

    /// The next prayer (today, or Fajr tomorrow): index and unix time.
    var nextPrayer: (index: Int, time: Double)? {
        guard let loc = data.prayer.location, let day = prayerDay else { return nil }
        if let i = day.times.firstIndex(where: { $0 > now }) { return (i, day.times[i]) }
        let locZone = TimeZone(identifier: loc.timezone) ?? zone
        let tomorrow = PrayerTimes.schedule(WTime.addDays(day.date, 1, locZone), loc, data.prayer)
        return (0, tomorrow.times[0])
    }

    func togglePrayerDone(_ index: Int) {
        guard let day = prayerDay else { return }
        var arr = data.prayersDone[day.date] ?? [false, false, false, false, false]
        if arr.count != 5 { arr = [false, false, false, false, false] }
        arr[index].toggle()
        data.prayersDone[day.date] = arr
    }

    func isPrayerDone(_ index: Int) -> Bool {
        guard let day = prayerDay, let arr = data.prayersDone[day.date], arr.count == 5 else { return false }
        return arr[index]
    }

    func setLocation(_ loc: PrayerLocation, auto: Bool) {
        data.prayer.location = loc
        data.prayer.locationAuto = auto
        data.prayer.askedLocation = true
        data.prayer.enabled = true
    }

    @Published var locating = false
    @Published var locationError: String?

    /// Ask a location service for the city of this internet connection (only when the person asks).
    func detectLocation() {
        locating = true
        locationError = nil
        Task {
            do {
                let loc = try await PrayerTimes.locateByNetwork()
                self.setLocation(loc, auto: true)
            } catch {
                self.locationError = error.localizedDescription
            }
            self.locating = false
        }
    }

    private func checkPrayers(_ n: Double) {
        guard data.prayer.enabled, let loc = data.prayer.location, let day = prayerDay else { return }
        let before = Double(data.prayer.beforeMin * 60)
        var notified = Set(data.prayerNotified)
        let startCount = notified.count
        for i in 0..<5 where data.prayer.notify[i] {
            let t = day.times[i]
            let name = "\(PrayerTimes.localNames[i]) / \(PrayerTimes.names[i])"
            if before > 0 {
                let key = "\(day.date)-\(i)-pre"
                if n >= t - before && n < t && !notified.contains(key) {
                    notified.insert(key)
                    showPeek(symbol: "moon.stars.fill", text: "\(PrayerTimes.localNames[i]) in \(data.prayer.beforeMin)m", color: Self.prayerColor)
                    notify(title: "\(name) in \(data.prayer.beforeMin) minutes",
                           body: "At \(WTime.timeOfDay(t, data.general)) · \(loc.name)", sound: data.prayer.sound)
                }
            }
            let key = "\(day.date)-\(i)"
            // Announce at the time (and up to 2 minutes late, e.g. after waking).
            if n >= t && n < t + 120 && !notified.contains(key) {
                notified.insert(key)
                showPeek(symbol: "moon.stars.fill", text: "\(PrayerTimes.localNames[i]) now", color: Self.prayerColor)
                notify(title: "Time for \(name)", body: "\(WTime.timeOfDay(t, data.general)) · \(loc.name)", sound: data.prayer.sound)
            }
        }
        if notified.count != startCount {
            // Keep only the last few days of keys.
            let cutoff = WTime.addDays(day.date, -3, zone)
            data.prayerNotified = notified.filter { $0 >= cutoff }.sorted()
        }
    }

    // MARK: Screen time

    var screenToday: ScreenDay { data.screenTime[today] ?? ScreenDay() }

    func screenDay(_ day: String) -> ScreenDay { data.screenTime[day] ?? ScreenDay() }

    private func checkScreenLimit() {
        let limit = data.screenTimeSettings.dailyLimitMin
        guard limit > 0, screenToday.total >= Double(limit * 60) else { return }
        let key = "screenLimitNotified"
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        showPeek(symbol: "hourglass", text: "Screen time \(WTime.duration(screenToday.total))", color: Self.screenColor)
        notify(title: "Daily screen time reached", body: "\(WTime.duration(screenToday.total)) on screen today. Time for a longer break?", sound: true)
    }

    // MARK: Announcing

    func showPeek(symbol: String, text: String, color: Color) {
        withAnimation(.smooth) {
            peek = Peek(symbol: symbol, text: text, color: color, until: WTime.now() + Self.peekDuration)
        }
    }

    private func announcePomo(_ event: PomoEvent) {
        let p = data.pomodoro
        switch event {
        case .focusDone:
            let next = data.pomo.phase
            showPeek(symbol: "checkmark.circle.fill", text: "Focus done · \(next.label.lowercased())", color: Self.focusColor)
            if p.notify { notify(title: "Focus session complete", body: "Next: \(next.label.lowercased()) (\(next.minutes(p)) min).", sound: p.sound) }
        case .breakDone(let phase):
            showPeek(symbol: "brain.head.profile", text: "Break over · focus", color: Self.breakColor)
            if p.notify { notify(title: "\(phase.label) over", body: "Ready for the next focus session.", sound: p.sound) }
        }
    }

    private func announceReminder(_ kind: ReminderKind) {
        let cfg = data.reminder(kind)
        showPeek(symbol: kind.symbol, text: kind.title, color: Self.restColor)
        // Open on the Rest tab next time the notch opens.
        BoringViewCoordinator.shared.currentView = .rest
        if cfg.desktopNotify { notify(title: kind.title, body: kind.message(cfg.durationSecs), sound: cfg.sound) }
        else if cfg.sound { playSound() }
    }

    private func notify(title: String, body: String, sound: Bool) {
        if sound { playSound() }
        guard data.general.desktopNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func postNotification(title: String, body: String, sound: Bool) {
        notify(title: title, body: body, sound: sound)
    }

    func ringSound() { playSound() }

    private func playSound() {
        NSSound(named: NSSound.Name(data.general.soundName))?.play()
    }
}

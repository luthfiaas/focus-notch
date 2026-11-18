//
//  CountdownTimer.swift
//  boringNotch
//
//  A plain countdown timer, separate from the focus timer: set a length, start it, and the
//  notch rings when it reaches zero. Survives quitting the app (it keeps counting from its start).
//

import SwiftUI

// MARK: - State

struct CountdownState: Codable {
    /// Length of the countdown in seconds.
    var duration: Double = 5 * 60
    /// Time counted before the current run (pauses never count).
    var elapsedBefore: Double = 0
    /// When the current run started; nil while paused or idle.
    var runningSince: Double?
    /// When it reached zero; set while it is ringing, cleared when stopped.
    var ringingSince: Double?
    /// Recently used lengths (seconds), newest first.
    var recent: [Double] = []

    static let maxDuration: Double = 24 * 3600
    /// The ring stops by itself after this long.
    static let ringFor: Double = 30

    enum CodingKeys: String, CodingKey {
        case duration, recent
        case elapsedBefore = "elapsed_before", runningSince = "running_since", ringingSince = "ringing_since"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = c.value(.duration, 5 * 60)
        elapsedBefore = c.value(.elapsedBefore, 0)
        runningSince = c.optional(.runningSince)
        ringingSince = c.optional(.ringingSince)
        recent = c.value(.recent, [])
    }

    var isRunning: Bool { runningSince != nil }
    var isRinging: Bool { ringingSince != nil }
    /// Started and not yet reset (running, paused part-way, or ringing).
    var isActive: Bool { isRunning || elapsedBefore > 0 || isRinging }

    func elapsed(_ now: Double) -> Double {
        min(duration, elapsedBefore + (runningSince.map { max(0, now - $0) } ?? 0))
    }
    func remaining(_ now: Double) -> Double { max(0, duration - elapsed(now)) }
    func progress(_ now: Double) -> Double { duration > 0 ? elapsed(now) / duration : 0 }

    mutating func start(_ now: Double) {
        guard runningSince == nil, duration > 0 else { return }
        if elapsedBefore >= duration { elapsedBefore = 0 }
        ringingSince = nil
        if elapsedBefore == 0 { remember(duration) }
        runningSince = now
    }

    mutating func pause(_ now: Double) {
        if let since = runningSince {
            elapsedBefore = min(duration, elapsedBefore + max(0, now - since))
            runningSince = nil
        }
    }

    mutating func reset() {
        elapsedBefore = 0
        runningSince = nil
        ringingSince = nil
    }

    /// Set a new length (only changes the running countdown's length, not its progress).
    mutating func set(_ secs: Double) {
        duration = min(Self.maxDuration, max(1, secs))
        ringingSince = nil
        if !isRunning { elapsedBefore = 0 }
    }

    /// Add (or remove) time; while running this extends the countdown in progress.
    mutating func add(_ secs: Double, _ now: Double) {
        let floor = isActive ? elapsed(now) + 1 : 1
        duration = min(Self.maxDuration, max(floor, duration + secs))
        if isRinging && secs > 0 {
            // "+1 min" after it rang: carry on for that extra minute.
            ringingSince = nil
            runningSince = now
            elapsedBefore = duration - secs
        }
    }

    private mutating func remember(_ secs: Double) {
        recent.removeAll { $0 == secs }
        recent.insert(secs, at: 0)
        recent = Array(recent.prefix(4))
    }

    /// Advance; returns true when it just reached zero.
    mutating func tick(_ now: Double) -> Bool {
        guard let since = runningSince, elapsed(now) >= duration else { return false }
        let end = since + (duration - elapsedBefore)
        runningSince = nil
        elapsedBefore = duration
        ringingSince = end
        return true
    }

    /// Short label for a length: "5 min", "1 h 30 min", "45 s".
    static func label(_ secs: Double) -> String {
        let s = Int(secs)
        if s < 60 { return "\(s) s" }
        if s % 60 != 0 { return "\(s / 60) min \(s % 60) s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
}

// MARK: - Store actions

extension WellnessStore {
    static let timerColor = Color(red: 1.0, green: 0.62, blue: 0.20)

    func timerToggle() {
        let n = WTime.now()
        if data.countdown.isRinging { data.countdown.reset(); return }
        if data.countdown.isRunning { data.countdown.pause(n) } else { data.countdown.start(n) }
    }

    func timerReset() { data.countdown.reset() }
    func timerSet(_ secs: Double) { data.countdown.set(secs) }
    func timerAdd(_ secs: Double) { data.countdown.add(secs, WTime.now()) }

    /// Start a countdown of this length right away.
    func timerStart(_ secs: Double) {
        data.countdown.reset()
        data.countdown.set(secs)
        data.countdown.start(WTime.now())
    }

    /// Called once a second by the store's tick.
    func tickCountdown(_ n: Double) {
        var c = data.countdown
        if c.tick(n) {
            data.countdown = c
            showPeek(symbol: "bell.fill", text: "Timer done", color: Self.timerColor)
            BoringViewCoordinator.shared.currentView = .timer
            postNotification(title: "Timer done", body: "\(CountdownState.label(c.duration)) is up.", sound: true)
            lastRing = n
            return
        }
        // Ring again every 4 s until stopped, at most `ringFor` seconds.
        if let since = c.ringingSince {
            if n - since >= CountdownState.ringFor {
                data.countdown.ringingSince = nil
            } else if n - lastRing >= 4 {
                lastRing = n
                ringSound()
            }
        }
    }
}

// MARK: - Tab

struct TimerTabView: View {
    @ObservedObject var store = WellnessStore.shared
    private let presets: [Double] = [60, 180, 300, 600, 900, 1800, 3600]

    var body: some View {
        let c = store.data.countdown
        let n = store.now
        let color = WellnessStore.timerColor
        let g = store.data.general

        HStack(alignment: .center, spacing: 16) {
            Button { store.timerToggle() } label: {
                ZStack {
                    PomodoroClockFace(progress: c.progress(n), color: c.isRinging ? .red : color,
                                      remaining: c.remaining(n), elapsed: c.elapsed(n),
                                      label: c.isRinging ? "DONE" : "TIMER", cycleDone: 0, cycleLength: 0)
                    if c.isRinging {
                        Image(systemName: "bell.fill").font(.system(size: 18)).foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                            .offset(y: -22)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                // Length: presets
                HStack(spacing: 4) {
                    ForEach(presets, id: \.self) { p in
                        NotchChip(label: p < 3600 ? "\(Int(p / 60))m" : "\(Int(p / 3600))h", tint: color,
                                  selected: !c.isActive && c.duration == p) {
                            if c.isRunning { store.timerStart(p) } else { store.timerSet(p) }
                        }
                    }
                }
                // Fine adjust + controls
                HStack(spacing: 4) {
                    NotchChip(label: "−1m") { store.timerAdd(-60) }
                    NotchChip(label: "+1m") { store.timerAdd(60) }
                    NotchChip(label: "+5m") { store.timerAdd(300) }
                    Spacer(minLength: 6)
                    HoverButton(icon: "arrow.counterclockwise", scale: .medium) { store.timerReset() }
                    HoverButton(icon: c.isRinging ? "stop.fill" : (c.isRunning ? "pause.fill" : "play.fill"),
                                iconColor: c.isRinging ? .red : .primary, scale: .large) { store.timerToggle() }
                }
                .frame(width: 300)
                // Clock times
                HStack(spacing: 10) {
                    Label(WTime.timeOfDay(n, g), systemImage: "clock")
                    if c.isRunning {
                        Label(WTime.timeOfDay(n + c.remaining(n), g), systemImage: "bell")
                            .foregroundStyle(color)
                    } else if c.isRinging {
                        Text("Time's up").foregroundStyle(.red)
                    } else if c.isActive {
                        Text("Paused")
                    } else {
                        Text(CountdownState.label(c.duration) + " · ready")
                    }
                    Spacer(minLength: 0)
                    // Recent lengths, one click to run again
                    ForEach(c.recent.filter { !presets.contains($0) }.prefix(2), id: \.self) { r in
                        Button { store.timerStart(r) } label: {
                            Label(CountdownState.label(r), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Run \(CountdownState.label(r)) again")
                    }
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(.gray)
                .frame(width: 300)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

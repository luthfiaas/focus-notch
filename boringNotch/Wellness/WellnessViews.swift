//
//  WellnessViews.swift
//  boringNotch
//
//  The Focus, Water, Rest and Prayer tabs of the open notch, and what the closed notch shows
//  while a timer runs or an event comes in. Sized for the 640 × 190 open notch.
//

import SwiftUI

// MARK: - Shared pieces

/// A circular progress ring like the one around the album art controls.
struct WellnessRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
        }
    }
}

/// A small capsule button for the notch (quick-add, phase chips, …).
struct NotchChip: View {
    var label: String
    var symbol: String? = nil
    var tint: Color = .white
    var selected = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? .black : tint)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(selected ? tint : Color.white.opacity(hovering ? 0.18 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.2)) { hovering = h } }
    }
}

struct StatLine: View {
    var value: String
    var label: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(color)
                .monospacedDigit().lineLimit(1)
            Text(label).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
        }
    }
}

// MARK: - Focus tab

/// The focus timer drawn as a watch face: minute ticks fill up as time passes, a hand sweeps
/// round once per phase, the countdown sits in the middle with the time already done below it.
struct PomodoroClockFace: View {
    var progress: Double
    var color: Color
    var remaining: Double
    var elapsed: Double
    var label: String
    var cycleDone: Int
    var cycleLength: Int
    var size: CGFloat = 118

    var body: some View {
        let r = size / 2
        let lit = Int((progress * 60).rounded(.down))
        ZStack {
            Circle().fill(Color.white.opacity(0.04))
            // 60 minute ticks; every fifth is longer.
            ForEach(0..<60, id: \.self) { i in
                let major = i % 5 == 0
                Capsule()
                    .fill(i < lit ? color : Color.white.opacity(major ? 0.35 : 0.18))
                    .frame(width: major ? 2 : 1, height: major ? 7 : 4)
                    .offset(y: -r + (major ? 6.5 : 5))
                    .rotationEffect(.degrees(Double(i) * 6))
            }
            // The hand.
            Capsule()
                .fill(color)
                .frame(width: 2, height: r - 12)
                .offset(y: -(r - 12) / 2)
                .rotationEffect(.degrees(progress * 360))
                .animation(.linear(duration: 1), value: progress)
            Circle().fill(color).frame(width: 6, height: 6)
            // Countdown and time done.
            VStack(spacing: 0) {
                Text(WTime.clock(remaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("+" + WTime.clock(elapsed))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .offset(y: 16)
            VStack(spacing: 3) {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
                if cycleLength > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<cycleLength, id: \.self) { i in
                            Circle().fill(i < cycleDone ? color : Color.white.opacity(0.2)).frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .offset(y: -22)
        }
        .frame(width: size, height: size)
    }
}

struct FocusTabView: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        let d = store.data
        let p = d.pomo
        let n = store.now
        let color = WellnessStore.color(p.phase)
        let zone = store.zone
        let today = store.today
        let todayStats = WellnessStats.focus(d, from: today, to: WTime.addDays(today, 1, zone), now: n)
        let week = WTime.weekStart(today, zone)
        let weekStats = WellnessStats.focus(d, from: week, to: WTime.addDays(week, 7, zone), now: n)
        let g = d.general

        HStack(alignment: .center, spacing: 16) {
            Button { store.toggleTimer() } label: {
                PomodoroClockFace(progress: p.isIdle ? 0 : p.progress(n), color: color,
                                  remaining: p.remaining(n), elapsed: p.elapsed(n), label: p.phase.label.uppercased(),
                                  cycleDone: p.completedInCycle, cycleLength: d.pomodoro.longEvery)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            // Phase, controls and clock times
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(PomoPhase.allCases, id: \.self) { ph in
                        NotchChip(label: ph == .focus ? "Focus" : (ph == .shortBreak ? "Short" : "Long"),
                                  tint: WellnessStore.color(ph), selected: p.phase == ph) {
                            store.choosePhase(ph)
                        }
                    }
                }
                HStack(spacing: 6) {
                    HoverButton(icon: "arrow.counterclockwise", scale: .medium) { store.resetTimer() }
                    HoverButton(icon: p.isRunning ? "pause.fill" : "play.fill", scale: .large) { store.toggleTimer() }
                    HoverButton(icon: "forward.end.fill", scale: .medium) { store.skipPhase() }
                }
                HStack(spacing: 10) {
                    Label(WTime.timeOfDay(n, g), systemImage: "clock")
                    if p.isRunning {
                        Label(WTime.timeOfDay(n + p.remaining(n), g), systemImage: "flag.checkered")
                            .foregroundStyle(color)
                    } else {
                        Text(p.isIdle ? "\(p.phase.minutes(d.pomodoro)) min · ready" : "Paused")
                    }
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(.gray)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            // Today / week
            VStack(alignment: .leading, spacing: 8) {
                StatLine(value: WTime.duration(todayStats.totalSecs), label: "focus today", color: WellnessStore.focusColor)
                HStack(spacing: 12) {
                    StatLine(value: "\(todayStats.completed)", label: "done")
                    StatLine(value: "\(todayStats.interrupted)", label: "stopped")
                }
                StatLine(value: WTime.duration(weekStats.totalSecs), label: "this week")
            }
            .frame(width: 96, alignment: .leading)

            WeekBars(values: (0..<7).map { i -> Double in
                let day = WTime.addDays(week, i, zone)
                return WellnessStats.focus(d, from: day, to: WTime.addDays(day, 1, zone), now: n).totalSecs
            }, todayIndex: weekdayIndex(today, week, zone), color: WellnessStore.focusColor)
            .frame(width: 92)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weekdayIndex(_ today: String, _ week: String, _ zone: TimeZone) -> Int {
        (0..<7).first { WTime.addDays(week, $0, zone) == today } ?? 0
    }
}

/// Monday-to-Sunday bars for the current week.
struct WeekBars: View {
    var values: [Double]
    var todayIndex: Int
    var color: Color

    var body: some View {
        let maxV = max(values.max() ?? 0, 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == todayIndex ? color : color.opacity(0.4))
                        .frame(width: 8, height: max(3, 70 * values[i] / maxV))
                }
            }
            .frame(height: 70, alignment: .bottom)
            HStack(spacing: 5) {
                ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { i, c in
                    Text(String(c)).font(.system(size: 8, weight: i == todayIndex ? .bold : .regular))
                        .foregroundStyle(i == todayIndex ? .white : .gray)
                        .frame(width: 8)
                }
            }
        }
    }
}

// MARK: - Water tab

struct WaterTabView: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        let total = store.waterToday
        let goal = max(1, store.waterGoalToday)
        let progress = Double(total) / Double(goal)
        let zone = store.zone
        let week = WTime.weekStart(store.today, zone)

        HStack(spacing: 18) {
            ZStack {
                WellnessRing(progress: progress, color: WellnessStore.waterColor, lineWidth: 7)
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.system(size: 14)).foregroundStyle(WellnessStore.waterColor)
                    Text("\(Int(min(progress, 9.99) * 100))%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(WellnessStore.liters(total)).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(WellnessStore.waterColor)
                    Text("of \(WellnessStore.liters(goal))").font(.system(size: 12)).foregroundStyle(.gray)
                }
                Text(total >= goal ? "Goal reached today" : "\(goal - total) ml to go")
                    .font(.system(size: 11)).foregroundStyle(.gray)
                HStack(spacing: 5) {
                    ForEach(store.data.water.quick.prefix(4), id: \.self) { ml in
                        NotchChip(label: "+\(ml)", tint: WellnessStore.waterColor) { store.addWater(ml) }
                    }
                    HoverButton(icon: "arrow.uturn.backward", iconColor: .gray, scale: .medium) { store.undoWater() }
                }
            }

            Spacer(minLength: 0)

            WeekBars(values: (0..<7).map { i in
                Double(WellnessStats.waterOn(store.data, WTime.addDays(week, i, zone)))
            }, todayIndex: (0..<7).first { WTime.addDays(week, $0, zone) == store.today } ?? 0,
                     color: WellnessStore.waterColor)
            .frame(width: 92)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rest tab

struct RestTabView: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        Group {
            if let active = store.activeReminder {
                activeCard(active)
            } else {
                overview
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activeCard(_ a: ActiveReminder) -> some View {
        let cfg = store.data.reminder(a.kind)
        let dur = Double(cfg.durationSecs)
        let left = a.countdownStart.map { max(0, dur - (store.now - $0)) }
        return HStack(spacing: 18) {
            ZStack {
                WellnessRing(progress: left.map { 1 - $0 / max(1, dur) } ?? 0, color: WellnessStore.restColor, lineWidth: 7)
                VStack(spacing: 2) {
                    Image(systemName: a.kind.symbol).font(.system(size: 22)).foregroundStyle(WellnessStore.restColor)
                    if let left {
                        Text(WTime.clock(left)).font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                Text(a.kind.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Text(a.kind.message(cfg.durationSecs)).font(.system(size: 12)).foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if a.countdownStart == nil {
                        NotchChip(label: "Start", symbol: "play.fill", tint: WellnessStore.restColor, selected: true) { store.startReminder() }
                        NotchChip(label: "Snooze \(cfg.snoozeMin)m", symbol: "zzz") { store.snoozeReminder() }
                        NotchChip(label: "Skip", symbol: "xmark") { store.skipReminder() }
                    } else {
                        NotchChip(label: "Done", symbol: "checkmark", tint: WellnessStore.restColor, selected: true) { store.doneReminder() }
                        NotchChip(label: "Skip", symbol: "xmark") { store.skipReminder() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var overview: some View {
        let d = store.data
        let zone = store.zone
        let from = WTime.dayStart(store.today, zone)
        let counts = RestReminders.counts(d, nil, from: from, to: from + 86400)
        return HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ReminderKind.allCases) { kind in
                    let cfg = d.reminder(kind)
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol).frame(width: 18).foregroundStyle(WellnessStore.restColor)
                        Text(kind.title).font(.system(size: 13)).foregroundStyle(.white)
                            .frame(width: 100, alignment: .leading)
                        Text(statusText(kind, cfg)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.gray)
                            .frame(width: 110, alignment: .leading)
                        Toggle("", isOn: Binding(get: { cfg.enabled }, set: { store.setReminderEnabled(kind, $0) }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        HoverButton(icon: "play.circle", iconColor: .gray, scale: .medium) { store.tryReminder(kind) }
                    }
                    .frame(height: 30)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                StatLine(value: "\(counts.completed)/\(counts.triggered)", label: "breaks done today", color: WellnessStore.restColor)
                StatLine(value: "\(counts.skipped)", label: "skipped")
            }
            .frame(width: 120, alignment: .leading)
        }
    }

    private func statusText(_ kind: ReminderKind, _ cfg: ReminderSettings) -> String {
        guard cfg.enabled else { return "Off" }
        if store.data.reminderRt.snoozed.contains(where: { $0.kind == kind }) { return "Snoozed" }
        guard let due = RestReminders.nextDue(store.data, kind) else { return "Every \(cfg.intervalMin) min" }
        if !RestReminders.allowedNow(store.data, kind, store.now) { return "After work hours" }
        return "in \(WTime.clock(due - store.now))"
    }
}

// MARK: - Prayer tab

struct PrayerTabView: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        Group {
            if let loc = store.data.prayer.location, let day = store.prayerDay {
                schedule(loc, day)
            } else {
                setup
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func schedule(_ loc: PrayerLocation, _ day: PrayerTimes.Day) -> some View {
        let next = store.nextPrayer
        let g = store.data.general
        return VStack(alignment: .leading, spacing: 6) {
            // Next prayer and the countdown to it
            HStack(alignment: .center) {
                if let next {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(PrayerTimes.localNames[next.index]) / \(PrayerTimes.names[next.index])")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(WellnessStore.prayerColor)
                        Label("\(WTime.timeOfDay(next.time, g)) · \(loc.name)", systemImage: "location.fill")
                            .font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(WTime.clock(next.time - store.now))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                        Text("until \(PrayerTimes.localNames[next.index])")
                            .font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
            }
            PrayerTimeline(day: day, now: store.now, next: next, general: g,
                           tracking: store.data.prayer.tracking,
                           isDone: { store.isPrayerDone($0) },
                           toggle: { store.togglePrayerDone($0) })
                .frame(height: 74)
        }
    }

    private var setup: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill").font(.system(size: 24)).foregroundStyle(WellnessStore.prayerColor)
            Text("Prayer times need to know roughly where you are.")
                .font(.system(size: 12)).foregroundStyle(.white)
            Text("Detecting asks a location service for the city of your internet connection. Nothing else is sent.")
                .font(.system(size: 10)).foregroundStyle(.gray).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                NotchChip(label: store.locating ? "Detecting…" : "Detect my city", symbol: "location.fill",
                          tint: WellnessStore.prayerColor, selected: true) { store.detectLocation() }
                Menu {
                    ForEach(PrayerTimes.builtinCities) { c in
                        Button(c.label) { store.setLocation(c, auto: false) }
                    }
                } label: {
                    Text("Choose a city").font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if let err = store.locationError {
                Text(err).font(.system(size: 10)).foregroundStyle(.red)
            }
        }
    }
}

/// The day's five prayers on a line from before Subuh to after Isya, with the moment now marked.
struct PrayerTimeline: View {
    let day: PrayerTimes.Day
    let now: Double
    let next: (index: Int, time: Double)?
    let general: WellnessGeneral
    let tracking: Bool
    let isDone: (Int) -> Bool
    let toggle: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 26
            let width = max(1, geo.size.width - inset * 2)
            let start = day.times[0] - 45 * 60
            let end = day.times[4] + 45 * 60
            let x = { (t: Double) -> CGFloat in inset + width * CGFloat(min(1, max(0, (t - start) / (end - start)))) }
            let lineY: CGFloat = 28
            let nowX = x(now)
            let nextIndex = next.flatMap { n in day.times.contains(n.time) ? n.index : nil }
            let color = WellnessStore.prayerColor

            ZStack(alignment: .topLeading) {
                // Line: done part bright, rest dim
                Capsule().fill(Color.white.opacity(0.12))
                    .frame(width: width, height: 3).position(x: inset + width / 2, y: lineY)
                Capsule().fill(color.opacity(0.55))
                    .frame(width: max(0, nowX - inset), height: 3)
                    .position(x: inset + max(0, nowX - inset) / 2, y: lineY)

                // Sunrise
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 9)).foregroundStyle(.gray)
                    .position(x: x(day.sunrise), y: lineY - 12)

                // Now
                if now >= start && now <= end {
                    Capsule().fill(.white).frame(width: 2, height: 16).position(x: nowX, y: lineY)
                    Text(WTime.timeOfDay(now, general))
                        .font(.system(size: 8, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        .position(x: nowX, y: lineY - 20)
                        .opacity(nodeNear(nowX, x) ? 0 : 1)
                }

                // Prayers
                ForEach(0..<5, id: \.self) { i in
                    let t = day.times[i]
                    let past = t <= now
                    let isNext = nextIndex == i
                    let done = isDone(i)
                    let px = x(t)
                    Group {
                        Text(PrayerTimes.localNames[i])
                            .font(.system(size: 10, weight: isNext ? .bold : .medium))
                            .foregroundStyle(isNext ? color : (past ? .white : .gray))
                            .fixedSize()
                            .position(x: px, y: lineY - 20)
                        ZStack {
                            if isNext {
                                Circle().fill(color.opacity(0.25)).frame(width: 22, height: 22)
                            }
                            Circle()
                                .fill(past || isNext ? color : Color.black)
                                .frame(width: isNext ? 13 : 11, height: isNext ? 13 : 11)
                                .overlay(Circle().stroke(past || isNext ? color : Color.gray, lineWidth: 1.5))
                            if done {
                                Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                        .onTapGesture { if tracking && (past || isNext) { toggle(i) } }
                        .help(tracking ? "Mark \(PrayerTimes.localNames[i]) as done" : "")
                        .position(x: px, y: lineY)
                        Text(WTime.timeOfDay(t, general))
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(isNext ? .white : (past ? .white.opacity(0.75) : .gray))
                            .fixedSize()
                            .position(x: px, y: lineY + 21)
                        if isNext {
                            Text("in " + WTime.clock(t - now))
                                .font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(color)
                                .fixedSize()
                                .position(x: px, y: lineY + 35)
                        } else if tracking && past {
                            Text(done ? "done" : "tap to mark")
                                .font(.system(size: 8)).foregroundStyle(done ? color : .gray)
                                .fixedSize()
                                .position(x: px, y: lineY + 35)
                        }
                    }
                }
            }
        }
    }

    /// Hide the "now" time when it would sit on a prayer's own label.
    private func nodeNear(_ nowX: CGFloat, _ x: (Double) -> CGFloat) -> Bool {
        day.times.contains { abs(x($0) - nowX) < 24 }
    }
}

// MARK: - Closed notch

/// What the closed notch shows for these features: an incoming event for a few seconds,
/// a waiting rest reminder, or the running focus timer.
enum WellnessClosedContent {
    case peek(WellnessStore.Peek)
    case reminder(ReminderKind)
    case timer(PomoPhase, remaining: Double, progress: Double, running: Bool)
    case countdown(remaining: Double, progress: Double, running: Bool, ringing: Bool)

    @MainActor static func current(_ store: WellnessStore) -> WellnessClosedContent? {
        if let p = store.peek { return .peek(p) }
        if let a = store.activeReminder { return .reminder(a.kind) }
        let cd = store.data.countdown
        if cd.isActive {
            return .countdown(remaining: cd.remaining(store.now), progress: cd.progress(store.now),
                              running: cd.isRunning, ringing: cd.isRinging)
        }
        let pomo = store.data.pomo
        if !pomo.isIdle {
            return .timer(pomo.phase, remaining: pomo.remaining(store.now), progress: pomo.progress(store.now), running: pomo.isRunning)
        }
        return nil
    }

    /// Width of each side next to the camera housing (both sides match so the housing stays centred).
    var sideWidth: CGFloat {
        switch self {
        case .peek: return 150
        case .reminder: return 96
        case .timer: return 48
        case .countdown(_, _, _, let ringing): return ringing ? 70 : 48
        }
    }
}

struct WellnessClosedActivity: View {
    @ObservedObject var store = WellnessStore.shared
    var content: WellnessClosedContent
    /// Height of the closed notch.
    var height: CGFloat
    /// Width of the camera housing (kept black).
    var notchWidth: CGFloat

    var body: some View {
        let side = max(0, height - 12)
        HStack {
            leading
                .frame(width: side, height: side)
                .frame(width: content.sideWidth, alignment: .leading)
            Rectangle().fill(.black).frame(width: notchWidth)
            trailing
                .frame(width: content.sideWidth, alignment: .trailing)
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder private var leading: some View {
        switch content {
        case .peek(let p):
            Image(systemName: p.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.color)
        case .reminder(let kind):
            Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WellnessStore.restColor)
                .symbolEffect(.pulse, options: .repeating)
        case .timer(let phase, _, let progress, _):
            WellnessRing(progress: progress, color: WellnessStore.color(phase), lineWidth: 2.5)
                .padding(2)
        case .countdown(_, let progress, _, let ringing):
            if ringing {
                Image(systemName: "bell.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                ZStack {
                    WellnessRing(progress: progress, color: WellnessStore.timerColor, lineWidth: 2.5)
                    Image(systemName: "timer").font(.system(size: 7, weight: .bold)).foregroundStyle(WellnessStore.timerColor)
                }
                .padding(2)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch content {
        case .peek(let p):
            Text(p.text).font(.system(size: 12, weight: .medium)).foregroundStyle(p.color).lineLimit(1)
        case .reminder(let kind):
            Text(kind.title).font(.system(size: 12, weight: .medium)).foregroundStyle(WellnessStore.restColor).lineLimit(1)
        case .timer(let phase, let remaining, _, let running):
            Text(WTime.clock(remaining))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(running ? WellnessStore.color(phase) : .gray)
        case .countdown(let remaining, _, let running, let ringing):
            if ringing {
                Text("Time's up").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red).lineLimit(1)
            } else {
                Text(WTime.clock(remaining))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(running ? WellnessStore.timerColor : .gray)
            }
        }
    }
}

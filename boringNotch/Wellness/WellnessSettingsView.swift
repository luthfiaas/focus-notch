//
//  WellnessSettingsView.swift
//  boringNotch
//
//  Settings panes for the Focus, Water, Rest and Prayer features.
//

import AppKit
import SwiftUI

private func minutesBinding(_ b: Binding<Int>) -> Binding<Date> {
    // Minutes since midnight ↔ a Date for DatePicker (in UTC so no zone shifts apply).
    Binding(
        get: { Date(timeIntervalSince1970: Double(b.wrappedValue * 60)) },
        set: { d in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let c = cal.dateComponents([.hour, .minute], from: d)
            b.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    )
}

private struct TimeOfDayPicker: View {
    var title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: minutesBinding($minutes), displayedComponents: .hourAndMinute)
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    }
}

// MARK: - Focus

struct FocusSettingsPane: View {
    @ObservedObject var store = WellnessStore.shared
    private let sounds = ["Glass", "Ping", "Pop", "Purr", "Hero", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Morse", "Sosumi", "Tink", "Basso"]

    var body: some View {
        Form {
            Section {
                Stepper("Focus: \(store.data.pomodoro.focusMin) min", value: $store.data.pomodoro.focusMin, in: 1...180)
                Stepper("Short break: \(store.data.pomodoro.shortMin) min", value: $store.data.pomodoro.shortMin, in: 1...60)
                Stepper("Long break: \(store.data.pomodoro.longMin) min", value: $store.data.pomodoro.longMin, in: 1...120)
                Stepper("Long break after \(store.data.pomodoro.longEvery) focus sessions", value: $store.data.pomodoro.longEvery, in: 1...12)
            } header: {
                Text("Focus timer")
            } footer: {
                Text("New lengths apply to the next phase; a running phase keeps its length.")
            }
            .onChange(of: store.data.pomodoro.focusMin) { store.pomodoroSettingsChanged() }
            .onChange(of: store.data.pomodoro.shortMin) { store.pomodoroSettingsChanged() }
            .onChange(of: store.data.pomodoro.longMin) { store.pomodoroSettingsChanged() }

            Section {
                Toggle("Start breaks automatically", isOn: $store.data.pomodoro.autoStartBreaks)
                Toggle("Start focus automatically after a break", isOn: $store.data.pomodoro.autoStartFocus)
                Toggle("Notify when a phase ends", isOn: $store.data.pomodoro.notify)
                Toggle("Play a sound when a phase ends", isOn: $store.data.pomodoro.sound)
            } header: {
                Text("Behaviour")
            }

            Section {
                Toggle("Desktop notifications", isOn: $store.data.general.desktopNotifications)
                Picker("Sound", selection: $store.data.general.soundName) {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: store.data.general.soundName) { _, name in NSSound(named: NSSound.Name(name))?.play() }
                Toggle("24-hour clock", isOn: $store.data.general.time24h)
                Picker("Time zone", selection: $store.data.general.timezone) {
                    Text("This Mac (\(TimeZone.current.identifier))").tag("System")
                    ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0).tag($0) }
                }
                TimeOfDayPicker(title: "Work day starts", minutes: $store.data.general.workStart)
                TimeOfDayPicker(title: "Work day ends", minutes: $store.data.general.workEnd)
            } header: {
                Text("General")
            } footer: {
                Text("Days and weeks in the statistics use this time zone. Rest reminders follow the work day unless set otherwise. Data: \(WellnessData.fileURL.path)")
            }
        }
        .navigationTitle("Focus")
    }
}

// MARK: - Water

struct WaterSettingsPane: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        Form {
            Section {
                Stepper("Daily goal: \(store.data.water.goalMl) ml", value: Binding(
                    get: { store.data.water.goalMl },
                    set: { store.setWaterGoal($0) }
                ), in: 250...10000, step: 250)
            } header: {
                Text("Goal")
            } footer: {
                Text("Changing the goal applies from today; earlier days keep the goal they had.")
            }
            Section {
                ForEach(store.data.water.quick.indices, id: \.self) { i in
                    Stepper("Button \(i + 1): \(store.data.water.quick[i]) ml", value: $store.data.water.quick[i], in: 1...5000, step: 50)
                }
            } header: {
                Text("Quick-add buttons")
            }
        }
        .navigationTitle("Water")
    }
}

// MARK: - Rest

struct RestSettingsPane: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        Form {
            ForEach(ReminderKind.allCases) { kind in
                section(kind)
            }
        }
        .navigationTitle("Rest")
    }

    private func binding(_ kind: ReminderKind) -> Binding<ReminderSettings> {
        Binding(get: { store.data.reminder(kind) }, set: { store.data.setReminder(kind, $0) })
    }

    private func section(_ kind: ReminderKind) -> some View {
        let b = binding(kind)
        return Section {
            Toggle("Enabled", isOn: b.enabled)
            Stepper("Every \(b.wrappedValue.intervalMin) min", value: b.intervalMin, in: 1...240)
            Stepper("Lasts \(b.wrappedValue.durationSecs) s", value: b.durationSecs, in: 5...900, step: 5)
            Stepper("Snooze \(b.wrappedValue.snoozeMin) min", value: b.snoozeMin, in: 1...60)
            Toggle("Only during working hours", isOn: b.useWorkHours)
            if b.wrappedValue.useWorkHours {
                Toggle("Own working hours", isOn: b.customHours)
                if b.wrappedValue.customHours {
                    TimeOfDayPicker(title: "From", minutes: b.start)
                    TimeOfDayPicker(title: "Until", minutes: b.end)
                }
            }
            Toggle("Desktop notification", isOn: b.desktopNotify)
            Toggle("Sound", isOn: b.sound)
            Button("Try it now") { store.tryReminder(kind) }
        } header: {
            Label(kind.title, systemImage: kind.symbol)
        }
    }
}

// MARK: - Prayer

struct PrayerSettingsPane: View {
    @ObservedObject var store = WellnessStore.shared
    @State private var query = ""
    @State private var results: [PrayerLocation] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show prayer times and notify", isOn: $store.data.prayer.enabled)
                LabeledContent("Location", value: store.data.prayer.location?.label ?? "Not set")
                HStack {
                    Button(store.locating ? "Detecting…" : "Detect my city") { store.detectLocation() }
                        .disabled(store.locating)
                    Spacer()
                    Menu("Choose a city") {
                        ForEach(PrayerTimes.builtinCities) { c in
                            Button(c.label) { store.setLocation(c, auto: false) }
                        }
                    }
                    .fixedSize()
                }
                HStack {
                    TextField("Search any city", text: $query).onSubmit(search)
                    Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                ForEach(results) { r in
                    Button(r.label) {
                        store.setLocation(r, auto: false)
                        results = []
                        query = ""
                    }
                }
                if let e = searchError ?? store.locationError {
                    Text(e).foregroundStyle(.red)
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Detecting asks a location service for the city of your internet connection; searching asks Open-Meteo. Prayer times themselves are calculated on this Mac.")
            }

            Section {
                Picker("Calculation method", selection: $store.data.prayer.method) {
                    ForEach(PrayerMethod.allCases) { Text($0.label).tag($0) }
                }
                Picker("Asr", selection: $store.data.prayer.asr) {
                    ForEach(AsrMethod.allCases) { Text($0.label).tag($0) }
                }
                ForEach(0..<5, id: \.self) { i in
                    Stepper("\(PrayerTimes.localNames[i]) adjustment: \(store.data.prayer.adjust[i]) min",
                            value: $store.data.prayer.adjust[i], in: -30...30)
                }
            } header: {
                Text("Calculation")
            } footer: {
                if store.data.prayer.method == .auto, let loc = store.data.prayer.location {
                    Text("Automatic uses \(PrayerTimes.resolve(.auto, loc).label) for \(loc.country).")
                }
            }

            Section {
                ForEach(0..<5, id: \.self) { i in
                    Toggle("\(PrayerTimes.localNames[i]) / \(PrayerTimes.names[i])", isOn: $store.data.prayer.notify[i])
                }
                Picker("Remind before", selection: $store.data.prayer.beforeMin) {
                    Text("At the time only").tag(0)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
                Toggle("Sound", isOn: $store.data.prayer.sound)
                Toggle("Track prayers done", isOn: $store.data.prayer.tracking)
            } header: {
                Text("Notifications")
            }
        }
        .navigationTitle("Prayer")
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        searchError = nil
        Task { @MainActor in
            do {
                results = try await PrayerTimes.searchOnline(q)
                if results.isEmpty { searchError = "No place called “\(q)” found." }
            } catch {
                searchError = error.localizedDescription
            }
            searching = false
        }
    }
}

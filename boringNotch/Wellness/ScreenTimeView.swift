//
//  ScreenTimeView.swift
//  boringNotch
//
//  The Screen Time tab: today's time on screen, the apps it went to, and the hours it fell in.
//

import SwiftUI

struct ScreenTimeTabView: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        let d = store.data
        let today = store.screenToday
        let zone = store.zone
        let yesterday = store.screenDay(WTime.addDays(store.today, -1, zone))
        let limit = Double(d.screenTimeSettings.dailyLimitMin * 60)
        let color = WellnessStore.screenColor

        if !d.screenTimeSettings.enabled {
            VStack(spacing: 8) {
                Image(systemName: "hourglass").font(.system(size: 22)).foregroundStyle(color)
                Text("Screen time is off").font(.system(size: 12)).foregroundStyle(.white)
                NotchChip(label: "Turn on", tint: color, selected: true) { store.data.screenTimeSettings.enabled = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .center, spacing: 16) {
                // Total today
                ZStack {
                    WellnessRing(progress: limit > 0 ? today.total / limit : min(1, today.total / (8 * 3600)),
                                 color: limit > 0 && today.total >= limit ? .red : color, lineWidth: 7)
                    VStack(spacing: 1) {
                        Image(systemName: "hourglass").font(.system(size: 12)).foregroundStyle(color)
                        Text(WTime.duration(today.total))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(limit > 0 ? "of \(WTime.duration(limit))" : "today")
                            .font(.system(size: 10)).foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(width: 112, height: 112)

                // Top apps
                VStack(alignment: .leading, spacing: 5) {
                    let top = today.apps.sorted { $0.value > $1.value }.prefix(4)
                    let most = max(top.first?.value ?? 1, 1)
                    if top.isEmpty {
                        Text("No screen time yet today").font(.system(size: 11)).foregroundStyle(.gray)
                    }
                    ForEach(Array(top), id: \.key) { id, secs in
                        HStack(spacing: 7) {
                            if let icon = ScreenTimeTracker.icon(for: id) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app").frame(width: 16, height: 16).foregroundStyle(.gray)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(d.appNames[id] ?? id).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(WTime.duration(secs)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.gray)
                                }
                                Capsule().fill(color.opacity(0.8))
                                    .frame(width: max(3, 150 * secs / most), height: 3)
                            }
                        }
                        .frame(width: 190)
                    }
                }

                Spacer(minLength: 0)

                // By hour, plus a few numbers
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        StatLine(value: "\(today.pickups)", label: "pickups")
                        StatLine(value: change(today.total, yesterday.total), label: "vs yesterday")
                    }
                    HourBars(hours: today.hours, currentHour: WTime.minuteOfDay(store.now, zone) / 60, color: color)
                        .frame(height: 52)
                }
                .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func change(_ today: Double, _ yesterday: Double) -> String {
        guard yesterday >= 60 else { return "–" }
        let diff = today - yesterday
        return (diff >= 0 ? "+" : "−") + WTime.duration(abs(diff))
    }
}

/// 24 thin bars, one per hour of the day.
struct HourBars: View {
    var hours: [Double]
    var currentHour: Int
    var color: Color

    var body: some View {
        let maxV = max(hours.max() ?? 0, 60)
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(h == currentHour ? color : color.opacity(0.45))
                        .frame(width: 4, height: max(1, 40 * hours[h] / maxV))
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach(["0", "6", "12", "18"], id: \.self) { t in
                    Text(t).font(.system(size: 8)).foregroundStyle(.gray).frame(width: 36, alignment: .leading)
                }
            }
        }
    }
}

struct ScreenTimeSettingsPane: View {
    @ObservedObject var store = WellnessStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Track screen time", isOn: $store.data.screenTimeSettings.enabled)
                Stepper("Away after \(store.data.screenTimeSettings.idleSecs / 60) min without input",
                        value: $store.data.screenTimeSettings.idleSecs, in: 60...900, step: 60)
                Stepper(store.data.screenTimeSettings.dailyLimitMin == 0
                        ? "Daily limit: none"
                        : "Daily limit: \(WTime.duration(Double(store.data.screenTimeSettings.dailyLimitMin * 60)))",
                        value: $store.data.screenTimeSettings.dailyLimitMin, in: 0...960, step: 30)
            } header: {
                Text("Screen time")
            } footer: {
                Text("Counts time this Mac is unlocked and in use, by the app in front. Time without keyboard or mouse input past the away limit, and time locked or asleep, is not counted. macOS doesn't let other apps read its own Screen Time, so these numbers are measured here and can differ from it. Kept for 60 days, on this Mac only.")
            }
        }
        .navigationTitle("Screen Time")
    }
}

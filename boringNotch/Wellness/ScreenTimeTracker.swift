//
//  ScreenTimeTracker.swift
//  boringNotch
//
//  Measures screen time on this Mac: time the screen is unlocked, awake and in use
//  (keyboard or mouse input within the idle limit), split by the app in front and by hour.
//  macOS does not let other apps read its own Screen Time data, so this keeps its own count.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ScreenTimeTracker {
    static let shared = ScreenTimeTracker()

    private var locked = false
    private var asleep = false
    private var lastTick: Double?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true }
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.locked = false
                self?.countPickup()
            }
        })
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true }
        })
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.asleep = false
                if self?.locked == false { self?.countPickup() }
            }
        })
        observers.append(wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true }
        })
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false }
        })
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func idleSeconds() -> Double {
        guard let any = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private func countPickup() {
        let store = WellnessStore.shared
        guard store.data.screenTimeSettings.enabled else { return }
        store.data.screenTime[store.today, default: ScreenDay()].pickups += 1
    }

    /// Called once a second by the store. Adds the time since the last call when the screen is in use.
    func tick(_ data: inout WellnessData, now: Double) -> Bool {
        defer { lastTick = now }
        guard data.screenTimeSettings.enabled, let last = lastTick else { return false }
        // Gaps (sleep, a busy main thread) never count for more than 2 s.
        let dt = min(max(0, now - last), 2)
        guard dt > 0, !locked, !asleep, Self.idleSeconds() < Double(max(10, data.screenTimeSettings.idleSecs)) else {
            return false
        }
        let zone = WTime.zone(data.general)
        let day = WTime.day(now, zone)
        let hour = min(23, max(0, WTime.minuteOfDay(now, zone) / 60))
        var record = data.screenTime[day] ?? ScreenDay()
        record.total += dt
        record.hours[hour] += dt
        if let app = NSWorkspace.shared.frontmostApplication {
            let id = app.bundleIdentifier ?? app.localizedName ?? "unknown"
            record.apps[id, default: 0] += dt
            if data.appNames[id] == nil { data.appNames[id] = app.localizedName ?? id }
        }
        data.screenTime[day] = record
        // Keep the last 60 days.
        if data.screenTime.count > 60 {
            let cutoff = WTime.addDays(day, -60, zone)
            data.screenTime = data.screenTime.filter { $0.key >= cutoff }
        }
        return true
    }

    /// The app's icon, looked up from its bundle identifier.
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

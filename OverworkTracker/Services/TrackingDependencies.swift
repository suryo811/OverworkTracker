import AppKit
import CoreGraphics
import Foundation

// MARK: - Protocols

protocol Clock: AnyObject {
    func now() -> Date
}

/// Snapshot of the currently frontmost application as reported by the OS.
struct FrontmostApp: Equatable {
    let bundleID: String?
    let appName: String
}

/// Abstraction over NSWorkspace + CGEventSource so the tracker can be
/// exercised deterministically from tests.
protocol ActivitySource: AnyObject {
    var frontmost: FrontmostApp? { get }
    var secondsSinceLastInput: TimeInterval { get }

    /// Invoked on the main thread whenever the frontmost application changes.
    func observeAppActivation(_ handler: @escaping (FrontmostApp) -> Void)

    /// Invoked on the main thread when the system is about to sleep / wakes up.
    func observeSleepWake(willSleep: @escaping () -> Void, didWake: @escaping () -> Void)

    func stopObserving()
}

/// Write-only surface of the database the tracker needs. Keeping this narrow
/// makes the tracker trivially mockable.
protocol SessionStore: AnyObject {
    func insertSession(_ session: TrackingSession) throws -> Int64
    func updateSessionDuration(id: Int64, duration: TimeInterval, endTime: Date) throws
}

/// The subset of `AppSettings` the tracker consults. Having this as a
/// protocol lets tests inject values without touching UserDefaults.
protocol TrackerSettingsProviding: AnyObject {
    var heartbeatInterval: TimeInterval { get }
    var idleThreshold: TimeInterval { get }
    var excludedBundleIDs: Set<String> { get }
}

extension AppSettings: TrackerSettingsProviding {}

// MARK: - Real implementations

final class SystemClock: Clock {
    func now() -> Date { Date() }
}

final class NSWorkspaceActivitySource: ActivitySource {
    private var activationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    var frontmost: FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApp(
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "Unknown"
        )
    }

    var secondsSinceLastInput: TimeInterval {
        // `combinedSessionState` combines HID + system events. `~0` matches
        // every event type so any mouse/keyboard/trackpad activity resets
        // the idle timer.
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    func observeAppActivation(_ handler: @escaping (FrontmostApp) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            handler(FrontmostApp(
                bundleID: app.bundleIdentifier,
                appName: app.localizedName ?? "Unknown"
            ))
        }
    }

    func observeSleepWake(willSleep: @escaping () -> Void, didWake: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in willSleep() }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in didWake() }
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        [activationObserver, sleepObserver, wakeObserver]
            .compactMap { $0 }
            .forEach { center.removeObserver($0) }
        activationObserver = nil
        sleepObserver = nil
        wakeObserver = nil
    }

    deinit { stopObserving() }
}

// MARK: - DatabaseManager conformance

extension DatabaseManager: SessionStore {}

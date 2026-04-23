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
    /// Observers from `NSWorkspace.shared.notificationCenter`.
    private var workspaceSleepObservers: [NSObjectProtocol] = []
    /// Observers from the distributed notification center (screen lock/unlock).
    private var distributedSleepObservers: [NSObjectProtocol] = []

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
        // All "user is going away" events funnel into `willSleep` and all
        // "user is back" events funnel into `didWake`, so the tracker can use
        // a single set of handlers regardless of whether the Mac fully slept,
        // only the display slept, or the screen was locked. This matters
        // because `willSleepNotification` does NOT fire on lock-without-sleep
        // (Ctrl+Cmd+Q, screen-saver lock, display sleep with power): without
        // the additional hooks below, the current session would be left open
        // for the entire duration of the lock and committed on unlock.
        let workspace = NSWorkspace.shared.notificationCenter
        let goingAwayNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let comingBackNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in goingAwayNames {
            let o = workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                willSleep()
            }
            workspaceSleepObservers.append(o)
        }
        for name in comingBackNames {
            let o = workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                didWake()
            }
            workspaceSleepObservers.append(o)
        }

        // Screen-lock / screen-unlock events are delivered via the
        // distributed notification center, not NSWorkspace.
        let distributed = DistributedNotificationCenter.default()
        let lockObserver = distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in willSleep() }
        let unlockObserver = distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in didWake() }
        distributedSleepObservers.append(contentsOf: [lockObserver, unlockObserver])
    }

    func stopObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        if let activationObserver {
            workspace.removeObserver(activationObserver)
        }
        activationObserver = nil

        for o in workspaceSleepObservers {
            workspace.removeObserver(o)
        }
        workspaceSleepObservers.removeAll()

        let distributed = DistributedNotificationCenter.default()
        for o in distributedSleepObservers {
            distributed.removeObserver(o)
        }
        distributedSleepObservers.removeAll()
    }

    deinit { stopObserving() }
}

// MARK: - DatabaseManager conformance

extension DatabaseManager: SessionStore {}

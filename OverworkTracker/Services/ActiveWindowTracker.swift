import AppKit
import Foundation

/// Event-driven active-window tracker.
///
/// The previous implementation polled every `pollingInterval` seconds and
/// credited a fixed chunk of `pollingInterval` to whichever app happened to be
/// frontmost at the tick. That lost every app visit shorter than the polling
/// interval (a 15s visit recorded as 0s) and it also over-credited idle time
/// because app switches were only noticed at the next tick.
///
/// This implementation:
///   * subscribes to `NSWorkspace.didActivateApplicationNotification` so app
///     switches are processed immediately and use real wall-clock elapsed
///     time;
///   * subscribes to `willSleepNotification` / `didWakeNotification` so time
///     the Mac is asleep is never credited;
///   * still runs a short heartbeat (default 5s) for two purposes only —
///     detecting idle transitions and pushing the live duration to the DB so
///     the UI feels real-time.
@Observable
final class ActiveWindowTracker {
    private let clock: Clock
    private let activity: ActivitySource
    private let store: SessionStore
    private let settings: TrackerSettingsProviding

    private var heartbeatTimer: Timer?
    private var current: LiveSession?
    private var wasIdle = false

    private(set) var isTracking = false

    /// Hard cap on a single session's credited duration. Guards against clock
    /// skew, missed sleep notifications, or other pathological states from
    /// producing 30-hour sessions.
    static let maxSessionDuration: TimeInterval = 24 * 60 * 60

    /// System-level bundle IDs that are never user-foreground work even though
    /// macOS briefly reports them as the frontmost application. `loginwindow`
    /// in particular is the lock/login screen process: if the Mac is locked
    /// (clamshell, display sleep, Ctrl+Cmd+Q, screen saver lock) it becomes
    /// frontmost for the duration of the lock, which without this filter
    /// silently accumulates hours of "work" against it.
    static let systemExcludedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
    ]

    private struct LiveSession {
        let id: Int64
        let bundleID: String?
        let appName: String
        let startedAt: Date
    }

    init(
        clock: Clock = SystemClock(),
        activity: ActivitySource = NSWorkspaceActivitySource(),
        store: SessionStore,
        settings: TrackerSettingsProviding = AppSettings.shared
    ) {
        self.clock = clock
        self.activity = activity
        self.store = store
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !isTracking else { return }
        isTracking = true
        wasIdle = false

        activity.observeAppActivation { [weak self] app in
            self?.handleAppActivation(app)
        }
        activity.observeSleepWake(
            willSleep: { [weak self] in self?.handleWillSleep() },
            didWake: { [weak self] in self?.handleDidWake() }
        )

        // Seed a session for whatever is currently frontmost, unless the user
        // is already idle.
        let now = clock.now()
        if activity.secondsSinceLastInput >= settings.idleThreshold {
            wasIdle = true
        } else if let front = activity.frontmost {
            startNewSession(for: front, at: now)
        }

        scheduleHeartbeat()
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        activity.stopObserving()
        commitCurrentSession(upTo: clock.now())
        isTracking = false
        wasIdle = false
    }

    private func scheduleHeartbeat() {
        heartbeatTimer?.invalidate()
        let t = Timer(timeInterval: settings.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    // MARK: - Event handlers (also driven directly by tests)

    /// Processes a frontmost-app change. Commits the prior session with the
    /// exact elapsed time up to `now` and starts a new one.
    func handleAppActivation(_ app: FrontmostApp) {
        guard isTracking else { return }
        let now = clock.now()
        commitCurrentSession(upTo: now)
        wasIdle = false
        startNewSession(for: app, at: now)
    }

    func handleWillSleep() {
        guard isTracking else { return }
        commitCurrentSession(upTo: clock.now())
        wasIdle = true
    }

    func handleDidWake() {
        guard isTracking else { return }
        // On wake the user may or may not be actively using the machine; let
        // the next heartbeat decide based on `secondsSinceLastInput`. Starting
        // a session here would over-credit anyone who wakes the Mac and walks
        // away.
        wasIdle = activity.secondsSinceLastInput >= settings.idleThreshold
        if !wasIdle, let front = activity.frontmost {
            startNewSession(for: front, at: clock.now())
        }
    }

    /// Called on every heartbeat (production timer) or directly from tests.
    /// Responsible for (1) idle detection and (2) pushing the live duration
    /// to storage so the UI updates while an app is still in the foreground.
    func heartbeat() {
        guard isTracking else { return }

        let now = clock.now()
        let secondsSinceInput = activity.secondsSinceLastInput
        let isIdle = secondsSinceInput >= settings.idleThreshold

        if isIdle {
            if !wasIdle {
                // User stopped interacting `secondsSinceInput` ago — credit up
                // to that moment, not up to `now`. This fixes the old bug
                // where idle time up to `idleThreshold` was silently added.
                let stoppedAt = now.addingTimeInterval(-secondsSinceInput)
                commitCurrentSession(upTo: stoppedAt)
                wasIdle = true
            }
            return
        }

        // Coming back from idle.
        if wasIdle {
            wasIdle = false
            if let front = activity.frontmost {
                startNewSession(for: front, at: now)
            }
            return
        }

        // Steady-state active: refresh the live duration. If somehow we have
        // no session but are active (e.g. start() raced with startup), open
        // one now.
        if current != nil {
            refreshCurrentDuration(at: now)
        } else if let front = activity.frontmost {
            startNewSession(for: front, at: now)
        }
    }

    // MARK: - Session management

    private func startNewSession(for app: FrontmostApp, at startedAt: Date) {
        // Excluded apps are tracked as "off" — no session created. Any
        // previous session was already committed by the caller. The
        // system-excluded set is consulted in addition to the user's list so
        // `loginwindow` / screensaver time can never be credited regardless
        // of user settings.
        if let bid = app.bundleID,
           settings.excludedBundleIDs.contains(bid)
            || Self.systemExcludedBundleIDs.contains(bid)
        {
            return
        }

        let session = TrackingSession(
            appName: app.appName,
            bundleID: app.bundleID,
            windowTitle: nil,
            startTime: startedAt,
            duration: 0,
            endTime: startedAt
        )

        do {
            let id = try store.insertSession(session)
            current = LiveSession(
                id: id,
                bundleID: app.bundleID,
                appName: app.appName,
                startedAt: startedAt
            )
        } catch {
            print("Failed to insert session: \(error)")
            current = nil
        }
    }

    private func commitCurrentSession(upTo endTime: Date) {
        guard let session = current else { return }
        let raw = endTime.timeIntervalSince(session.startedAt)
        let duration = max(0, min(raw, Self.maxSessionDuration))
        let clampedEnd = session.startedAt.addingTimeInterval(duration)
        do {
            try store.updateSessionDuration(
                id: session.id,
                duration: duration,
                endTime: clampedEnd
            )
        } catch {
            print("Failed to commit session: \(error)")
        }
        current = nil
    }

    private func refreshCurrentDuration(at now: Date) {
        guard let session = current else { return }
        let raw = now.timeIntervalSince(session.startedAt)
        let duration = max(0, min(raw, Self.maxSessionDuration))
        do {
            try store.updateSessionDuration(
                id: session.id,
                duration: duration,
                endTime: now
            )
        } catch {
            print("Failed to refresh session: \(error)")
        }
    }
}

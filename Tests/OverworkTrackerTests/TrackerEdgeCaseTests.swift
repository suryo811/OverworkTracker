import XCTest
@testable import OverworkTracker

/// Additional edge-case tests for `ActiveWindowTracker` that complement
/// `TrackerBehaviorTests`. Focuses on boundary conditions (threshold equality,
/// empty state, idempotency) and scenarios where multiple state transitions
/// interact (idle heartbeats in a row, excluded-then-included).
final class TrackerEdgeCaseTests: XCTestCase {
    private var clock: FakeClock!
    private var activity: FakeActivitySource!
    private var store: InMemorySessionStore!
    private var settings: FakeSettings!
    private var tracker: ActiveWindowTracker!

    private let safari = FrontmostApp(bundleID: "com.apple.Safari", appName: "Safari")
    private let xcode = FrontmostApp(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
    private let slack = FrontmostApp(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack")

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        activity = FakeActivitySource()
        store = InMemorySessionStore()
        settings = FakeSettings()
        tracker = ActiveWindowTracker(
            clock: clock,
            activity: activity,
            store: store,
            settings: settings
        )
    }

    override func tearDown() {
        tracker = nil
        settings = nil
        store = nil
        activity = nil
        clock = nil
        super.tearDown()
    }

    private func startWithFrontmost(_ app: FrontmostApp, secondsSinceInput: TimeInterval = 0) {
        activity.frontmost = app
        activity.secondsSinceLastInput = secondsSinceInput
        tracker.start()
    }

    // MARK: - Idle heartbeat idempotency

    func testRepeatedHeartbeatsWhileIdleDoNotCreateExtraRows() {
        startWithFrontmost(safari)

        // Work for 10s, then go idle.
        clock.advance(by: 10)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        clock.advance(by: 400)
        activity.secondsSinceLastInput = 400
        tracker.heartbeat()

        let snapshotCount = store.all.count
        let snapshotDuration = store.all.last?.duration ?? -1

        // Fire several more heartbeats while still idle — should change nothing.
        for i in 1...5 {
            clock.advance(by: 60)
            activity.secondsSinceLastInput = 400 + TimeInterval(i) * 60
            tracker.heartbeat()
        }

        XCTAssertEqual(store.all.count, snapshotCount,
                       "Heartbeats during a continuous idle stretch must not open new sessions")
        XCTAssertEqual(store.all.last?.duration ?? -2, snapshotDuration, accuracy: 0.001,
                       "Duration of the committed session must not keep growing once idle")
    }

    // MARK: - Excluded bundles

    func testActivationToExcludedAppAfterActiveSession() {
        settings.excludedBundleIDs = [slack.bundleID!]
        startWithFrontmost(safari)

        clock.advance(by: 10)
        activity.simulateActivation(bundleID: slack.bundleID, appName: slack.appName)

        // No new row for Slack, and Safari is already committed with 10s.
        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(store.all[0].duration, 10, accuracy: 0.001)
    }

    func testExcludedThenNonExcludedApp() {
        settings.excludedBundleIDs = [slack.bundleID!]
        startWithFrontmost(slack) // seed session for excluded app — should not insert

        XCTAssertEqual(store.all.count, 0, "Seeding with an excluded app must not insert a row")

        // 30s in excluded app, then switch to Xcode.
        clock.advance(by: 30)
        activity.simulateActivation(bundleID: xcode.bundleID, appName: xcode.appName)

        clock.advance(by: 20)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1, "Only the non-excluded app should be recorded")
        XCTAssertEqual(store.all[0].bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(store.all[0].duration, 20, accuracy: 0.001,
                       "Xcode should start counting from the activation, not earlier")
    }

    // MARK: - Wake boundaries

    func testWakeWithNoFrontmostDoesNotStartSession() {
        startWithFrontmost(safari)
        clock.advance(by: 5)
        activity.simulateSleep()

        clock.advance(by: 60)
        activity.frontmost = nil
        activity.secondsSinceLastInput = 0
        activity.simulateWake()

        clock.advance(by: 30)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1, "Wake without a frontmost app must not open a new session")
        XCTAssertEqual(store.all[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(store.all[0].duration, 5, accuracy: 0.5)
    }

    func testWakeAtIdleThresholdBoundary() {
        startWithFrontmost(safari)
        clock.advance(by: 10)
        activity.simulateSleep()

        clock.advance(by: 60)
        activity.frontmost = xcode
        // Exactly at the idle threshold — tracker uses `>=` so this is idle.
        activity.secondsSinceLastInput = settings.idleThreshold
        activity.simulateWake()

        tracker.stop()

        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.dt.Xcode"), 0,
                       "Waking at exactly the idle threshold must not start a new session")
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 10, accuracy: 0.5)
    }

    // MARK: - Lifecycle edge cases

    func testIdempotentStartDoesNotDoubleInsert() {
        activity.frontmost = safari
        activity.secondsSinceLastInput = 0
        tracker.start()
        tracker.start() // second start is a no-op

        clock.advance(by: 15)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1,
                       "Calling start() twice must not open a second session for the same frontmost app")
        XCTAssertEqual(store.all[0].duration, 15, accuracy: 0.001)
    }

    func testStopWithoutAnySessionIsNoop() {
        // Tracker was never started.
        tracker.stop()
        XCTAssertEqual(store.all.count, 0)
        XCTAssertFalse(tracker.isTracking)
    }

    func testWillSleepWithNoCurrentSessionIsNoop() {
        // Start while already idle — no seed session is opened.
        activity.frontmost = safari
        activity.secondsSinceLastInput = 999
        tracker.start()

        XCTAssertEqual(store.all.count, 0)

        // Firing sleep without a current session must not crash or insert.
        activity.simulateSleep()

        XCTAssertEqual(store.all.count, 0)
    }

    // MARK: - Reactivation & cap boundary

    func testReactivationOfSameBundleStartsNewSession() {
        startWithFrontmost(safari)
        clock.advance(by: 10)

        // User re-activates Safari (e.g., clicks its icon while already frontmost).
        activity.simulateActivation(bundleID: safari.bundleID, appName: safari.appName)

        clock.advance(by: 5)
        tracker.stop()

        XCTAssertEqual(store.all.count, 2,
                       "Every activation event opens a new session, even for the same bundle")
        XCTAssertEqual(store.all[0].duration, 10, accuracy: 0.001)
        XCTAssertEqual(store.all[1].duration, 5, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 15, accuracy: 0.001)
    }

    func testSessionCapEdgeJustAbove24Hours() {
        startWithFrontmost(safari)
        clock.advance(by: ActiveWindowTracker.maxSessionDuration + 1)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].duration,
                       ActiveWindowTracker.maxSessionDuration,
                       accuracy: 0.001,
                       "Raw duration of cap+1 second must be clamped to exactly the cap")
    }
}

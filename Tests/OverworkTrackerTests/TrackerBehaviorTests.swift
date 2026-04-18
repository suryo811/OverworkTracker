import XCTest
@testable import OverworkTracker

/// Deterministic scenarios that lock in the time-accounting behavior of
/// `ActiveWindowTracker`. Each test wires up a `FakeClock` + `FakeActivitySource`
/// + `InMemorySessionStore` so we can drive app switches, idle transitions,
/// and sleep/wake events directly without any real timers.
final class TrackerBehaviorTests: XCTestCase {
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

    // MARK: - Helpers

    private func startWithFrontmost(_ app: FrontmostApp, secondsSinceInput: TimeInterval = 0) {
        activity.frontmost = app
        activity.secondsSinceLastInput = secondsSinceInput
        tracker.start()
    }

    // MARK: - Core accounting

    func testSingleAppOverTwoMinutes_recordsFullDuration() {
        startWithFrontmost(safari)

        // 120s of continuous activity — simulate steady input and a few heartbeats.
        clock.advance(by: 30)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        clock.advance(by: 60)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        clock.advance(by: 30)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        tracker.stop()

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 120, accuracy: 0.001)
    }

    /// The original bug: a visit shorter than `pollingInterval` (30s) was
    /// recorded as 0s because duration was only added on the next tick.
    /// With real elapsed time this must no longer happen.
    func testAppSwitchBeforeFirstHeartbeat_recordsBothApps() {
        startWithFrontmost(safari)

        // 3s in Safari, switch to Xcode.
        clock.advance(by: 3)
        activity.simulateActivation(bundleID: xcode.bundleID, appName: xcode.appName)

        // 2s in Xcode, switch to Slack.
        clock.advance(by: 2)
        activity.simulateActivation(bundleID: slack.bundleID, appName: slack.appName)

        // 5s in Slack, then stop.
        clock.advance(by: 5)
        tracker.stop()

        XCTAssertEqual(store.all.count, 3)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 3, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.dt.Xcode"), 2, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.tinyspeck.slackmacgap"), 5, accuracy: 0.001)
    }

    // MARK: - Idle handling

    func testIdleTransitionCreditsOnlyActiveTime() {
        startWithFrontmost(safari)

        // 60s of active work, with heartbeats each reporting fresh input.
        clock.advance(by: 60)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        // User walks away. 6 minutes later a heartbeat fires; the idle API
        // reports 360s since last input. The tracker must credit up to the
        // moment input stopped, not up to "now".
        clock.advance(by: 360)
        activity.secondsSinceLastInput = 360
        tracker.heartbeat()

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.totalDuration, 60, accuracy: 1.0,
                       "Idle minutes must not be credited")
    }

    func testReturnFromIdleStartsNewSession() {
        startWithFrontmost(safari)

        // Work for 30s...
        clock.advance(by: 30)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        // ...go idle for 10 minutes...
        clock.advance(by: 600)
        activity.secondsSinceLastInput = 600
        tracker.heartbeat()

        // ...come back to the same app and work another 20s.
        clock.advance(by: 5)
        activity.secondsSinceLastInput = 1 // user interacted
        tracker.heartbeat() // this opens a fresh session

        clock.advance(by: 20)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        tracker.stop()

        XCTAssertEqual(store.all.count, 2, "Idle transition should split into two sessions")
        XCTAssertEqual(store.all[0].duration, 30, accuracy: 1.0)
        XCTAssertEqual(store.all[1].duration, 20, accuracy: 1.0)
        // Total must not include the 10 min idle gap.
        XCTAssertEqual(store.totalDuration, 50, accuracy: 1.0)
    }

    // MARK: - Sleep / wake

    func testSleepDoesNotAccumulateTime() {
        startWithFrontmost(safari)

        clock.advance(by: 1)
        activity.simulateSleep()

        // Machine is asleep for an hour.
        clock.advance(by: 3600)
        activity.secondsSinceLastInput = 3600
        activity.simulateWake()

        // On wake the user is still idle; no new session should open.
        tracker.stop()

        XCTAssertEqual(store.totalDuration, 1, accuracy: 0.5,
                       "Sleep gap must not be credited")
    }

    func testWakeIntoActiveUseStartsNewSession() {
        startWithFrontmost(safari)

        clock.advance(by: 10)
        activity.simulateSleep()
        clock.advance(by: 120)

        // Wake up with active input on Xcode.
        activity.secondsSinceLastInput = 0
        activity.frontmost = xcode
        activity.simulateWake()

        clock.advance(by: 30)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()
        tracker.stop()

        XCTAssertEqual(store.all.count, 2)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 10, accuracy: 0.5)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.dt.Xcode"), 30, accuracy: 0.5)
    }

    // MARK: - Excluded bundles & pause

    func testExcludedBundleIDSkipped() {
        settings.excludedBundleIDs = ["com.tinyspeck.slackmacgap"]

        startWithFrontmost(safari)

        clock.advance(by: 20)
        // Switch to excluded Slack — current Safari session commits, no new session opens.
        activity.simulateActivation(bundleID: slack.bundleID, appName: slack.appName)

        clock.advance(by: 60) // time in Slack is ignored
        activity.simulateActivation(bundleID: xcode.bundleID, appName: xcode.appName)

        clock.advance(by: 15)
        tracker.stop()

        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 20, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.tinyspeck.slackmacgap"), 0,
                       "Excluded app must never be recorded")
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.dt.Xcode"), 15, accuracy: 0.001)
    }

    func testStopCommitsOpenSessionWithRealElapsed() {
        startWithFrontmost(safari)
        clock.advance(by: 47)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].duration, 47, accuracy: 0.001)
    }

    func testStartWhileIdleDoesNotOpenSession() {
        activity.frontmost = safari
        activity.secondsSinceLastInput = 999 // already idle
        tracker.start()

        clock.advance(by: 60)
        tracker.heartbeat()

        XCTAssertEqual(store.all.count, 0,
                       "Starting while idle must not open a session until activity resumes")
    }

    func testLongAppSessionIsCappedAt24Hours() {
        startWithFrontmost(safari)
        clock.advance(by: 48 * 60 * 60) // 48 hours without any events (pathological)
        tracker.stop()

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].duration,
                       ActiveWindowTracker.maxSessionDuration,
                       accuracy: 0.001)
    }
}

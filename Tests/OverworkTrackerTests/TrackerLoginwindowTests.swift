import XCTest
@testable import OverworkTracker

/// Regression tests for the "macOS lock/login screen accumulates hours"
/// bug: `loginwindow` becoming frontmost must never produce a session, and
/// lock-without-full-sleep (which used to leave sessions dangling for the
/// duration of the lock) must commit the current session just like a real
/// sleep does.
final class TrackerLoginwindowTests: XCTestCase {
    private var clock: FakeClock!
    private var activity: FakeActivitySource!
    private var store: InMemorySessionStore!
    private var settings: FakeSettings!
    private var tracker: ActiveWindowTracker!

    private let safari = FrontmostApp(bundleID: "com.apple.Safari", appName: "Safari")
    private let xcode = FrontmostApp(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
    private let loginwindow = FrontmostApp(
        bundleID: "com.apple.loginwindow",
        appName: "loginwindow"
    )
    private let screensaver = FrontmostApp(
        bundleID: "com.apple.ScreenSaver.Engine",
        appName: "ScreenSaverEngine"
    )

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

    // MARK: - loginwindow never creates a session

    func testLoginwindowActivationDoesNotCreateSession() {
        startWithFrontmost(safari)

        clock.advance(by: 30)
        activity.simulateActivation(
            bundleID: loginwindow.bundleID,
            appName: loginwindow.appName
        )

        XCTAssertEqual(store.all.count, 1, "Safari session should commit; no loginwindow row created")
        XCTAssertEqual(store.all[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(store.all[0].duration, 30, accuracy: 0.001)
        XCTAssertEqual(
            store.totalDuration(forBundleID: "com.apple.loginwindow"), 0,
            "loginwindow must never appear in the store"
        )
    }

    func testScreensaverActivationDoesNotCreateSession() {
        startWithFrontmost(xcode)

        clock.advance(by: 5)
        activity.simulateActivation(
            bundleID: screensaver.bundleID,
            appName: screensaver.appName
        )

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(
            store.totalDuration(forBundleID: "com.apple.ScreenSaver.Engine"), 0,
            "Screen saver must never appear in the store"
        )
    }

    func testStartWithLoginwindowFrontmostDoesNotCreateSession() {
        // Tracker launches while the lock screen is showing (e.g. right after
        // login-at-boot, before the user's real session is fully up).
        startWithFrontmost(loginwindow)

        clock.advance(by: 120)
        tracker.heartbeat()

        XCTAssertEqual(
            store.all.count, 0,
            "Seeding with loginwindow as frontmost must not insert a row"
        )
    }

    func testLoginwindowHoursDoNotAccumulateBetweenRealApps() {
        // Simulates the reported 2h13m bug: user locks the Mac, loginwindow
        // becomes frontmost, the screen sleeps for hours, and eventually a
        // real app regains focus. The gap must be unaccounted for rather
        // than credited to loginwindow.
        startWithFrontmost(safari)

        clock.advance(by: 60)
        activity.simulateActivation(
            bundleID: loginwindow.bundleID,
            appName: loginwindow.appName
        )

        // Hours pass while the screen is locked. In the old code, the
        // heartbeat would have kept refreshing a loginwindow session's
        // duration up to `maxSessionDuration`. With the exclusion in place,
        // there is no such session — heartbeats are no-ops.
        clock.advance(by: 2 * 60 * 60 + 13 * 60) // 2h13m
        activity.secondsSinceLastInput = 2 * 60 * 60 + 13 * 60
        tracker.heartbeat()

        // User unlocks; Xcode becomes frontmost.
        activity.secondsSinceLastInput = 0
        activity.simulateActivation(
            bundleID: xcode.bundleID,
            appName: xcode.appName
        )

        clock.advance(by: 5)
        tracker.stop()

        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.Safari"), 60, accuracy: 0.001)
        XCTAssertEqual(store.totalDuration(forBundleID: "com.apple.dt.Xcode"), 5, accuracy: 0.001)
        XCTAssertEqual(
            store.totalDuration(forBundleID: "com.apple.loginwindow"), 0,
            "The locked interval must not be credited anywhere"
        )
    }

    // MARK: - Lock events behave like sleep

    func testLockEventCommitsOpenSession() {
        // `handleWillSleep` is the unified entry point for every "user is
        // going away" notification, including screen lock. Firing it must
        // commit the current session with the real elapsed duration.
        startWithFrontmost(safari)

        clock.advance(by: 42)
        activity.simulateSleep() // stands in for screen-lock / display-sleep

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].duration, 42, accuracy: 0.001)
    }

    func testUnlockAfterLongLockCreditsZeroToPreviousApp() {
        // The Mac was locked for two hours (no full system sleep). The
        // previously-frontmost app must be credited only its pre-lock
        // duration, and the locked interval itself must be credited to no
        // one.
        startWithFrontmost(safari)

        clock.advance(by: 30)
        activity.simulateSleep() // screen lock

        clock.advance(by: 2 * 60 * 60) // locked for 2h
        // On unlock the idle clock is still high until the user actually
        // types their password.
        activity.secondsSinceLastInput = 2 * 60 * 60
        activity.frontmost = safari
        activity.simulateWake()

        // User types password and returns to Safari.
        activity.secondsSinceLastInput = 0
        activity.simulateActivation(bundleID: safari.bundleID, appName: safari.appName)

        clock.advance(by: 20)
        tracker.stop()

        XCTAssertEqual(
            store.totalDuration(forBundleID: "com.apple.Safari"), 50, accuracy: 0.5,
            "Only the 30s before lock + 20s after unlock should be credited"
        )
    }
}

import XCTest
@testable import OverworkTracker

/// End-to-end test that runs `ActiveWindowTracker` against a real
/// `DatabaseManager` (on a temp path) with a scripted sequence of app
/// activations, heartbeats, and idle transitions. Asserts that the numbers
/// surfaced by `fetchSummaries(for:)` / `fetchTotalTime(for:)` match what a
/// user should expect for the scripted day.
///
/// This is the single most important "does it track time correctly" test —
/// if this regresses, user-visible time accounting is broken.
final class TimeTrackingIntegrationTests: XCTestCase {
    private var tempDir: URL!
    private var db: DatabaseManager!
    private var clock: FakeClock!
    private var activity: FakeActivitySource!
    private var settings: FakeSettings!
    private var tracker: ActiveWindowTracker!

    private let safari = FrontmostApp(bundleID: "com.apple.Safari", appName: "Safari")
    private let xcode = FrontmostApp(bundleID: "com.apple.dt.Xcode", appName: "Xcode")

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OverworkTrackerIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try DatabaseManager(databasePath: tempDir.appendingPathComponent("db.sqlite").path)

        clock = FakeClock()
        activity = FakeActivitySource()
        settings = FakeSettings()
        tracker = ActiveWindowTracker(
            clock: clock,
            activity: activity,
            store: db,
            settings: settings
        )
    }

    override func tearDownWithError() throws {
        tracker = nil
        settings = nil
        activity = nil
        clock = nil
        db = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testScriptedDayMatchesFetchSummaries() throws {
        let day = clock.now()

        // 1. Boot up in Safari, actively in use.
        activity.frontmost = safari
        activity.secondsSinceLastInput = 0
        tracker.start()

        // 2. 5 seconds of Safari, live-update via heartbeat.
        clock.advance(by: 5)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        // 3. Switch to Xcode (event-driven; commits Safari @ 5s, opens Xcode).
        activity.simulateActivation(bundleID: xcode.bundleID, appName: xcode.appName)

        // 4. 3 seconds of Xcode, live-update via heartbeat.
        clock.advance(by: 3)
        activity.secondsSinceLastInput = 1
        tracker.heartbeat()

        // 5. User steps away for 10 minutes. Heartbeat detects idle and
        //    commits Xcode with 3s (not 3s + 600s).
        clock.advance(by: 600)
        activity.secondsSinceLastInput = 600
        tracker.heartbeat()

        // Extra idle heartbeats must not keep adding time.
        clock.advance(by: 120)
        activity.secondsSinceLastInput = 720
        tracker.heartbeat()

        // 6. User returns to Safari and works another 2s, then stops.
        clock.advance(by: 5)
        activity.secondsSinceLastInput = 1
        activity.frontmost = safari
        tracker.heartbeat() // this opens a fresh Safari session

        clock.advance(by: 2)
        tracker.stop()

        // Per-app totals come out of the real DB.
        let summaries = try db.fetchSummaries(for: day)
        let total = try db.fetchTotalTime(for: day)

        let safariTotal = summaries.first(where: { $0.id == "com.apple.Safari" })?.totalDuration ?? 0
        let xcodeTotal = summaries.first(where: { $0.id == "com.apple.dt.Xcode" })?.totalDuration ?? 0

        XCTAssertEqual(safariTotal, 7, accuracy: 0.5,
                       "Safari should be credited 5s (before switch) + 2s (after return) = 7s")
        XCTAssertEqual(xcodeTotal, 3, accuracy: 0.5,
                       "Xcode should be credited exactly 3s, excluding the 10 min idle gap")
        XCTAssertEqual(total, 10, accuracy: 0.5,
                       "Day total must be the sum of active time only")

        // Ordering: Safari (7s) before Xcode (3s).
        XCTAssertEqual(summaries.map(\.id), ["com.apple.Safari", "com.apple.dt.Xcode"],
                       "fetchSummaries must order by duration descending")

        // And sessions are broken correctly: Safari × 2, Xcode × 1 = 3 rows.
        let allTotal = try db.fetchTotalTime(for: day)
        XCTAssertEqual(allTotal, safariTotal + xcodeTotal, accuracy: 0.001)
    }

    /// A second scripted scenario exercising sleep + wake through the real DB.
    func testSleepGapIsNotCredited() throws {
        let day = clock.now()

        activity.frontmost = safari
        activity.secondsSinceLastInput = 0
        tracker.start()

        clock.advance(by: 10)
        activity.simulateSleep()

        // Machine asleep for one hour.
        clock.advance(by: 3600)
        activity.secondsSinceLastInput = 3600
        activity.simulateWake()

        clock.advance(by: 5)
        tracker.stop()

        let total = try db.fetchTotalTime(for: day)
        XCTAssertEqual(total, 10, accuracy: 0.5,
                       "Sleep gap (3600s) and idle after wake must not be credited to any app")
    }
}

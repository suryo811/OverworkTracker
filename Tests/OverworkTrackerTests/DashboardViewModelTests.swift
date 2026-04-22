import XCTest
@testable import OverworkTracker

/// Tests `DashboardViewModel` behavior using the refactor-friendly
/// designated initializer. Wires up a temp-path `DatabaseManager`, a
/// `FakeActivitySource`-backed `ActiveWindowTracker`, and an isolated
/// `AppSettings` so tests never touch the production DB or
/// `UserDefaults.standard`.
final class DashboardViewModelTests: XCTestCase {
    private var tempDir: URL!
    private var db: DatabaseManager!
    private var clock: FakeClock!
    private var activity: FakeActivitySource!
    private var settings: AppSettings!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OverworkTrackerVMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try DatabaseManager(databasePath: tempDir.appendingPathComponent("db.sqlite").path)

        clock = FakeClock()
        activity = FakeActivitySource()

        suiteName = "OverworkTrackerVMTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = AppSettings(defaults: defaults)
    }

    override func tearDownWithError() throws {
        db = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        settings = nil
        activity = nil
        clock = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    private func makeTracker() -> ActiveWindowTracker {
        ActiveWindowTracker(
            clock: clock,
            activity: activity,
            store: db,
            settings: settings
        )
    }

    private func makeVM(
        tracker: ActiveWindowTracker?,
        startRefreshTimer: Bool = false
    ) -> DashboardViewModel {
        DashboardViewModel(
            database: db,
            tracker: tracker,
            settings: settings,
            startRefreshTimer: startRefreshTimer
        )
    }

    private func insert(
        appName: String,
        bundleID: String?,
        startTime: Date,
        duration: TimeInterval
    ) throws {
        let session = TrackingSession(
            appName: appName,
            bundleID: bundleID,
            windowTitle: nil,
            startTime: startTime,
            duration: duration,
            endTime: startTime.addingTimeInterval(duration)
        )
        _ = try db.insertSession(session)
    }

    private var todayNoon: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 12
        return cal.date(from: comps)!
    }

    // MARK: - Init & pause state

    func testInitStartsTrackerWhenNotPaused() {
        XCTAssertFalse(settings.isPaused)
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        XCTAssertTrue(tracker.isTracking,
                      "Tracker should auto-start when settings.isPaused is false")
        withExtendedLifetime(vm) {} // keep VM alive past the assertion
    }

    func testInitDoesNotStartTrackerWhenPaused() {
        settings.isPaused = true
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        XCTAssertFalse(tracker.isTracking,
                       "Tracker must not start when settings.isPaused is true")
        withExtendedLifetime(vm) {}
    }

    func testInitWithNilTrackerDoesNotCrash() {
        // Dashboard has a nil tracker when DB initialization fails; VM should still refresh.
        let vm = makeVM(tracker: nil)
        XCTAssertEqual(vm.appSummaries.count, 0)
    }

    // MARK: - Pause toggling

    func testTogglePauseStopsAndRestartsTracker() {
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        XCTAssertTrue(tracker.isTracking)

        vm.togglePause()
        XCTAssertTrue(settings.isPaused)
        XCTAssertFalse(tracker.isTracking, "togglePause to paused must stop the tracker")

        vm.togglePause()
        XCTAssertFalse(settings.isPaused)
        XCTAssertTrue(tracker.isTracking, "togglePause to unpaused must start the tracker")
    }

    // MARK: - Refresh & date navigation

    func testRefreshPopulatesSummariesForSelectedDate() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayNoon)!

        try insert(appName: "Safari", bundleID: "com.apple.Safari",
                   startTime: todayNoon, duration: 60)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: todayNoon.addingTimeInterval(120), duration: 180)
        try insert(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                   startTime: yesterday, duration: 900)

        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        // selectedDate defaults to today (init runs refresh()).
        XCTAssertEqual(vm.totalSeconds, 240, accuracy: 0.001)
        XCTAssertEqual(Set(vm.appSummaries.map(\.id)),
                       ["com.apple.Safari", "com.apple.dt.Xcode"])

        // Switching to yesterday triggers the didSet on selectedDate → refresh().
        vm.selectedDate = yesterday
        XCTAssertEqual(vm.totalSeconds, 900, accuracy: 0.001)
        XCTAssertEqual(vm.appSummaries.map(\.id), ["com.tinyspeck.slackmacgap"])
    }

    func testGoToNextDayBlockedOnToday() {
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        let before = vm.selectedDate
        XCTAssertTrue(vm.isToday)
        vm.goToNextDay()
        XCTAssertEqual(vm.selectedDate, before,
                       "goToNextDay must be a no-op when already on today")
        XCTAssertTrue(vm.isToday)
    }

    func testGoToPreviousDayThenToday() {
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)

        vm.goToPreviousDay()
        XCTAssertFalse(vm.isToday)
        XCTAssertTrue(Calendar.current.isDateInYesterday(vm.selectedDate))

        vm.goToToday()
        XCTAssertTrue(vm.isToday)
    }

    func testDateLabelReflectsSelection() {
        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        XCTAssertEqual(vm.dateLabel, "Today")
        vm.goToPreviousDay()
        XCTAssertEqual(vm.dateLabel, "Yesterday")
        vm.goToPreviousDay()
        XCTAssertNotEqual(vm.dateLabel, "Today")
        XCTAssertNotEqual(vm.dateLabel, "Yesterday")
    }

    // MARK: - Monthly summary

    func testLoadMonthlySummaryPopulatesMonthlySummary() throws {
        try insert(appName: "Safari", bundleID: "com.apple.Safari",
                   startTime: todayNoon, duration: 300)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: Calendar.current.date(byAdding: .day, value: -3, to: todayNoon)!,
                   duration: 600)

        let tracker = makeTracker()
        let vm = makeVM(tracker: tracker)
        XCTAssertNil(vm.monthlySummary, "monthlySummary must start nil until loaded")

        vm.loadMonthlySummary()

        let summary = try XCTUnwrap(vm.monthlySummary)
        XCTAssertEqual(summary.totalSeconds, 900, accuracy: 0.001)
        XCTAssertEqual(summary.activeDays, 2)
        XCTAssertEqual(summary.topApps.first?.bundleID, "com.apple.dt.Xcode")
    }

    // MARK: - CSV

    func testMakeCSVIncludesHeaderAndEscapesCommas() {
        let rows: [(date: String, appName: String, bundleID: String?, totalDuration: TimeInterval)] = [
            (date: "2026-04-20", appName: "Safari", bundleID: "com.apple.Safari", totalDuration: 60),
            (date: "2026-04-20", appName: "Weird, Name", bundleID: nil, totalDuration: 3661),
        ]

        let csv = DashboardViewModel.makeCSV(rows: rows)
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Date,App,Bundle ID,Duration (seconds),Formatted Duration")
        XCTAssertEqual(lines[1], "2026-04-20,Safari,com.apple.Safari,60,1m")
        XCTAssertEqual(lines[2], "2026-04-20,Weird; Name,,3661,1h 1m",
                       "Commas in app names must be replaced and nil bundle IDs must serialize as empty")
    }

    func testMakeCSVEmptyRowsStillEmitsHeader() {
        let csv = DashboardViewModel.makeCSV(rows: [])
        XCTAssertEqual(csv, "Date,App,Bundle ID,Duration (seconds),Formatted Duration")
    }

    // MARK: - Deinit

    func testDeinitStopsTracker() {
        let tracker = makeTracker()
        var vm: DashboardViewModel? = makeVM(tracker: tracker)
        XCTAssertTrue(tracker.isTracking)

        vm = nil
        _ = vm // silence unused-warning

        XCTAssertFalse(tracker.isTracking,
                       "VM deinit must stop the tracker so the heartbeat timer is invalidated")
    }
}

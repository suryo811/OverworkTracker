import XCTest
@testable import OverworkTracker

final class DatabaseManagerTests: XCTestCase {
    private var tempDir: URL!
    private var db: DatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OverworkTrackerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("tracker.sqlite").path
        db = try DatabaseManager(databasePath: dbPath)
    }

    override func tearDownWithError() throws {
        db = nil
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

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

    private var noon: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 12
        comps.minute = 0
        return cal.date(from: comps)!
    }

    // MARK: - Tests

    func testFetchSummariesGroupsByBundleID() throws {
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: noon, duration: 100)
        try insert(appName: "Safari", bundleID: "com.apple.Safari",
                   startTime: noon.addingTimeInterval(200), duration: 50)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: noon.addingTimeInterval(400), duration: 200)

        let summaries = try db.fetchSummaries(for: noon)
        XCTAssertEqual(summaries.count, 2)
        // Ordered by totalDuration desc.
        XCTAssertEqual(summaries[0].id, "com.apple.dt.Xcode")
        XCTAssertEqual(summaries[0].totalDuration, 200, accuracy: 0.001)
        XCTAssertEqual(summaries[1].id, "com.apple.Safari")
        XCTAssertEqual(summaries[1].totalDuration, 150, accuracy: 0.001)
    }

    func testFetchTotalTimeForDay() throws {
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: noon, duration: 100)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: noon.addingTimeInterval(400), duration: 250)

        let total = try db.fetchTotalTime(for: noon)
        XCTAssertEqual(total, 350, accuracy: 0.001)
    }

    func testFetchTotalTimeExcludesOtherDays() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: noon)!
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: yesterday, duration: 900)
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: noon, duration: 60)

        XCTAssertEqual(try db.fetchTotalTime(for: noon), 60, accuracy: 0.001)
        XCTAssertEqual(try db.fetchTotalTime(for: yesterday), 900, accuracy: 0.001)
    }

    func testFetchMonthlySummaryActiveDaysDistinct() throws {
        let cal = Calendar.current
        // Three different days in the last 30 days.
        let today = cal.startOfDay(for: noon).addingTimeInterval(60 * 60 * 10)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: today)!

        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: today, duration: 300)
        try insert(appName: "Safari", bundleID: "com.apple.Safari",
                   startTime: today.addingTimeInterval(60), duration: 60)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: twoDaysAgo, duration: 500)
        try insert(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                   startTime: tenDaysAgo, duration: 120)

        let summary = try db.fetchMonthlySummary()
        XCTAssertEqual(summary.activeDays, 3)
        XCTAssertEqual(summary.totalSeconds, 980, accuracy: 0.001)
        // Top apps ordered by total duration desc.
        XCTAssertEqual(summary.topApps.first?.bundleID, "com.apple.dt.Xcode")
    }

    func testUpdateSessionDurationOverwritesPreviousValue() throws {
        let session = TrackingSession(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: nil,
            startTime: noon,
            duration: 0,
            endTime: noon
        )
        let id = try db.insertSession(session)

        try db.updateSessionDuration(id: id, duration: 123, endTime: noon.addingTimeInterval(123))

        let total = try db.fetchTotalTime(for: noon)
        XCTAssertEqual(total, 123, accuracy: 0.001)
    }

    // MARK: - Edge cases

    func testFetchMonthlySummaryOnEmptyDatabase() throws {
        let summary = try db.fetchMonthlySummary()
        XCTAssertEqual(summary.totalSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(summary.activeDays, 1,
                       "activeDays must floor to 1 on an empty DB so daily-average division stays defined")
        XCTAssertTrue(summary.topApps.isEmpty)
    }

    func testFetchMonthlySummaryTruncatesToTop5() throws {
        // Insert 7 distinct apps with decreasing durations so ordering is
        // unambiguous.
        let apps: [(String, String, TimeInterval)] = [
            ("App7", "com.example.app7", 700),
            ("App6", "com.example.app6", 600),
            ("App5", "com.example.app5", 500),
            ("App4", "com.example.app4", 400),
            ("App3", "com.example.app3", 300),
            ("App2", "com.example.app2", 200),
            ("App1", "com.example.app1", 100),
        ]
        for (name, bundle, dur) in apps {
            try insert(appName: name, bundleID: bundle, startTime: noon, duration: dur)
        }

        let summary = try db.fetchMonthlySummary()
        XCTAssertEqual(summary.topApps.count, 5, "fetchMonthlySummary must truncate to the top 5 apps")
        XCTAssertEqual(summary.topApps.map(\.bundleID),
                       ["com.example.app7", "com.example.app6",
                        "com.example.app5", "com.example.app4",
                        "com.example.app3"])
        XCTAssertEqual(summary.totalSeconds, 2800, accuracy: 0.001,
                       "Total must still include every row, not just the top 5")
    }

    func testFetchMonthlySummaryGroupsNilBundleByAppName() throws {
        try insert(appName: "Unnamed", bundleID: nil, startTime: noon, duration: 40)
        try insert(appName: "Unnamed", bundleID: nil,
                   startTime: noon.addingTimeInterval(100), duration: 60)

        let summary = try db.fetchMonthlySummary()
        XCTAssertEqual(summary.topApps.count, 1,
                       "Two nil-bundle rows with the same appName should group into a single row")
        XCTAssertEqual(summary.topApps[0].appName, "Unnamed")
        XCTAssertEqual(summary.topApps[0].totalDuration, 100, accuracy: 0.001)
    }

    func testFetchMonthlySummaryRespectsCustomDaysArg() throws {
        // fetchMonthlySummary uses the current wall clock; anchor inserts to now.
        let now = Date()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!

        try insert(appName: "Recent", bundleID: "com.example.recent",
                   startTime: fiveDaysAgo, duration: 100)
        try insert(appName: "Older", bundleID: "com.example.older",
                   startTime: tenDaysAgo, duration: 500)

        let sevenDay = try db.fetchMonthlySummary(days: 7)
        XCTAssertEqual(sevenDay.totalSeconds, 100, accuracy: 0.001,
                       "7-day window must exclude the 10-days-ago row")
        XCTAssertEqual(sevenDay.topApps.map(\.bundleID), ["com.example.recent"])

        let thirtyDay = try db.fetchMonthlySummary(days: 30)
        XCTAssertEqual(thirtyDay.totalSeconds, 600, accuracy: 0.001,
                       "30-day window must include both rows")
    }

    func testFetchSummariesDayBoundaryInclusivity() throws {
        let dayStart = Calendar.current.startOfDay(for: noon)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        // Exactly at dayStart → included.
        try insert(appName: "StartApp", bundleID: "com.example.start",
                   startTime: dayStart, duration: 10)
        // Exactly at dayEnd → excluded (strict `<` upper bound).
        try insert(appName: "EndApp", bundleID: "com.example.end",
                   startTime: dayEnd, duration: 30)

        let summaries = try db.fetchSummaries(for: noon)
        XCTAssertEqual(summaries.map(\.id), ["com.example.start"],
                       "dayStart is inclusive; dayEnd is exclusive")
        XCTAssertEqual(try db.fetchTotalTime(for: noon), 10, accuracy: 0.001)
    }

    func testFetchTotalTimeReturnsZeroForDayWithNoRows() throws {
        let emptyDay = Calendar.current.date(byAdding: .day, value: -5, to: noon)!
        XCTAssertEqual(try db.fetchTotalTime(for: emptyDay), 0, accuracy: 0.001)
    }

    func testFetchDailySummariesAcrossDaysGroupsByDayAndApp() throws {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: noon)!

        // Today: Safari 100s + Safari 50s → merged 150s; Xcode 200s.
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: noon, duration: 100)
        try insert(appName: "Safari", bundleID: "com.apple.Safari",
                   startTime: noon.addingTimeInterval(300), duration: 50)
        try insert(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                   startTime: noon.addingTimeInterval(600), duration: 200)
        // Yesterday: Safari 75s.
        try insert(appName: "Safari", bundleID: "com.apple.Safari", startTime: yesterday, duration: 75)

        let rows = try db.fetchDailySummaries(from: yesterday, to: noon)

        XCTAssertEqual(rows.count, 3, "3 groups: (today, Safari), (today, Xcode), (yesterday, Safari)")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: noon)
        let yesterdayKey = formatter.string(from: yesterday)

        let todaySafari = rows.first { $0.date == todayKey && $0.bundleID == "com.apple.Safari" }
        let todayXcode = rows.first { $0.date == todayKey && $0.bundleID == "com.apple.dt.Xcode" }
        let yesterdaySafari = rows.first { $0.date == yesterdayKey && $0.bundleID == "com.apple.Safari" }

        XCTAssertEqual(try XCTUnwrap(todaySafari).totalDuration, 150, accuracy: 0.001,
                       "Two Safari rows on the same day must merge")
        XCTAssertEqual(try XCTUnwrap(todayXcode).totalDuration, 200, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(yesterdaySafari).totalDuration, 75, accuracy: 0.001,
                       "Same app on different days must remain separate groups")
    }

    func testFetchDailySummariesBundleNilFallsBackToAppName() throws {
        try insert(appName: "LegacyApp", bundleID: nil, startTime: noon, duration: 40)
        try insert(appName: "LegacyApp", bundleID: nil,
                   startTime: noon.addingTimeInterval(100), duration: 60)

        let rows = try db.fetchDailySummaries(from: noon, to: noon)
        XCTAssertEqual(rows.count, 1,
                       "Nil-bundle rows with the same appName must group to a single daily row")
        XCTAssertEqual(rows[0].appName, "LegacyApp")
        XCTAssertEqual(rows[0].bundleID, nil)
        XCTAssertEqual(rows[0].totalDuration, 100, accuracy: 0.001)
    }

    func testUpdateSessionDurationOnMissingIdDoesNotThrow() {
        XCTAssertNoThrow(
            try db.updateSessionDuration(id: 9999, duration: 10, endTime: noon),
            "Updating a non-existent id must be a silent no-op"
        )
    }
}

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
}

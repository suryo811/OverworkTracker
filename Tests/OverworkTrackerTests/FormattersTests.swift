import XCTest
@testable import OverworkTracker

/// Verifies the duration formatter shared by `AppUsageSummary` and
/// `MonthlySummary`. Boundary values (0, 59, 60, 3599, 3600, 3660) matter
/// because they flip which branch of the formatter is used.
final class FormattersTests: XCTestCase {

    // MARK: - AppUsageSummary.format

    func testFormatSubMinuteValuesRenderLessThanOneMinute() {
        XCTAssertEqual(AppUsageSummary.format(0), "< 1m")
        XCTAssertEqual(AppUsageSummary.format(30), "< 1m")
        XCTAssertEqual(AppUsageSummary.format(59), "< 1m")
    }

    func testFormatMinuteValuesRenderOnlyMinutes() {
        XCTAssertEqual(AppUsageSummary.format(60), "1m")
        XCTAssertEqual(AppUsageSummary.format(61), "1m")
        XCTAssertEqual(AppUsageSummary.format(119), "1m")
        XCTAssertEqual(AppUsageSummary.format(3599), "59m")
    }

    func testFormatHourBoundaryFlipsToHoursAndMinutes() {
        XCTAssertEqual(AppUsageSummary.format(3600), "1h 0m")
        XCTAssertEqual(AppUsageSummary.format(3661), "1h 1m")
        XCTAssertEqual(AppUsageSummary.format(36_000), "10h 0m")
        XCTAssertEqual(AppUsageSummary.format(36_060), "10h 1m")
    }

    func testFormattedDurationDelegatesToStaticFormatter() {
        let summary = AppUsageSummary(
            id: "com.example",
            appName: "Example",
            bundleID: "com.example",
            totalDuration: 3661,
            icon: nil
        )
        XCTAssertEqual(summary.formattedDuration, AppUsageSummary.format(3661))
        XCTAssertEqual(summary.formattedDuration, "1h 1m")
    }

    // MARK: - MonthlySummary computed properties

    func testMonthlySummaryTotalHoursFromSeconds() {
        let summary = MonthlySummary(totalSeconds: 3661, activeDays: 1, topApps: [])
        XCTAssertEqual(summary.totalHours, 3661.0 / 3600.0, accuracy: 1e-9)
    }

    func testMonthlySummaryDailyAverageDividesByActiveDays() {
        let oneDay = MonthlySummary(totalSeconds: 7200, activeDays: 1, topApps: [])
        XCTAssertEqual(oneDay.dailyAverageSeconds, 7200, accuracy: 1e-9)

        let sevenDay = MonthlySummary(totalSeconds: 7200, activeDays: 7, topApps: [])
        XCTAssertEqual(sevenDay.dailyAverageSeconds, 7200.0 / 7.0, accuracy: 1e-9)

        let thirtyDay = MonthlySummary(totalSeconds: 9000, activeDays: 30, topApps: [])
        XCTAssertEqual(thirtyDay.dailyAverageSeconds, 300, accuracy: 1e-9)
    }

    func testMonthlySummaryFormattedDailyAverageMatchesFormat() {
        let summary = MonthlySummary(totalSeconds: 7200, activeDays: 7, topApps: [])
        XCTAssertEqual(summary.formattedDailyAverage,
                       AppUsageSummary.format(7200.0 / 7.0))
    }

    func testMonthlySummaryEmptyTopAppsStillFormats() {
        let summary = MonthlySummary(totalSeconds: 0, activeDays: 1, topApps: [])
        XCTAssertEqual(summary.formattedTotal, "< 1m")
        XCTAssertEqual(summary.formattedDailyAverage, "< 1m")
    }

    func testMonthlySummaryFormattedTotalUsesSharedFormatter() {
        let summary = MonthlySummary(totalSeconds: 3660, activeDays: 1, topApps: [])
        XCTAssertEqual(summary.formattedTotal, "1h 1m")
    }
}

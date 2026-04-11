import AppKit

struct MonthlySummary {
    struct AppEntry {
        let appName: String
        let bundleID: String?
        let totalDuration: TimeInterval
        let icon: NSImage?
    }

    let totalSeconds: TimeInterval
    let activeDays: Int
    let topApps: [AppEntry]

    var totalHours: Double { totalSeconds / 3600 }
    var dailyAverageSeconds: TimeInterval { totalSeconds / Double(activeDays) }

    var formattedTotal: String {
        AppUsageSummary.format(totalSeconds)
    }

    var formattedDailyAverage: String {
        AppUsageSummary.format(dailyAverageSeconds)
    }
}

import AppKit
import Foundation

@Observable
final class DashboardViewModel {
    private(set) var appSummaries: [AppUsageSummary] = []
    private(set) var totalSecondsToday: TimeInterval = 0
    private(set) var isAccessibilityGranted = false

    private var db: DatabaseManager?
    private var tracker: ActiveWindowTracker?
    private var refreshTimer: Timer?

    var totalHoursToday: Double {
        totalSecondsToday / 3600.0
    }

    var formattedTotal: String {
        AppUsageSummary.format(totalSecondsToday)
    }

    var maxDuration: TimeInterval {
        appSummaries.first?.totalDuration ?? 1
    }

    init() {
        do {
            let database = try DatabaseManager()
            self.db = database
            let windowTracker = ActiveWindowTracker(db: database)
            self.tracker = windowTracker
            windowTracker.start()
        } catch {
            print("Failed to initialize database: \(error)")
        }

        isAccessibilityGranted = PermissionsManager.isAccessibilityGranted

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        guard let db else { return }
        do {
            appSummaries = try db.fetchTodaySummaries()
            totalSecondsToday = try db.fetchTotalHoursToday()
            isAccessibilityGranted = PermissionsManager.isAccessibilityGranted
        } catch {
            print("Failed to refresh: \(error)")
        }
    }

    func requestAccessibility() {
        PermissionsManager.requestAccessibility()
    }
}

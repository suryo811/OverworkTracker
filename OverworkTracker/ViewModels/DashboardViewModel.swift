import AppKit
import Foundation

@Observable
final class DashboardViewModel {
    private(set) var appSummaries: [AppUsageSummary] = []
    private(set) var totalSeconds: TimeInterval = 0
    private(set) var isAccessibilityGranted = false

    var selectedDate: Date = Date() {
        didSet { refresh() }
    }

    private let settings = AppSettings.shared
    private var db: DatabaseManager?
    private var tracker: ActiveWindowTracker?
    private var refreshTimer: Timer?

    var totalHours: Double {
        totalSeconds / 3600.0
    }

    var formattedTotal: String {
        AppUsageSummary.format(totalSeconds)
    }

    var maxDuration: TimeInterval {
        appSummaries.first?.totalDuration ?? 1
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: selectedDate)
        }
    }

    var isPaused: Bool {
        settings.isPaused
    }

    init() {
        do {
            let database = try DatabaseManager()
            self.db = database
            let windowTracker = ActiveWindowTracker(db: database)
            self.tracker = windowTracker
            if !settings.isPaused {
                windowTracker.start()
            }
        } catch {
            print("Failed to initialize database: \(error)")
        }

        isAccessibilityGranted = PermissionsManager.isAccessibilityGranted

        refreshTimer = Timer.scheduledTimer(withTimeInterval: settings.pollingInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        tracker?.stop()
    }

    func refresh() {
        guard let db else { return }
        do {
            appSummaries = try db.fetchSummaries(for: selectedDate)
            totalSeconds = try db.fetchTotalTime(for: selectedDate)
            isAccessibilityGranted = PermissionsManager.isAccessibilityGranted
        } catch {
            print("Failed to refresh: \(error)")
        }
    }

    func togglePause() {
        settings.isPaused.toggle()
        if settings.isPaused {
            tracker?.stop()
        } else {
            tracker?.start()
        }
    }

    func goToPreviousDay() {
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = prev
        }
    }

    func goToNextDay() {
        guard !isToday else { return }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = next
        }
    }

    func requestAccessibility() {
        PermissionsManager.requestAccessibility()
    }
}

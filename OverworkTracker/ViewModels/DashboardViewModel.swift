import AppKit
import Foundation

@Observable
final class DashboardViewModel {
    private(set) var appSummaries: [AppUsageSummary] = []
    private(set) var totalSeconds: TimeInterval = 0
    var showMonthlySummary = false
    private(set) var monthlySummary: MonthlySummary?

    var selectedDate: Date = Date() {
        didSet { refresh() }
    }

    private let settings = AppSettings.shared
    private var db: DatabaseManager?
    private var tracker: ActiveWindowTracker?
    private var refreshTimer: Timer?

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
            let windowTracker = ActiveWindowTracker(
                clock: SystemClock(),
                activity: NSWorkspaceActivitySource(),
                store: database,
                settings: settings
            )
            self.tracker = windowTracker
            if !settings.isPaused {
                windowTracker.start()
            }
        } catch {
            print("Failed to initialize database: \(error)")
        }

        // UI refresh is decoupled from the tracker's heartbeat — a fixed 2s
        // cadence keeps the live duration counter feeling real-time.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        } catch {
            print("Failed to refresh: \(error)")
        }
    }

    func loadMonthlySummary() {
        guard let db else { return }
        do {
            monthlySummary = try db.fetchMonthlySummary()
        } catch {
            print("Failed to load monthly summary: \(error)")
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

    func goToToday() {
        selectedDate = Date()
    }

    func exportCSV() {
        guard let db else { return }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        do {
            let summaries = try db.fetchDailySummaries(from: startDate, to: endDate)

            var lines = ["Date,App,Bundle ID,Duration (seconds),Formatted Duration"]
            for s in summaries {
                let name = s.appName.replacingOccurrences(of: ",", with: ";")
                let bundleID = s.bundleID ?? ""
                let hours = Int(s.totalDuration) / 3600
                let minutes = (Int(s.totalDuration) % 3600) / 60
                let formatted = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                lines.append("\(s.date),\(name),\(bundleID),\(Int(s.totalDuration)),\(formatted)")
            }
            let csv = lines.joined(separator: "\n")

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let startStr = formatter.string(from: startDate)
            let endStr = formatter.string(from: endDate)
            let fileName = "OverworkTracker_\(startStr)_to_\(endStr).csv"

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            print("Export failed: \(error)")
        }
    }
}

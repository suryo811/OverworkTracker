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

    private let settings: AppSettings
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

    /// Designated initializer. Accepts collaborators so tests can wire a
    /// temp-path database, a fake-backed tracker, and an isolated settings
    /// instance. The convenience `init()` wires up real production defaults.
    init(
        database: DatabaseManager?,
        tracker: ActiveWindowTracker?,
        settings: AppSettings,
        startRefreshTimer: Bool = true
    ) {
        self.db = database
        self.tracker = tracker
        self.settings = settings

        if let tracker, !settings.isPaused {
            tracker.start()
        }

        if startRefreshTimer {
            // UI refresh is decoupled from the tracker's heartbeat — a fixed 2s
            // cadence keeps the live duration counter feeling real-time.
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    convenience init() {
        let settings = AppSettings.shared
        var database: DatabaseManager?
        var tracker: ActiveWindowTracker?
        do {
            let openedDB = try DatabaseManager()
            database = openedDB
            tracker = ActiveWindowTracker(
                clock: SystemClock(),
                activity: NSWorkspaceActivitySource(),
                store: openedDB,
                settings: settings
            )
        } catch {
            print("Failed to initialize database: \(error)")
        }
        self.init(database: database, tracker: tracker, settings: settings)
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

    /// Pure CSV serializer for the daily-summary rows returned by
    /// `DatabaseManager.fetchDailySummaries`. Extracted so tests can verify
    /// the output without touching the filesystem or `NSWorkspace`.
    static func makeCSV(
        rows: [(date: String, appName: String, bundleID: String?, totalDuration: TimeInterval)]
    ) -> String {
        var lines = ["Date,App,Bundle ID,Duration (seconds),Formatted Duration"]
        for s in rows {
            let name = s.appName.replacingOccurrences(of: ",", with: ";")
            let bundleID = s.bundleID ?? ""
            let hours = Int(s.totalDuration) / 3600
            let minutes = (Int(s.totalDuration) % 3600) / 60
            let formatted = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            lines.append("\(s.date),\(name),\(bundleID),\(Int(s.totalDuration)),\(formatted)")
        }
        return lines.joined(separator: "\n")
    }

    func exportCSV() {
        guard let db else { return }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        do {
            let summaries = try db.fetchDailySummaries(from: startDate, to: endDate)
            let csv = Self.makeCSV(rows: summaries)

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

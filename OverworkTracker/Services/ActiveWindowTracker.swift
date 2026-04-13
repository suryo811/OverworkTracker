import AppKit
import Foundation

@Observable
final class ActiveWindowTracker {
    private let db: DatabaseManager
    private let settings = AppSettings.shared
    private var timer: Timer?
    private var currentSessionID: Int64?
    private var currentBundleID: String?
    private var currentSessionStart: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var wasIdle = false

    private(set) var isTracking = false

    init(db: DatabaseManager) {
        self.db = db
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true

        let interval = settings.pollingInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isTracking = false
        finalizeCurrentSession()
    }

    // MARK: - Polling

    private func tick() {
        // 1. Check idle
        if IdleDetector.isIdle(threshold: settings.idleThreshold) {
            if !wasIdle {
                finalizeCurrentSession()
                wasIdle = true
            }
            return
        }

        // Came back from idle
        if wasIdle {
            wasIdle = false
            currentSessionID = nil
        }

        // 2. Get frontmost app
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleID = frontApp.bundleIdentifier

        // 3. Skip excluded apps
        if let bundleID, settings.excludedBundleIDs.contains(bundleID) {
            if currentSessionID != nil {
                finalizeCurrentSession()
            }
            return
        }

        // 4. Compare with current session — session boundary is app change only
        let sameApp = bundleID == currentBundleID

        if let sessionID = currentSessionID, sameApp {
            accumulatedDuration += settings.pollingInterval
            let endTime = Date()
            try? db.updateSessionDuration(
                id: sessionID,
                duration: accumulatedDuration,
                endTime: endTime
            )
        } else {
            finalizeCurrentSession()
            startNewSession(appName: appName, bundleID: bundleID)
        }
    }

    // MARK: - Session Management

    private func startNewSession(appName: String, bundleID: String?) {
        let now = Date()
        let session = TrackingSession(
            appName: appName,
            bundleID: bundleID,
            windowTitle: nil,
            startTime: now,
            duration: 0,
            endTime: now
        )

        do {
            currentSessionID = try db.insertSession(session)
            currentBundleID = bundleID
            currentSessionStart = now
            accumulatedDuration = 0
        } catch {
            print("Failed to insert session: \(error)")
        }
    }

    private func finalizeCurrentSession() {
        currentSessionID = nil
        currentBundleID = nil
        currentSessionStart = nil
        accumulatedDuration = 0
    }
}

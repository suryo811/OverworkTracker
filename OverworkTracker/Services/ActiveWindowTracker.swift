import AppKit
import ApplicationServices
import Foundation

@Observable
final class ActiveWindowTracker {
    private let db: DatabaseManager
    private var timer: Timer?
    private var currentSessionID: Int64?
    private var currentBundleID: String?
    private var currentWindowTitle: String?
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

        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
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
        if IdleDetector.isIdle() {
            if !wasIdle {
                // Transition to idle: finalize current session
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

        // 3. Get window title (if accessibility granted)
        let windowTitle = Self.windowTitle(for: frontApp.processIdentifier)

        // 4. Compare with current session — session boundary is app change only
        let sameApp = bundleID == currentBundleID

        if let sessionID = currentSessionID, sameApp {
            // Extend current session, update window title in place
            accumulatedDuration += 5.0
            currentWindowTitle = windowTitle
            let endTime = Date()
            try? db.updateSessionDuration(
                id: sessionID,
                duration: accumulatedDuration,
                endTime: endTime
            )
        } else {
            // App changed — start a new session
            finalizeCurrentSession()
            startNewSession(appName: appName, bundleID: bundleID, windowTitle: windowTitle)
        }
    }

    // MARK: - Session Management

    private func startNewSession(appName: String, bundleID: String?, windowTitle: String?) {
        let now = Date()
        var session = TrackingSession(
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            startTime: now,
            duration: 0,
            endTime: now
        )

        do {
            currentSessionID = try db.insertSession(session)
            currentBundleID = bundleID
            currentWindowTitle = windowTitle
            currentSessionStart = now
            accumulatedDuration = 0
        } catch {
            print("Failed to insert session: \(error)")
        }
    }

    private func finalizeCurrentSession() {
        currentSessionID = nil
        currentBundleID = nil
        currentWindowTitle = nil
        currentSessionStart = nil
        accumulatedDuration = 0
    }

    // MARK: - Window Title via Accessibility

    private static func windowTitle(for pid: pid_t) -> String? {
        guard PermissionsManager.isAccessibilityGranted else { return nil }

        let axApp = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success else { return nil }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleResult == .success, let title = titleRef as? String else { return nil }
        return title
    }
}

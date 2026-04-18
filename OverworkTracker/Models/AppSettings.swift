import Foundation
import ServiceManagement

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // Stored properties — @Observable instruments these for change tracking.
    // Each uses didSet to persist the new value to UserDefaults.

    /// How often the tracker's heartbeat fires. The heartbeat is only used
    /// for idle detection and refreshing the live duration on disk so the
    /// dashboard feels real-time — app switches are event-driven and do not
    /// depend on this interval. Clamped 1–30s; default 5s.
    var heartbeatInterval: TimeInterval = {
        // Migrate the old `pollingInterval` key if present so existing users
        // don't see a stale 30s value.
        let defaults = UserDefaults.standard
        let legacy = defaults.double(forKey: "pollingInterval")
        let stored = defaults.double(forKey: "heartbeatInterval")
        if stored != 0 { return stored.clamped(to: 1...30) }
        if legacy != 0 { return min(legacy, 30).clamped(to: 1...30) }
        return 5
    }() {
        didSet { UserDefaults.standard.set(heartbeatInterval, forKey: "heartbeatInterval") }
    }

    var idleThreshold: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "idleThreshold")
        return stored == 0 ? 300 : stored.clamped(to: 60...900)
    }() {
        didSet { UserDefaults.standard.set(idleThreshold, forKey: "idleThreshold") }
    }

    var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "launchAtLogin") {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(launchAtLogin ? "register" : "unregister") launch at login: \(error)")
            }
        }
    }

    var excludedBundleIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? []) {
        didSet { UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs") }
    }

    var isPaused: Bool = UserDefaults.standard.bool(forKey: "isPaused") {
        didSet { UserDefaults.standard.set(isPaused, forKey: "isPaused") }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

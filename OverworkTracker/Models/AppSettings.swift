import Foundation
import ServiceManagement

@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    /// How often the tracker's heartbeat fires. The heartbeat is only used
    /// for idle detection and refreshing the live duration on disk so the
    /// dashboard feels real-time — app switches are event-driven and do not
    /// depend on this interval. Clamped 1–30s; default 5s.
    var heartbeatInterval: TimeInterval {
        didSet { defaults.set(heartbeatInterval, forKey: "heartbeatInterval") }
    }

    var idleThreshold: TimeInterval {
        didSet { defaults.set(idleThreshold, forKey: "idleThreshold") }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
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

    var excludedBundleIDs: Set<String> {
        didSet { defaults.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs") }
    }

    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: "isPaused") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate the old `pollingInterval` key if present so existing users
        // don't see a stale 30s value. Persist the migrated value under the
        // new key and remove the legacy one so the migration only runs once.
        // Note: property observers (didSet) don't fire during init, so any
        // persistence here must be done explicitly against `defaults`.
        let legacy = defaults.double(forKey: "pollingInterval")
        let storedHeartbeat = defaults.double(forKey: "heartbeatInterval")
        if storedHeartbeat != 0 {
            self.heartbeatInterval = storedHeartbeat.clamped(to: 1...30)
        } else if legacy != 0 {
            let migrated = legacy.clamped(to: 1...30)
            self.heartbeatInterval = migrated
            defaults.set(migrated, forKey: "heartbeatInterval")
            defaults.removeObject(forKey: "pollingInterval")
        } else {
            self.heartbeatInterval = 5
        }

        let storedIdle = defaults.double(forKey: "idleThreshold")
        self.idleThreshold = storedIdle == 0 ? 300 : storedIdle.clamped(to: 60...900)

        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.excludedBundleIDs = Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? [])
        self.isPaused = defaults.bool(forKey: "isPaused")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

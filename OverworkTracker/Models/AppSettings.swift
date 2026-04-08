import Foundation
import ServiceManagement

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // Stored properties — @Observable instruments these for change tracking.
    // Each uses didSet to persist the new value to UserDefaults.

    var pollingInterval: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "pollingInterval")
        return stored == 0 ? 30 : stored.clamped(to: 5...60)
    }() {
        didSet { UserDefaults.standard.set(pollingInterval, forKey: "pollingInterval") }
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

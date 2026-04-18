import Foundation
@testable import OverworkTracker

final class FakeActivitySource: ActivitySource {
    var frontmost: FrontmostApp?
    var secondsSinceLastInput: TimeInterval = 0

    private var activationHandler: ((FrontmostApp) -> Void)?
    private var willSleepHandler: (() -> Void)?
    private var didWakeHandler: (() -> Void)?

    func observeAppActivation(_ handler: @escaping (FrontmostApp) -> Void) {
        activationHandler = handler
    }

    func observeSleepWake(willSleep: @escaping () -> Void, didWake: @escaping () -> Void) {
        willSleepHandler = willSleep
        didWakeHandler = didWake
    }

    func stopObserving() {
        activationHandler = nil
        willSleepHandler = nil
        didWakeHandler = nil
    }

    // MARK: - Test controls

    func simulateActivation(bundleID: String?, appName: String) {
        let app = FrontmostApp(bundleID: bundleID, appName: appName)
        frontmost = app
        activationHandler?(app)
    }

    func simulateSleep() {
        willSleepHandler?()
    }

    func simulateWake() {
        didWakeHandler?()
    }
}

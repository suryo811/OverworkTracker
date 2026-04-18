import Foundation
@testable import OverworkTracker

final class FakeSettings: TrackerSettingsProviding {
    var heartbeatInterval: TimeInterval
    var idleThreshold: TimeInterval
    var excludedBundleIDs: Set<String>

    init(
        heartbeatInterval: TimeInterval = 5,
        idleThreshold: TimeInterval = 300,
        excludedBundleIDs: Set<String> = []
    ) {
        self.heartbeatInterval = heartbeatInterval
        self.idleThreshold = idleThreshold
        self.excludedBundleIDs = excludedBundleIDs
    }
}

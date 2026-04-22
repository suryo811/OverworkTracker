import XCTest
@testable import OverworkTracker

/// Verifies how `AppSettings` reads, clamps, and persists values via
/// `UserDefaults`. Each test uses an isolated suite so production defaults
/// are never touched.
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OverworkTrackerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Clamping on load

    func testHeartbeatIntervalClampedLowOnLoad() {
        defaults.set(0.1, forKey: "heartbeatInterval")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.heartbeatInterval, 1.0, accuracy: 0.001,
                       "Stored heartbeatInterval below the minimum (1s) must clamp up on load")
    }

    func testHeartbeatIntervalClampedHighOnLoad() {
        defaults.set(100.0, forKey: "heartbeatInterval")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.heartbeatInterval, 30.0, accuracy: 0.001,
                       "Stored heartbeatInterval above the maximum (30s) must clamp down on load")
    }

    func testIdleThresholdClampedLowOnLoad() {
        defaults.set(10.0, forKey: "idleThreshold")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.idleThreshold, 60.0, accuracy: 0.001,
                       "Stored idleThreshold below 60s must clamp to 60s")
    }

    func testIdleThresholdAllowsInfinityForNeverIdle() {
        defaults.set(TimeInterval.infinity, forKey: "idleThreshold")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.idleThreshold, TimeInterval.infinity,
                       "Stored idleThreshold of .infinity (the Never sentinel) must survive load without being clamped")
    }

    func testIdleThresholdPreservesLargeFiniteValuesOnLoad() {
        // The upper bound was previously 900s; widening it so Never can round-trip also
        // means any large value the user picks stays intact rather than snapping to 900.
        defaults.set(10_000.0, forKey: "idleThreshold")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.idleThreshold, 10_000.0, accuracy: 0.001,
                       "Stored idleThreshold above the old 900s cap must no longer be clamped down")
    }

    func testDefaultsWhenNothingStored() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.heartbeatInterval, 5.0, accuracy: 0.001)
        XCTAssertEqual(settings.idleThreshold, 300.0, accuracy: 0.001)
        XCTAssertFalse(settings.isPaused)
        XCTAssertTrue(settings.excludedBundleIDs.isEmpty)
    }

    // MARK: - Migration

    func testPollingIntervalMigratesToHeartbeatInterval() {
        // Legacy key only — simulates an upgrade from the old polling tracker.
        defaults.set(8.0, forKey: "pollingInterval")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.heartbeatInterval, 8.0, accuracy: 0.001,
                       "heartbeatInterval must be seeded from the legacy pollingInterval key")
        XCTAssertNil(defaults.object(forKey: "pollingInterval"),
                     "Legacy pollingInterval key must be removed after migration")
    }

    func testMigrationClampsLegacyPollingIntervalAboveMax() {
        defaults.set(60.0, forKey: "pollingInterval")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.heartbeatInterval, 30.0, accuracy: 0.001,
                       "Legacy values above 30s must still be clamped into the valid range")
    }

    func testHeartbeatIntervalTakesPrecedenceOverLegacyPolling() {
        defaults.set(8.0, forKey: "pollingInterval")
        defaults.set(12.0, forKey: "heartbeatInterval")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.heartbeatInterval, 12.0, accuracy: 0.001,
                       "Existing heartbeatInterval must win over legacy pollingInterval")
    }

    // MARK: - Persistence round-trips

    func testIsPausedPersistsAcrossInstances() {
        let a = AppSettings(defaults: defaults)
        a.isPaused = true

        let b = AppSettings(defaults: defaults)
        XCTAssertTrue(b.isPaused, "isPaused must round-trip through UserDefaults")
    }

    func testExcludedBundleIDsPersistAcrossInstances() {
        let a = AppSettings(defaults: defaults)
        a.excludedBundleIDs = ["com.apple.Safari", "com.tinyspeck.slackmacgap"]

        let b = AppSettings(defaults: defaults)
        XCTAssertEqual(b.excludedBundleIDs,
                       ["com.apple.Safari", "com.tinyspeck.slackmacgap"])

        a.excludedBundleIDs.remove("com.apple.Safari")
        let c = AppSettings(defaults: defaults)
        XCTAssertEqual(c.excludedBundleIDs, ["com.tinyspeck.slackmacgap"])
    }

    func testHeartbeatAndIdleValuesPersistAcrossInstances() {
        let a = AppSettings(defaults: defaults)
        a.heartbeatInterval = 7
        a.idleThreshold = 120

        let b = AppSettings(defaults: defaults)
        XCTAssertEqual(b.heartbeatInterval, 7, accuracy: 0.001)
        XCTAssertEqual(b.idleThreshold, 120, accuracy: 0.001)
    }

    func testIdleThresholdPersistsInfinityAcrossInstances() {
        let a = AppSettings(defaults: defaults)
        a.idleThreshold = .infinity

        let b = AppSettings(defaults: defaults)
        XCTAssertEqual(b.idleThreshold, .infinity,
                       "Never idle (.infinity) must round-trip through UserDefaults so the user's choice sticks across launches")
    }
}

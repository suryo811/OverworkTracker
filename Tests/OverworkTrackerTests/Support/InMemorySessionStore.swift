import Foundation
@testable import OverworkTracker

/// Array-backed SessionStore for deterministic assertions in tracker tests.
final class InMemorySessionStore: SessionStore {
    private(set) var sessions: [Int64: TrackingSession] = [:]
    private(set) var insertOrder: [Int64] = []
    private var nextID: Int64 = 1

    func insertSession(_ session: TrackingSession) throws -> Int64 {
        let id = nextID
        nextID += 1
        var stored = session
        stored.id = id
        sessions[id] = stored
        insertOrder.append(id)
        return id
    }

    func updateSessionDuration(id: Int64, duration: TimeInterval, endTime: Date) throws {
        guard var session = sessions[id] else { return }
        session.duration = duration
        session.endTime = endTime
        sessions[id] = session
    }

    // MARK: - Convenience accessors for tests

    /// Sessions in the order they were inserted.
    var all: [TrackingSession] {
        insertOrder.compactMap { sessions[$0] }
    }

    /// Total recorded duration across every session, grouped by bundleID
    /// when present (matches the dashboard query semantics).
    func totalDuration(forBundleID bundleID: String) -> TimeInterval {
        all.filter { $0.bundleID == bundleID }.reduce(0) { $0 + $1.duration }
    }

    func totalDuration(forAppName appName: String) -> TimeInterval {
        all.filter { $0.appName == appName }.reduce(0) { $0 + $1.duration }
    }

    var totalDuration: TimeInterval {
        all.reduce(0) { $0 + $1.duration }
    }
}

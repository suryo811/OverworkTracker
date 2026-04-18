import Foundation
@testable import OverworkTracker

final class FakeClock: Clock {
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    func now() -> Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }

    func set(_ date: Date) {
        current = date
    }
}

import CoreGraphics
import Foundation

enum IdleDetector {
    /// Seconds since the user last interacted with mouse/keyboard.
    static var secondsSinceLastInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)! // all event types
        )
    }

    /// Whether the user has been idle longer than the given threshold.
    static func isIdle(threshold: TimeInterval = 300) -> Bool {
        secondsSinceLastInput >= threshold
    }
}

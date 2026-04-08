import AppKit
import Foundation

struct AppUsageSummary: Identifiable {
    let id: String
    let appName: String
    let bundleID: String?
    let totalDuration: TimeInterval
    let icon: NSImage?
    let windowTitles: [String]

    var formattedDuration: String {
        Self.format(totalDuration)
    }

    static func format(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

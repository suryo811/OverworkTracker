import AppKit
import Foundation

struct AppUsageSummary: Identifiable {
    let id: String
    let appName: String
    let bundleID: String?
    let totalDuration: TimeInterval
    let icon: NSImage?

    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

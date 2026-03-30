import ApplicationServices
import Foundation

enum PermissionsManager {
    /// Returns true if the app has Accessibility permission.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission via system dialog.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

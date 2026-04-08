import AppKit
import SwiftUI

final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func open() {
        if let existing = window, existing.isVisible {
            existing.orderFrontRegardless()
            return
        }
        let controller = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: controller)
        win.title = "Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 420, height: 380))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        win.orderFrontRegardless()
    }
}

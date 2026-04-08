import SwiftUI

@main
struct OverworkTrackerApp: App {
    @State private var viewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(viewModel: viewModel)
                .frame(width: 320, height: 460)
        } label: {
            Label("OverworkTracker", systemImage: "clock.badge.exclamationmark")
        }
        .menuBarExtraStyle(.window)

    }
}

import SwiftUI

@main
struct OverworkTrackerApp: App {
    @State private var viewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(viewModel: viewModel)
                .frame(width: 360, height: 460)
        } label: {
            Label("OverworkTracker", systemImage: "flame.fill")
        }
        .menuBarExtraStyle(.window)

    }
}

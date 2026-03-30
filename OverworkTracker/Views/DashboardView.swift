import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .lastTextBaseline) {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.formattedTotal)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            .padding()

            Divider()

            // Accessibility prompt
            if !viewModel.isAccessibilityGranted {
                PermissionPromptView {
                    viewModel.requestAccessibility()
                }
                Divider()
            }

            // App breakdown list
            if viewModel.appSummaries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Tracking started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Switch between apps to see data here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.appSummaries) { summary in
                            AppBreakdownRow(
                                summary: summary,
                                maxDuration: viewModel.maxDuration
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Verdict banner
            VerdictBanner(totalHours: viewModel.totalHoursToday)
                .padding()
        }
        .background(.ultraThinMaterial)
    }
}

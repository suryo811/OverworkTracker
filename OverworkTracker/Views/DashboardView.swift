import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    var body: some View {
        VStack(spacing: 0) {
            // Date navigation header
            HStack {
                Button(action: viewModel.goToPreviousDay) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(viewModel.dateLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: viewModel.goToNextDay) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isToday)
                .opacity(viewModel.isToday ? 0.3 : 1)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Total time
            Text(viewModel.formattedTotal)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .padding(.bottom, 8)

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
                    Text(viewModel.isToday ? "Tracking started" : "No data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if viewModel.isToday {
                        Text("Switch between apps to see data here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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

            // Verdict banner (only when >= 1 hour)
            if viewModel.totalHours >= 1 {
                Divider()
                VerdictBanner(totalHours: viewModel.totalHours)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()

            // Toolbar
            HStack {
                Button(action: viewModel.togglePause) {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isPaused ? .orange : .secondary)

                Spacer()

                Button(action: viewModel.exportCSV) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Export as CSV")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit OverworkTracker")

            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

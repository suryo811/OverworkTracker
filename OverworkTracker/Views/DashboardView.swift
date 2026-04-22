import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var showResetConfirmation = false
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.showMonthlySummary {
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

                    Group {
                        if viewModel.isToday {
                            Text(viewModel.dateLabel)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(action: viewModel.goToToday) {
                                HStack(spacing: 4) {
                                    Text(viewModel.dateLabel)
                                        .font(.headline)
                                    Image(systemName: "arrow.uturn.left.circle.fill")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Jump to today")
                        }
                    }

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
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .padding(.bottom, 8)

                Divider()

                // App breakdown list
                if viewModel.appSummaries.isEmpty {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.appSummaries) { summary in
                                AppBreakdownRow(summary: summary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 260)
                }
            } else {
                // Monthly summary
                if let summary = viewModel.monthlySummary {
                    MonthlySummaryView(summary: summary)
                        .frame(height: 360)
                } else {
                    ProgressView()
                        .frame(height: 360)
                }
            }

            // Toolbar
            HStack {
                Button(action: viewModel.togglePause) {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.caption)
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isPaused ? Color.accentColor : .secondary)

                Spacer()

                // Today / 30 Days toggle
                Button(action: {
                    viewModel.showMonthlySummary.toggle()
                    if viewModel.showMonthlySummary {
                        viewModel.loadMonthlySummary()
                    }
                }) {
                    Text(viewModel.showMonthlySummary ? "Today" : "30 Days")
                        .font(.caption)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(viewModel.showMonthlySummary ? "Show today" : "Show 30-day summary")

                Button(action: { showResetConfirmation = true }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset all tracking data")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.caption)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit OverworkTracker")

            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
        .overlay {
            if showResetConfirmation {
                ResetConfirmationOverlay(
                    onCancel: { showResetConfirmation = false },
                    onConfirm: {
                        viewModel.resetAllData()
                        showResetConfirmation = false
                    }
                )
            }
        }
    }
}

private struct ResetConfirmationOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture(perform: onCancel)

            VStack(spacing: 10) {
                Text("Reset all tracking data?")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("This permanently deletes every recorded session. This cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                    )

                    Button(action: onConfirm) {
                        Text("Reset")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.85))
                    )
                }
                .padding(.top, 6)
            }
            .padding(16)
            .frame(maxWidth: 240)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .padding(.horizontal, 16)
        }
    }
}

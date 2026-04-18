import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
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
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .padding(.bottom, 8)

                Divider()

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

                if !viewModel.appSummaries.isEmpty {
                    ColorLegend()
                }
            } else {
                // Monthly summary
                if let summary = viewModel.monthlySummary {
                    MonthlySummaryView(summary: summary)
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
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
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.isPaused ? .orange : .secondary)

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

                Button(action: viewModel.exportCSV) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Export last 30 days as CSV")

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
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
    }
}

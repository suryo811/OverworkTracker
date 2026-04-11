import SwiftUI

struct MonthlySummaryView: View {
    let summary: MonthlySummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Stats grid
                HStack(spacing: 12) {
                    StatCard(title: "Total", value: summary.formattedTotal, icon: "clock.fill", color: .blue)
                    StatCard(title: "Daily Avg", value: summary.formattedDailyAverage, icon: "chart.bar.fill", color: .orange)
                    StatCard(title: "Active Days", value: "\(summary.activeDays)", icon: "calendar", color: .green)
                }

                if !summary.topApps.isEmpty {
                    Text("Top Apps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(Array(summary.topApps.enumerated()), id: \.offset) { index, app in
                            HStack(spacing: 10) {
                                Text("#\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20)

                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 22, height: 22)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                } else {
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                }

                                Text(app.appName)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Text(AppUsageSummary.format(app.totalDuration))
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

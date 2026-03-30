import SwiftUI

struct AppBreakdownRow: View {
    let summary: AppUsageSummary
    let maxDuration: TimeInterval

    private var barFraction: Double {
        guard maxDuration > 0 else { return 0 }
        return min(summary.totalDuration / maxDuration, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let icon = summary.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }

            // App name and bar
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.appName)
                    .font(.subheadline)
                    .lineLimit(1)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.75))
                        .frame(width: max(geo.size.width * barFraction, 4))
                }
                .frame(height: 6)
            }

            Spacer()

            // Duration
            Text(summary.formattedDuration)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var barColor: Color {
        switch summary.totalDuration {
        case ..<1800:     return .green
        case 1800..<3600: return .blue
        case 3600..<7200: return .orange
        default:          return .red
        }
    }
}

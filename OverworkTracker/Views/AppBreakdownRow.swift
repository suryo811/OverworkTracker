import SwiftUI

struct AppBreakdownRow: View {
    let summary: AppUsageSummary
    let maxDuration: TimeInterval

    @State private var isExpanded = false

    private var barFraction: Double {
        guard maxDuration > 0 else { return 0 }
        return min(summary.totalDuration / maxDuration, 1.0)
    }

    private var dedupedTitles: [String] {
        var seen = Set<String>()
        return summary.windowTitles.filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // App icon
                if let icon = summary.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                // App name and bar
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.appName)
                        .font(.subheadline)
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(maxWidth: .infinity)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor.opacity(0.8))
                                .frame(width: max(geo.size.width * barFraction, 4))
                        }
                    }
                    .frame(height: 5)
                }

                // Duration
                Text(summary.formattedDuration)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Expand chevron — always reserves space, invisible when no titles
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .frame(width: 12)
                    .opacity(dedupedTitles.isEmpty ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !dedupedTitles.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Expanded window titles
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(dedupedTitles, id: \.self) { title in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(barColor.opacity(0.5))
                                .frame(width: 2, height: 12)
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 34)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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

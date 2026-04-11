import SwiftUI

struct ColorLegend: View {
    private let items: [(Color, String)] = [
        (.green, "< 30m"),
        (.blue, "30m–1h"),
        (.orange, "1–2h"),
        (.red, "2h+"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.1) { color, label in
                HStack(spacing: 4) {
                    Circle()
                        .fill(color.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

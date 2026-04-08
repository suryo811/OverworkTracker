import SwiftUI

struct VerdictBanner: View {
    let totalHours: Double

    private var tier: Int {
        switch totalHours {
        case ..<1:    return 0
        case 1..<2:   return 1
        case 2..<4:   return 2
        case 4..<6:   return 3
        case 6..<8:   return 4
        case 8..<10:  return 5
        case 10..<12: return 6
        default:      return 7
        }
    }

    private var verdict: (title: String, subtitle: String, symbol: String, color: Color) {
        switch totalHours {
        case ..<1:
            return ("Warming up", "You just got here. Coffee's still warm.", "cup.and.saucer.fill", .green)
        case 1..<2:
            return ("Getting started", "Ease into it. No rush.", "figure.walk", .green)
        case 2..<4:
            return ("In the zone", "Productive. Suspicious, but productive.", "bolt.fill", .blue)
        case 4..<6:
            return ("Solid shift", "Your chair is getting concerned.", "chair.fill", .blue)
        case 6..<8:
            return ("Full day", "Touch grass? Just a thought.", "leaf.fill", .yellow)
        case 8..<10:
            return ("Overworking", "Your laptop filed a complaint with HR.", "exclamationmark.triangle.fill", .orange)
        case 10..<12:
            return ("Send help", "Even your cursor is trying to leave.", "sos", .red)
        default:
            return ("Intervention needed", "We're calling your emergency contacts.", "phone.arrow.up.right.fill", .red)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: verdict.symbol)
                .font(.title2)
                .foregroundStyle(verdict.color)
                .frame(width: 28)
                .animation(.easeInOut(duration: 0.4), value: tier)

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.title)
                    .font(.subheadline.weight(.semibold))
                    .animation(.easeInOut(duration: 0.4), value: tier)
                Text(verdict.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.4), value: tier)
            }

            Spacer()
        }
    }
}

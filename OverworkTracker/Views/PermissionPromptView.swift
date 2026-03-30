import SwiftUI

struct PermissionPromptView: View {
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Enable window titles")
                    .font(.subheadline.weight(.medium))
                Text("Grant Accessibility to see which window you're in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

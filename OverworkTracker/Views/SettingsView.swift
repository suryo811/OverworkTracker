import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var newExclusionBundleID = ""

    var body: some View {
        Form {
            Section("General") {
                HStack {
                    Text("Heartbeat interval")
                    Spacer()
                    Picker("", selection: $settings.heartbeatInterval) {
                        Text("1s").tag(1.0 as TimeInterval)
                        Text("5s").tag(5.0 as TimeInterval)
                        Text("15s").tag(15.0 as TimeInterval)
                        Text("30s").tag(30.0 as TimeInterval)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack {
                    Text("Idle timeout")
                    Spacer()
                    Picker("", selection: $settings.idleThreshold) {
                        Text("1 min").tag(60.0 as TimeInterval)
                        Text("3 min").tag(180.0 as TimeInterval)
                        Text("5 min").tag(300.0 as TimeInterval)
                        Text("10 min").tag(600.0 as TimeInterval)
                        Text("15 min").tag(900.0 as TimeInterval)
                        Text("Never").tag(TimeInterval.infinity)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Excluded Apps") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(appName(for: bundleID) ?? bundleID)
                            Spacer()
                            Button(role: .destructive) {
                                settings.excludedBundleIDs.remove(bundleID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    TextField("Bundle ID (e.g. com.apple.Safari)", text: $newExclusionBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newExclusionBundleID.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        settings.excludedBundleIDs.insert(trimmed)
                        newExclusionBundleID = ""
                    }
                    .disabled(newExclusionBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }
}

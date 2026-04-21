import QuietTermCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appModel.appearance) {
                    ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Sync") {
                LabeledContent("Status", value: appModel.syncStatus)
                Text("Host profiles and non-secret preferences sync through iCloud when available. SSH keys and passwords stay local.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AppModel.bootstrap())
    }
}

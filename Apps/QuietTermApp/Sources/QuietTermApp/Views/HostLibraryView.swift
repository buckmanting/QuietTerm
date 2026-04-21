import QuietTermCore
import SwiftUI

struct HostLibraryView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            Section("Hosts") {
                ForEach(appModel.profiles) { profile in
                    Button {
                        appModel.openSession(for: profile)
                    } label: {
                        HostProfileRow(profile: profile)
                    }
                }
            }

            Section("Beta") {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg.rectangle")
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Quiet Term")
        .toolbar {
            Button {
                // Profile creation is tracked in KAN-7.
            } label: {
                Label("Add Host", systemImage: "plus")
            }
        }
    }
}

private struct HostProfileRow: View {
    let profile: HostProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.alias)
                .font(.headline)
            Text(profile.connectionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(profile.authMethod.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HostLibraryView()
            .environmentObject(AppModel.bootstrap())
    }
}

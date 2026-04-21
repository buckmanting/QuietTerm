import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var exportText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                exportText = appModel.diagnosticSnapshot().exportText()
            } label: {
                Label("Generate Diagnostics", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)

            TextEditor(text: $exportText)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay {
                    if exportText.isEmpty {
                        ContentUnavailableView(
                            "No Export",
                            systemImage: "lock.shield",
                            description: Text("Diagnostics are generated only after explicit user action and are redacted before display.")
                        )
                    }
                }
        }
        .padding()
        .navigationTitle("Diagnostics")
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environmentObject(AppModel.bootstrap())
    }
}

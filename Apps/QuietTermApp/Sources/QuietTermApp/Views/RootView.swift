import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HostLibraryView()
        } detail: {
            TerminalTabsView()
        }
        .sheet(item: passwordPromptBinding) { request in
            PasswordPromptView(
                request: request,
                onSubmit: { password in
                    appModel.submitPassword(password, for: request)
                },
                onCancel: {
                    appModel.cancelPasswordPrompt(for: request)
                }
            )
            .interactiveDismissDisabled()
        }
        .alert(item: hostKeyPromptBinding) { request in
            Alert(
                title: Text("Trust Host Key?"),
                message: Text(hostKeyMessage(for: request)),
                primaryButton: .default(Text("Trust")) {
                    appModel.trustHostKey(for: request)
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    appModel.rejectHostKey(for: request)
                }
            )
        }
    }

    private var passwordPromptBinding: Binding<PasswordPromptRequest?> {
        Binding {
            appModel.passwordPrompt
        } set: { newValue in
            appModel.passwordPrompt = newValue
        }
    }

    private var hostKeyPromptBinding: Binding<HostKeyPromptRequest?> {
        Binding {
            appModel.hostKeyPrompt
        } set: { newValue in
            appModel.hostKeyPrompt = newValue
        }
    }

    private func hostKeyMessage(for request: HostKeyPromptRequest) -> String {
        """
        \(request.fingerprint.hostIdentity)
        \(request.fingerprint.algorithm)
        SHA256:\(request.fingerprint.sha256Fingerprint)
        """
    }
}

private struct PasswordPromptView: View {
    let request: PasswordPromptRequest
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(request.hostAlias) {
                    Text(request.connectionLabel)
                        .foregroundStyle(.secondary)
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("quietterm.password.field")
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
            }
            .navigationTitle("SSH Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect", action: submit)
                        .accessibilityIdentifier("quietterm.password.connect")
                        .disabled(password.isEmpty)
                }
            }
        }
    }

    private func submit() {
        let submittedPassword = password
        password = ""
        onSubmit(submittedPassword)
    }

    private func cancel() {
        password = ""
        onCancel()
    }
}

#Preview {
    RootView()
        .environmentObject(AppModel.bootstrap())
}

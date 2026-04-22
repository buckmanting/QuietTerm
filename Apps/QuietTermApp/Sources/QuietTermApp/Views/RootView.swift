import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var compactTerminalPresented = false

    var body: some View {
        content
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
        .onAppear {
            syncNavigationSelection()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            syncNavigationSelection()
        }
        .onChange(of: appModel.selectedSessionID) { _, selectedSessionID in
            withAnimation {
                if horizontalSizeClass == .compact {
                    compactTerminalPresented = selectedSessionID != nil
                } else {
                    preferredCompactColumn = selectedSessionID == nil ? .sidebar : .detail
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                HostLibraryView()
                    .navigationDestination(isPresented: compactTerminalBinding) {
                        TerminalTabsView()
                    }
            }
        } else {
            NavigationSplitView(
                columnVisibility: $columnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                HostLibraryView()
            } detail: {
                TerminalTabsView()
            }
        }
    }

    private var compactTerminalBinding: Binding<Bool> {
        Binding(
            get: {
                compactTerminalPresented
            },
            set: { isPresented in
                compactTerminalPresented = isPresented
                if !isPresented {
                    appModel.selectedSessionID = nil
                }
            }
        )
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

    private func syncNavigationSelection() {
        if horizontalSizeClass == .compact {
            compactTerminalPresented = appModel.selectedSessionID != nil
        } else {
            preferredCompactColumn = appModel.selectedSessionID == nil ? .sidebar : .detail
        }
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

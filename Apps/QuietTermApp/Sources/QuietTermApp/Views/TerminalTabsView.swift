import QuietTermCore
import SwiftUI

struct TerminalTabsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if appModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No Session",
                    systemImage: "terminal",
                    description: Text("Open a host from the library to start a foreground SSH session.")
                )
            } else {
                sessionPicker
                Divider()

                if let session = appModel.selectedSession {
                    TerminalPlaceholderView(session: session)
                }
            }
        }
        .navigationTitle(appModel.selectedSession?.title ?? "Terminal")
    }

    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.sessions) { session in
                    Button {
                        appModel.selectedSessionID = session.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                            Text(session.title)
                                .lineLimit(1)
                            Button {
                                appModel.closeSession(session)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            session.id == appModel.selectedSessionID ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct TerminalPlaceholderView: View {
    let session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(stateLabel, systemImage: stateIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("$ ssh \(session.title)")
            Text("Quiet Term beta shell adapter pending.")
                .foregroundStyle(.secondary)
            Text("This placeholder will be replaced by the SwiftTerm/libssh2 integration.")
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(Color.black)
        .foregroundStyle(Color.green)
    }

    private var stateLabel: String {
        switch session.state {
        case .idle:
            "Idle"
        case .verifyingHostKey:
            "Verifying host key"
        case .authenticating:
            "Authenticating"
        case .connected:
            "Connected"
        case .disconnected(let reason):
            reason ?? "Disconnected"
        case .failed(_, let message):
            message
        }
    }

    private var stateIcon: String {
        switch session.state {
        case .connected:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        default:
            "circle"
        }
    }
}

#Preview {
    TerminalTabsView()
        .environmentObject(AppModel.bootstrap())
}

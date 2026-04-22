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
                    TerminalSessionView(
                        session: session,
                        outputCounter: appModel.terminalOutputCounters[session.id] ?? 0,
                        drainOutput: {
                            appModel.drainTerminalOutput(for: session.id)
                        },
                        sendInput: { data in
                            appModel.sendTerminalInput(data, to: session.id)
                        },
                        retrySession: {
                            appModel.retrySession(session.id)
                        },
                        openNewSession: {
                            appModel.openNewSession(matching: session.id)
                        }
                    )
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
                            .accessibilityIdentifier("quietterm.session.close")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            session.id == appModel.selectedSessionID ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quietterm.session.tab")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct TerminalSessionView: View {
    let session: TerminalSession
    let outputCounter: Int
    let drainOutput: () -> [Data]
    let sendInput: (Data) -> Void
    let retrySession: () -> Void
    let openNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: stateIcon)
                    Text(stateLabel)
                        .accessibilityIdentifier("quietterm.session.state")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if session.state.isRetryable {
                    HStack(spacing: 8) {
                        Button("Retry", action: retrySession)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .accessibilityIdentifier("quietterm.session.retry")
                        Button("New Session", action: openNewSession)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .accessibilityIdentifier("quietterm.session.new")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))

            SwiftTermRendererView(
                sessionID: session.id,
                outputCounter: outputCounter,
                drainOutput: drainOutput,
                sendInput: sendInput
            )
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .idle:
            "Renderer fixture"
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
        case .disconnected:
            "wifi.exclamationmark"
        case .failed:
            "exclamationmark.triangle"
        default:
            "terminal"
        }
    }
}

#Preview {
    TerminalTabsView()
        .environmentObject(AppModel.bootstrap())
}

private extension ConnectionState {
    var isRetryable: Bool {
        switch self {
        case .disconnected, .failed:
            true
        default:
            false
        }
    }
}

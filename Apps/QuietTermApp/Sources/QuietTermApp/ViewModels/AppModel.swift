import Foundation
import QuietTermCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [HostProfile]
    @Published var sessions: [TerminalSession]
    @Published var selectedSessionID: UUID?
    @Published var appearance: AppearancePreference
    @Published var syncStatus: String
    @Published var hostLibraryBanner: HostLibraryBanner?
    @Published var passwordPrompt: PasswordPromptRequest?
    @Published var hostKeyPrompt: HostKeyPromptRequest?
    @Published private(set) var terminalOutputCounters: [UUID: Int]

    private let sshClient: any SSHClient
    private var hostKeyTrustStore: InMemoryHostKeyTrustStore
    private var activeSessions: [UUID: any SSHSession]
    private var sessionTasks: [UUID: Task<Void, Never>]
    private var pendingTerminalOutput: [UUID: [Data]]
    private var passwordContinuations: [UUID: CheckedContinuation<SSHPasswordCredential, Error>]
    private var hostKeyContinuations: [UUID: CheckedContinuation<Bool, Never>]

    init(
        profiles: [HostProfile] = [],
        sessions: [TerminalSession] = [],
        selectedSessionID: UUID? = nil,
        appearance: AppearancePreference = .dark,
        syncStatus: String = "Local mode",
        sshClient: any SSHClient = DefaultSSHClient.make(),
        hostKeyTrustStore: InMemoryHostKeyTrustStore = InMemoryHostKeyTrustStore()
    ) {
        self.profiles = profiles
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.appearance = appearance
        self.syncStatus = syncStatus
        self.sshClient = sshClient
        self.hostKeyTrustStore = hostKeyTrustStore
        self.hostLibraryBanner = nil
        self.passwordPrompt = nil
        self.hostKeyPrompt = nil
        self.terminalOutputCounters = [:]
        self.activeSessions = [:]
        self.sessionTasks = [:]
        self.pendingTerminalOutput = [:]
        self.passwordContinuations = [:]
        self.hostKeyContinuations = [:]
    }

    static func bootstrap(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppModel {
        let sampleProfile = HostProfile(
            alias: environment["QUIETTERM_SSH_ALIAS"] ?? "Example host",
            hostname: environment["QUIETTERM_SSH_HOST"] ?? "example.com",
            port: UInt16(environment["QUIETTERM_SSH_PORT"] ?? "") ?? 22,
            username: environment["QUIETTERM_SSH_USERNAME"] ?? "deploy",
            authMethod: .password(savedSecretID: nil),
            tags: ["beta"],
            folderName: "Servers"
        )

        let sshClient: any SSHClient
        #if DEBUG
        if environment["QUIETTERM_UI_TEST_MOCK_SSH"] == "1" {
            sshClient = UITestSSHClient()
        } else {
            sshClient = DefaultSSHClient.make()
        }
        #else
        sshClient = DefaultSSHClient.make()
        #endif

        return AppModel(
            profiles: [sampleProfile],
            sshClient: sshClient
        )
    }

    var selectedSession: TerminalSession? {
        guard let selectedSessionID else {
            return sessions.first
        }

        return sessions.first { $0.id == selectedSessionID }
    }

    func openSession(for profile: HostProfile) {
        guard case .password = profile.authMethod else {
            hostLibraryBanner = HostLibraryBanner(
                message: "\(profile.authMethod.displayName) is outside KAN-16."
            )
            return
        }

        var session = TerminalSession(
            profileID: profile.id,
            title: profile.alias,
            state: .authenticating
        )
        session.lastEventAt = Date()
        sessions.append(session)
        selectedSessionID = session.id

        let request = SSHConnectionRequest(
            profile: profile,
            terminalSize: TerminalSize(columns: 80, rows: 24)
        )

        sessionTasks[session.id] = Task { [weak self] in
            await self?.runSession(sessionID: session.id, request: request)
        }
    }

    func closeSession(_ session: TerminalSession) {
        sessionTasks[session.id]?.cancel()
        sessionTasks[session.id] = nil
        let activeSession = activeSessions.removeValue(forKey: session.id)
        pendingTerminalOutput.removeValue(forKey: session.id)
        terminalOutputCounters.removeValue(forKey: session.id)
        passwordContinuations.removeValue(forKey: session.id)?.resume(throwing: SSHConnectionError.passwordCancelled)
        hostKeyContinuations.removeValue(forKey: session.id)?.resume(returning: false)
        sessions.removeAll { $0.id == session.id }
        selectedSessionID = sessions.last?.id

        Task {
            await activeSession?.close()
        }
    }

    func submitPassword(_ password: String, for request: PasswordPromptRequest) {
        guard let continuation = passwordContinuations.removeValue(forKey: request.sessionID) else {
            return
        }

        passwordPrompt = nil
        continuation.resume(returning: SSHPasswordCredential(password))
    }

    func cancelPasswordPrompt(for request: PasswordPromptRequest?) {
        guard let request else {
            return
        }

        passwordPrompt = nil
        passwordContinuations.removeValue(forKey: request.sessionID)?.resume(throwing: SSHConnectionError.passwordCancelled)
    }

    func trustHostKey(for request: HostKeyPromptRequest) {
        hostKeyPrompt = nil
        hostKeyTrustStore.trust(request.fingerprint)
        let continuation = hostKeyContinuations.removeValue(forKey: request.sessionID)
        Task { @MainActor in
            // Delay continuation slightly so SwiftUI fully dismisses the host-key alert
            // before presenting the password sheet for the same session.
            try? await Task.sleep(nanoseconds: 150_000_000)
            continuation?.resume(returning: true)
        }
    }

    func rejectHostKey(for request: HostKeyPromptRequest?) {
        guard let request else {
            return
        }

        hostKeyPrompt = nil
        let continuation = hostKeyContinuations.removeValue(forKey: request.sessionID)
        Task { @MainActor in
            await Task.yield()
            continuation?.resume(returning: false)
        }
    }

    func dismissHostLibraryBanner() {
        hostLibraryBanner = nil
    }

    func sendTerminalInput(_ data: Data, to sessionID: UUID) {
        guard let activeSession = activeSessions[sessionID] else {
            return
        }

        Task {
            try? await activeSession.send(data)
        }
    }

    func drainTerminalOutput(for sessionID: UUID) -> [Data] {
        let output = pendingTerminalOutput[sessionID] ?? []
        pendingTerminalOutput[sessionID] = []
        return output
    }

    func diagnosticSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: "0.1.0",
            buildNumber: "1",
            deviceModel: "Simulator or device",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            syncStatus: syncStatus,
            profiles: profiles.map { $0.withoutSecretsForSync() },
            sessions: sessions,
            events: ["App shell initialized"]
        )
    }

    private func runSession(sessionID: UUID, request: SSHConnectionRequest) async {
        let handlers = SSHConnectionHandlers(
            requestPassword: { [weak self] profile in
                try await self?.requestPassword(for: profile, sessionID: sessionID) ?? SSHPasswordCredential(bytes: [])
            },
            validateHostKey: { [weak self] fingerprint in
                await self?.validateHostKey(fingerprint, sessionID: sessionID) ?? .rejected(reason: "Host-key validation unavailable.")
            }
        )

        do {
            let sshSession = try await sshClient.connect(request, handlers: handlers)
            activeSessions[sessionID] = sshSession

            for try await event in sshSession.events {
                handle(event, sessionID: sessionID)
            }
        } catch SSHConnectionError.passwordCancelled {
            discardSession(
                sessionID,
                banner: nil
            )
        } catch SSHConnectionError.authenticationFailed {
            discardSession(
                sessionID,
                banner: "Authentication failed for \(request.profile.alias)."
            )
        } catch SSHConnectionError.hostKeyRejected(let reason) {
            discardSession(
                sessionID,
                banner: reason
            )
        } catch {
            discardSession(
                sessionID,
                banner: "Connection failed for \(request.profile.alias): \(error.localizedDescription)"
            )
        }

        activeSessions.removeValue(forKey: sessionID)
        sessionTasks.removeValue(forKey: sessionID)
    }

    private func requestPassword(for profile: HostProfile, sessionID: UUID) async throws -> SSHPasswordCredential {
        try await withCheckedThrowingContinuation { continuation in
            passwordContinuations[sessionID] = continuation
            passwordPrompt = PasswordPromptRequest(
                sessionID: sessionID,
                hostAlias: profile.alias,
                username: profile.username,
                hostname: profile.hostname,
                port: profile.port
            )
            updateSessionState(sessionID, state: .authenticating)
        }
    }

    private func validateHostKey(_ fingerprint: HostKeyFingerprint, sessionID: UUID) async -> SSHHostKeyValidation {
        updateSessionState(sessionID, state: .verifyingHostKey)

        switch hostKeyTrustStore.decision(for: fingerprint) {
        case .trusted:
            return .trusted
        case .changedHostKey:
            return .rejected(reason: "Changed host key blocked for \(fingerprint.hostIdentity).")
        case .firstUseRequiresApproval:
            let trusted = await withCheckedContinuation { continuation in
                hostKeyContinuations[sessionID] = continuation
                hostKeyPrompt = HostKeyPromptRequest(sessionID: sessionID, fingerprint: fingerprint)
            }
            return trusted ? .trusted : .rejected(reason: "Host key was not trusted for \(fingerprint.hostIdentity).")
        }
    }

    private func handle(_ event: SSHEvent, sessionID: UUID) {
        switch event {
        case .stateChanged(let state):
            updateSessionState(sessionID, state: state)
        case .terminalOutput(let data):
            pendingTerminalOutput[sessionID, default: []].append(data)
            terminalOutputCounters[sessionID, default: 0] += 1
        case .hostKeyChallenge, .keyboardInteractivePrompt:
            break
        }
    }

    private func updateSessionState(_ sessionID: UUID, state: ConnectionState) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        sessions[index].state = state
        sessions[index].lastEventAt = Date()
    }

    private func discardSession(_ sessionID: UUID, banner: String?) {
        if let banner {
            hostLibraryBanner = HostLibraryBanner(message: banner)
        }

        passwordPrompt = passwordPrompt?.sessionID == sessionID ? nil : passwordPrompt
        hostKeyPrompt = hostKeyPrompt?.sessionID == sessionID ? nil : hostKeyPrompt
        pendingTerminalOutput.removeValue(forKey: sessionID)
        terminalOutputCounters.removeValue(forKey: sessionID)
        sessions.removeAll { $0.id == sessionID }
        selectedSessionID = sessions.last?.id
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        case .system:
            nil
        }
    }
}

struct HostLibraryBanner: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

struct PasswordPromptRequest: Identifiable, Equatable {
    var id: UUID { sessionID }
    var sessionID: UUID
    var hostAlias: String
    var username: String
    var hostname: String
    var port: UInt16

    var connectionLabel: String {
        "\(username)@\(hostname):\(port)"
    }
}

struct HostKeyPromptRequest: Identifiable, Equatable {
    var id: UUID { sessionID }
    var sessionID: UUID
    var fingerprint: HostKeyFingerprint
}

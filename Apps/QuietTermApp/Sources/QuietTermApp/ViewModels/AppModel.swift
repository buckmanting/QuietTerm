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

    init(
        profiles: [HostProfile] = [],
        sessions: [TerminalSession] = [],
        selectedSessionID: UUID? = nil,
        appearance: AppearancePreference = .dark,
        syncStatus: String = "Local mode"
    ) {
        self.profiles = profiles
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.appearance = appearance
        self.syncStatus = syncStatus
    }

    static func bootstrap() -> AppModel {
        let sampleProfile = HostProfile(
            alias: "Example host",
            hostname: "example.com",
            username: "deploy",
            authMethod: .keyboardInteractive,
            tags: ["beta"],
            folderName: "Servers"
        )

        return AppModel(profiles: [sampleProfile])
    }

    var selectedSession: TerminalSession? {
        guard let selectedSessionID else {
            return sessions.first
        }

        return sessions.first { $0.id == selectedSessionID }
    }

    func openSession(for profile: HostProfile) {
        let session = TerminalSession(
            profileID: profile.id,
            title: profile.alias,
            state: .disconnected(reason: "SSH adapter not wired yet")
        )
        sessions.append(session)
        selectedSessionID = session.id
    }

    func closeSession(_ session: TerminalSession) {
        sessions.removeAll { $0.id == session.id }
        selectedSessionID = sessions.last?.id
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

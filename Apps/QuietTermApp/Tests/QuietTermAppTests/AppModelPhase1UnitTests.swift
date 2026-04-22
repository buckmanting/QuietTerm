import QuietTermCore
import SwiftUI
@testable import QuietTerm
import XCTest

@MainActor
final class AppModelPhase1UnitTests: XCTestCase {
    func testAOpenSessionStartsInAuthenticatingState() {
        let profile = makeProfile()
        let model = AppModel(
            profiles: [profile],
            sshClient: SleepingSSHClient()
        )

        model.openSession(for: profile)

        XCTAssertEqual(model.sessions.count, 1)
        let session = model.sessions[0]
        XCTAssertEqual(session.profileID, profile.id)
        XCTAssertEqual(session.state, .authenticating)
        XCTAssertEqual(model.selectedSessionID, session.id)

        closeAllSessions(in: model)
    }

    func testBRetryFromFailedStateReturnsSessionToAuthenticating() {
        let profile = makeProfile()
        let failedSession = TerminalSession(
            profileID: profile.id,
            title: profile.alias,
            state: .failed(code: "AUTH_FAILED", message: "Authentication failed.")
        )
        let model = AppModel(
            profiles: [profile],
            sessions: [failedSession],
            selectedSessionID: failedSession.id,
            sshClient: SleepingSSHClient()
        )

        model.retrySession(failedSession.id)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].id, failedSession.id)
        XCTAssertEqual(model.sessions[0].state, .authenticating)
        XCTAssertEqual(model.selectedSessionID, failedSession.id)

        closeAllSessions(in: model)
    }

    func testCRetryFromDisconnectedStateKeepsSameTabIdentity() {
        let profile = makeProfile()
        let disconnectedSession = TerminalSession(
            profileID: profile.id,
            title: profile.alias,
            state: .disconnected(reason: "Network dropped.")
        )
        let model = AppModel(
            profiles: [profile],
            sessions: [disconnectedSession],
            selectedSessionID: disconnectedSession.id,
            sshClient: SleepingSSHClient()
        )

        model.retrySession(disconnectedSession.id)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].id, disconnectedSession.id)
        XCTAssertEqual(model.sessions[0].state, .authenticating)
        XCTAssertEqual(model.selectedSessionID, disconnectedSession.id)

        closeAllSessions(in: model)
    }

    func testDClosingOneTabDoesNotChangeOtherTabState() {
        let profile = makeProfile()
        let disconnected = TerminalSession(
            profileID: profile.id,
            title: "Disconnected",
            state: .disconnected(reason: "Network dropped.")
        )
        let connected = TerminalSession(
            profileID: profile.id,
            title: "Connected",
            state: .connected
        )
        let model = AppModel(
            profiles: [profile],
            sessions: [disconnected, connected],
            selectedSessionID: connected.id,
            sshClient: SleepingSSHClient()
        )

        model.closeSession(disconnected)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].id, connected.id)
        XCTAssertEqual(model.sessions[0].state, .connected)
        XCTAssertEqual(model.selectedSessionID, connected.id)
    }

    func testEClosingSelectedTabFallsBackToLastTab() {
        let profile = makeProfile()
        let first = TerminalSession(profileID: profile.id, title: "First", state: .connected)
        let selected = TerminalSession(profileID: profile.id, title: "Selected", state: .connected)
        let last = TerminalSession(profileID: profile.id, title: "Last", state: .connected)

        let model = AppModel(
            profiles: [profile],
            sessions: [first, selected, last],
            selectedSessionID: selected.id,
            sshClient: SleepingSSHClient()
        )

        model.closeSession(selected)

        XCTAssertEqual(model.sessions.map(\.id), [first.id, last.id])
        XCTAssertEqual(model.selectedSessionID, last.id)
        XCTAssertEqual(model.selectedSession?.id, last.id)
    }

    func testFResumeMarksConnectedSessionDisconnectedWhenNoTransportExists() {
        let profile = makeProfile()
        let connectedSession = TerminalSession(
            profileID: profile.id,
            title: profile.alias,
            state: .connected
        )
        let model = AppModel(
            profiles: [profile],
            sessions: [connectedSession],
            selectedSessionID: connectedSession.id,
            sshClient: SleepingSSHClient()
        )

        model.handleScenePhaseChange(.active)

        guard case .disconnected(let reason) = model.sessions[0].state else {
            XCTFail("Expected connected session to become disconnected after resume reconciliation.")
            return
        }
        XCTAssertEqual(reason, "Session disconnected while the app was in the background.")
    }

    private func makeProfile() -> HostProfile {
        HostProfile(
            alias: "Unit Test Host",
            hostname: "unit.test.local",
            username: "quiet",
            authMethod: .password(savedSecretID: nil)
        )
    }

    private func closeAllSessions(in model: AppModel) {
        let activeSessions = model.sessions
        for session in activeSessions {
            model.closeSession(session)
        }
    }
}

private struct SleepingSSHClient: SSHClient {
    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession {
        let oneHour: UInt64 = 3_600_000_000_000
        try await Task.sleep(nanoseconds: oneHour)
        throw SSHConnectionError.connectionFailed("Unexpected wake for test client.")
    }
}

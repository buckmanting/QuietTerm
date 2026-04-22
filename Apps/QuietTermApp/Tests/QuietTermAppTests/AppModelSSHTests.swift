import Foundation
import QuietTermCore
import SwiftUI
@testable import QuietTerm
import XCTest

@MainActor
final class AppModelSSHTests: XCTestCase {
    func testPasswordPromptTrustsHostKeyConnectsAndSendsInput() async throws {
        let profile = makeProfile()
        let presentedFingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "presented"
        )
        let passwordByteCount = LockedBox<Int?>(nil)
        let mockSession = MockSSHSession()
        let client = MockSSHClient { request, handlers in
            XCTAssertEqual(request.profile.id, profile.id)

            let hostKeyDecision = try await handlers.validateHostKey(presentedFingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            var credential = try await handlers.requestPassword(request.profile)
            passwordByteCount.set(credential.byteCount)
            credential.discard()

            mockSession.yield(.stateChanged(.connected))
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let passwordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("secret", for: passwordPrompt)

        try await eventuallyTrue { model.sessions.first?.state == .connected }
        XCTAssertEqual(passwordByteCount.value(), 6)

        let sessionID = try XCTUnwrap(model.sessions.first?.id)
        model.sendTerminalInput(Data([0x03]), to: sessionID)

        try await eventuallyTrue {
            mockSession.sentData().contains(Data([0x03]))
        }
    }

    func testChangedHostKeyHardBlocksWithoutReplacementPrompt() async throws {
        let profile = makeProfile()
        let trustedFingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "trusted"
        )
        let presentedFingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "changed"
        )
        let client = MockSSHClient { _, handlers in
            let decision = try await handlers.validateHostKey(presentedFingerprint)
            switch decision {
            case .trusted:
                XCTFail("Changed host keys must not be trusted.")
                return MockSSHSession()
            case .rejected(let reason):
                throw SSHConnectionError.hostKeyRejected(reason)
            }
        }

        let model = AppModel(
            profiles: [profile],
            sshClient: client,
            hostKeyTrustStore: InMemoryHostKeyTrustStore(trustedFingerprints: [trustedFingerprint])
        )

        model.openSession(for: profile)

        try await eventuallyTrue {
            guard let state = model.sessions.first?.state else {
                return false
            }
            if case .failed = state {
                return true
            }
            return false
        }

        let sessionState = try XCTUnwrap(model.sessions.first?.state)
        guard case .failed(let code, let message) = sessionState else {
            XCTFail("Expected a failed session state.")
            return
        }
        XCTAssertEqual(code, "HOST_KEY_REJECTED")
        XCTAssertTrue(message.contains("Changed host key blocked"))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertNil(model.hostKeyPrompt)
        XCTAssertNil(model.passwordPrompt)
    }

    func testCancellingPasswordPromptKeepsFailedSessionForRetry() async throws {
        let profile = makeProfile()
        let client = MockSSHClient { request, handlers in
            _ = try await handlers.requestPassword(request.profile)
            XCTFail("Password cancellation should throw before connect returns.")
            return MockSSHSession()
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let passwordPrompt = try await eventually { model.passwordPrompt }
        model.cancelPasswordPrompt(for: passwordPrompt)

        try await eventuallyTrue {
            guard let state = model.sessions.first?.state else {
                return false
            }
            if case .failed = state {
                return true
            }
            return false
        }

        let sessionState = try XCTUnwrap(model.sessions.first?.state)
        guard case .failed(let code, let message) = sessionState else {
            XCTFail("Expected a failed session state.")
            return
        }
        XCTAssertEqual(code, "AUTH_CANCELLED")
        XCTAssertEqual(message, "Authentication cancelled.")
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertNil(model.passwordPrompt)
        XCTAssertNil(model.hostLibraryBanner)
    }

    func testRetryReconnectsUsingSameSessionTab() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let connectAttempts = LockedBox<Int>(0)
        let client = MockSSHClient { request, handlers in
            let attempt = connectAttempts.value() + 1
            connectAttempts.set(attempt)

            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            let mockSession = MockSSHSession()
            if attempt == 1 {
                mockSession.yield(.stateChanged(.connected))
                mockSession.yield(.terminalOutput(Data("first-attempt".utf8)))
                mockSession.yield(.stateChanged(.disconnected(reason: "Network dropped.")))
                mockSession.finish()
            } else {
                mockSession.yield(.stateChanged(.connected))
                mockSession.yield(.terminalOutput(Data("second-attempt".utf8)))
            }
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let firstPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("first-password", for: firstPasswordPrompt)

        try await eventuallyTrue {
            guard let state = model.sessions.first?.state else {
                return false
            }
            if case .disconnected = state {
                return true
            }
            return false
        }

        let disconnectedState = try XCTUnwrap(model.sessions.first?.state)
        guard case .disconnected(let reason) = disconnectedState else {
            XCTFail("Expected first attempt to end in disconnected state.")
            return
        }
        XCTAssertEqual(reason, "Network dropped.")

        let originalSessionID = try XCTUnwrap(model.sessions.first?.id)
        let outputCountBeforeRetry = model.terminalOutputCounters[originalSessionID] ?? 0

        model.retrySession(originalSessionID)

        XCTAssertNil(model.hostKeyPrompt)

        let secondPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("second-password", for: secondPasswordPrompt)

        try await eventuallyTrue { model.sessions.first?.state == .connected }
        let sessionIDAfterRetry = try XCTUnwrap(model.sessions.first?.id)
        XCTAssertEqual(sessionIDAfterRetry, originalSessionID)
        XCTAssertEqual(model.sessions.count, 1)

        let outputCountAfterRetry = model.terminalOutputCounters[originalSessionID] ?? 0
        XCTAssertGreaterThan(outputCountAfterRetry, outputCountBeforeRetry)
        XCTAssertEqual(connectAttempts.value(), 2)
    }

    func testOpenNewSessionFromDisconnectedKeepsOriginalSession() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let connectAttempts = LockedBox<Int>(0)

        let client = MockSSHClient { request, handlers in
            let attempt = connectAttempts.value() + 1
            connectAttempts.set(attempt)

            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            let mockSession = MockSSHSession()
            if attempt == 1 {
                mockSession.yield(.stateChanged(.connected))
                mockSession.yield(.terminalOutput(Data("first-attempt".utf8)))
                mockSession.yield(.stateChanged(.disconnected(reason: "Network dropped.")))
                mockSession.finish()
            } else {
                mockSession.yield(.stateChanged(.connected))
                mockSession.yield(.terminalOutput(Data("second-attempt".utf8)))
            }
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let firstPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("first-password", for: firstPasswordPrompt)

        try await eventuallyTrue {
            guard let state = model.sessions.first?.state else {
                return false
            }
            if case .disconnected = state {
                return true
            }
            return false
        }

        let originalSessionID = try XCTUnwrap(model.sessions.first?.id)
        let originalOutputCounter = model.terminalOutputCounters[originalSessionID] ?? 0

        model.openNewSession(matching: originalSessionID)

        XCTAssertEqual(model.sessions.count, 2)
        let secondSession = try XCTUnwrap(model.sessions.last)
        XCTAssertNotEqual(secondSession.id, originalSessionID)
        XCTAssertEqual(model.selectedSessionID, secondSession.id)

        guard let originalSession = model.sessions.first(where: { $0.id == originalSessionID }) else {
            XCTFail("Original session should still exist.")
            return
        }
        guard case .disconnected(let reason) = originalSession.state else {
            XCTFail("Original session should remain disconnected.")
            return
        }
        XCTAssertEqual(reason, "Network dropped.")
        XCTAssertEqual(model.terminalOutputCounters[originalSessionID], originalOutputCounter)

        let secondPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("second-password", for: secondPasswordPrompt)

        try await eventuallyTrue {
            guard let latestSession = model.sessions.first(where: { $0.id == secondSession.id }) else {
                return false
            }
            return latestSession.state == .connected
        }
    }

    func testDisconnectingOneTabDoesNotAffectOtherConnectedTabAndCloseIsolated() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let connectAttempts = LockedBox<Int>(0)
        let firstSessionBox = LockedBox<MockSSHSession?>(nil)

        let client = MockSSHClient { request, handlers in
            let attempt = connectAttempts.value() + 1
            connectAttempts.set(attempt)

            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            let mockSession = MockSSHSession()
            mockSession.yield(.stateChanged(.connected))
            if attempt == 1 {
                firstSessionBox.set(mockSession)
            }
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let firstPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("first-password", for: firstPasswordPrompt)

        try await eventuallyTrue { model.sessions.count == 1 && model.sessions.first?.state == .connected }
        let firstSessionID = try XCTUnwrap(model.sessions.first?.id)

        model.openNewSession(matching: firstSessionID)
        try await eventuallyTrue { model.sessions.count == 2 }
        let secondSessionID = try await eventually {
            model.sessions.first(where: { $0.id != firstSessionID })?.id
        }

        let secondPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("second-password", for: secondPasswordPrompt)

        try await eventuallyTrue {
            model.sessions.first(where: { $0.id == secondSessionID })?.state == .connected
        }

        let firstSession = try await eventually { firstSessionBox.value() }
        firstSession.yield(.stateChanged(.disconnected(reason: "Network dropped.")))

        try await eventuallyTrue {
            guard let firstState = model.sessions.first(where: { $0.id == firstSessionID })?.state else {
                return false
            }

            guard case .disconnected(let reason) = firstState, reason == "Network dropped." else {
                return false
            }

            return model.sessions.first(where: { $0.id == secondSessionID })?.state == .connected
        }

        XCTAssertEqual(model.selectedSessionID, secondSessionID)

        let disconnectedTab = try XCTUnwrap(model.sessions.first(where: { $0.id == firstSessionID }))
        model.closeSession(disconnectedTab)

        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions.first?.id, secondSessionID)
        XCTAssertEqual(model.sessions.first?.state, .connected)
        XCTAssertEqual(model.selectedSessionID, secondSessionID)
    }

    func testInputAndOutputRemainIsolatedAcrossConcurrentTabs() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let connectAttempts = LockedBox<Int>(0)
        let firstSessionBox = LockedBox<MockSSHSession?>(nil)
        let secondSessionBox = LockedBox<MockSSHSession?>(nil)

        let client = MockSSHClient { request, handlers in
            let attempt = connectAttempts.value() + 1
            connectAttempts.set(attempt)

            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            let mockSession = MockSSHSession()
            mockSession.yield(.stateChanged(.connected))
            if attempt == 1 {
                firstSessionBox.set(mockSession)
            } else {
                secondSessionBox.set(mockSession)
            }
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let firstPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("first-password", for: firstPasswordPrompt)

        try await eventuallyTrue { model.sessions.count == 1 && model.sessions.first?.state == .connected }
        let firstSessionID = try XCTUnwrap(model.sessions.first?.id)

        model.openNewSession(matching: firstSessionID)
        try await eventuallyTrue { model.sessions.count == 2 }
        let secondSessionID = try await eventually {
            model.sessions.first(where: { $0.id != firstSessionID })?.id
        }

        let secondPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("second-password", for: secondPasswordPrompt)

        try await eventuallyTrue {
            model.sessions.first(where: { $0.id == secondSessionID })?.state == .connected
        }

        let firstSession = try await eventually { firstSessionBox.value() }
        let secondSession = try await eventually { secondSessionBox.value() }

        let firstInput = Data("ls\n".utf8)
        let secondInput = Data("pwd\n".utf8)
        model.sendTerminalInput(firstInput, to: firstSessionID)
        model.sendTerminalInput(secondInput, to: secondSessionID)

        try await eventuallyTrue {
            firstSession.sentData().contains(firstInput) &&
            !firstSession.sentData().contains(secondInput) &&
            secondSession.sentData().contains(secondInput) &&
            !secondSession.sentData().contains(firstInput)
        }

        let firstOutput = Data("first-output".utf8)
        let secondOutput = Data("second-output".utf8)
        firstSession.yield(.terminalOutput(firstOutput))
        secondSession.yield(.terminalOutput(secondOutput))

        try await eventuallyTrue {
            (model.terminalOutputCounters[firstSessionID] ?? 0) > 0 &&
            (model.terminalOutputCounters[secondSessionID] ?? 0) > 0
        }

        XCTAssertEqual(model.drainTerminalOutput(for: firstSessionID), [firstOutput])
        XCTAssertEqual(model.drainTerminalOutput(for: secondSessionID), [secondOutput])
        XCTAssertTrue(model.drainTerminalOutput(for: firstSessionID).isEmpty)
        XCTAssertTrue(model.drainTerminalOutput(for: secondSessionID).isEmpty)
    }

    func testClosingUnselectedTabPreservesSelectedTab() {
        let profile = makeProfile()
        let first = TerminalSession(profileID: profile.id, title: "First", state: .connected)
        let selected = TerminalSession(profileID: profile.id, title: "Selected", state: .connected)
        let last = TerminalSession(profileID: profile.id, title: "Last", state: .connected)

        let model = AppModel(
            profiles: [profile],
            sessions: [first, selected, last],
            selectedSessionID: selected.id
        )

        model.closeSession(first)

        XCTAssertEqual(model.sessions.map(\.id), [selected.id, last.id])
        XCTAssertEqual(model.selectedSessionID, selected.id)
        XCTAssertEqual(model.selectedSession?.id, selected.id)
    }

    func testResumeMarksConnectedSessionDisconnectedWhenTransportMissing() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let client = MockSSHClient { request, handlers in
            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            let mockSession = MockSSHSession()
            mockSession.yield(.stateChanged(.connected))
            mockSession.finish()
            return mockSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let passwordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("password", for: passwordPrompt)

        try await eventuallyTrue { model.sessions.first?.state == .connected }

        model.handleScenePhaseChange(.active)

        try await eventuallyTrue {
            guard let state = model.sessions.first?.state else {
                return false
            }
            if case .disconnected = state {
                return true
            }
            return false
        }

        guard case .disconnected(let reason) = model.sessions.first?.state else {
            XCTFail("Expected disconnected state after resume reconciliation.")
            return
        }
        XCTAssertEqual(reason, "Session disconnected while the app was in the background.")
    }

    func testResumeKeepsConnectedSessionWhenTransportStillActive() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let liveSession = MockSSHSession()
        let client = MockSSHClient { request, handlers in
            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            _ = try await handlers.requestPassword(request.profile)

            liveSession.yield(.stateChanged(.connected))
            return liveSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        let passwordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("password", for: passwordPrompt)

        try await eventuallyTrue { model.sessions.first?.state == .connected }

        model.handleScenePhaseChange(.active)

        XCTAssertEqual(model.sessions.first?.state, .connected)

        if let session = model.sessions.first {
            model.closeSession(session)
        }
    }

    func testRetryIgnoresStalePasswordCancellationFromPreviousAttempt() async throws {
        let profile = makeProfile()
        let fingerprint = HostKeyFingerprint(
            hostname: profile.hostname,
            port: profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "persisted"
        )
        let attempts = LockedBox<Int>(0)
        let staleAttemptGate = AsyncGate()
        let secondSessionBox = LockedBox<MockSSHSession?>(nil)

        let client = MockSSHClient { request, handlers in
            let attempt = attempts.value() + 1
            attempts.set(attempt)

            let hostKeyDecision = try await handlers.validateHostKey(fingerprint)
            guard hostKeyDecision == .trusted else {
                throw SSHConnectionError.hostKeyRejected("Host key was rejected.")
            }

            if attempt == 1 {
                do {
                    _ = try await handlers.requestPassword(request.profile)
                    XCTFail("First attempt should be cancelled by retry.")
                    return MockSSHSession()
                } catch is CancellationError {
                    // Retry cancels the first task; remap to passwordCancelled so this stale
                    // attempt exercises runSession's failure-catching path.
                    await staleAttemptGate.wait()
                    throw SSHConnectionError.passwordCancelled
                } catch {
                    // Hold the stale attempt until the retry attempt is fully connected.
                    await staleAttemptGate.wait()
                    throw error
                }
            }

            _ = try await handlers.requestPassword(request.profile)
            let secondSession = MockSSHSession()
            secondSessionBox.set(secondSession)
            return secondSession
        }

        let model = AppModel(profiles: [profile], sshClient: client)
        model.openSession(for: profile)

        let hostKeyPrompt = try await eventually { model.hostKeyPrompt }
        model.trustHostKey(for: hostKeyPrompt)

        _ = try await eventually { model.passwordPrompt }
        let sessionID = try XCTUnwrap(model.sessions.first?.id)

        // Force retry eligibility while the first attempt is still waiting on password.
        model.sessions[0].state = .failed(code: "TEST_FORCE_RETRY", message: "Force retry while first prompt is pending.")
        model.retrySession(sessionID)

        let secondPasswordPrompt = try await eventually { model.passwordPrompt }
        model.submitPassword("second-password", for: secondPasswordPrompt)

        let secondSession = try await eventually { secondSessionBox.value() }
        secondSession.yield(.stateChanged(.connected))

        try await eventuallyTrue { model.sessions.first?.state == .connected }

        // Release the stale first attempt after retry has connected; it will throw password-cancelled.
        await staleAttemptGate.open()

        // The stale error must not clobber the current attempt's connected state.
        try await eventuallyTrue { model.sessions.first?.state == .connected }
    }

    private func makeProfile() -> HostProfile {
        HostProfile(
            alias: "Unit Test Host",
            hostname: "unit.test.local",
            username: "quiet",
            authMethod: .password(savedSecretID: nil)
        )
    }
}

private final class MockSSHClient: SSHClient, @unchecked Sendable {
    private let connectHandler: @Sendable (SSHConnectionRequest, SSHConnectionHandlers) async throws -> any SSHSession

    init(connectHandler: @escaping @Sendable (SSHConnectionRequest, SSHConnectionHandlers) async throws -> any SSHSession) {
        self.connectHandler = connectHandler
    }

    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession {
        try await connectHandler(request, handlers)
    }
}

private final class MockSSHSession: SSHSession, @unchecked Sendable {
    let events: AsyncThrowingStream<SSHEvent, Error>

    private let continuation: AsyncThrowingStream<SSHEvent, Error>.Continuation
    private let lock = NSLock()
    private var sentInput: [Data] = []

    init() {
        var streamContinuation: AsyncThrowingStream<SSHEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation
    }

    func send(_ data: Data) async throws {
        lock.withLock {
            sentInput.append(data)
        }
    }

    func close() async {
        continuation.finish()
    }

    func yield(_ event: SSHEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }

    func sentData() -> [Data] {
        lock.withLock {
            sentInput
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }

    func value() -> Value {
        lock.withLock {
            storedValue
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func open() {
        guard !isOpen else {
            return
        }

        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

private enum EventuallyError: Error {
    case timedOut
}

@MainActor
private func eventually<Value>(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: @MainActor () -> Value?
) async throws -> Value {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if let value = body() {
            return value
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for condition.", file: file, line: line)
    throw EventuallyError.timedOut
}

@MainActor
private func eventuallyTrue(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: @MainActor () -> Bool
) async throws {
    _ = try await eventually(timeout: timeout, file: file, line: line) {
        body() ? true : nil
    }
}

import Foundation
import QuietTermCore
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

        let banner = try await eventually { model.hostLibraryBanner }
        XCTAssertTrue(banner.message.contains("Changed host key blocked"))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.hostKeyPrompt)
        XCTAssertNil(model.passwordPrompt)
    }

    func testCancellingPasswordPromptDiscardsAttemptedSession() async throws {
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

        try await eventuallyTrue { model.sessions.isEmpty }
        XCTAssertNil(model.passwordPrompt)
        XCTAssertNil(model.hostLibraryBanner)
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

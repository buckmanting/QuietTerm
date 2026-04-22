#if DEBUG
import Foundation
import QuietTermCore

struct UITestSSHClient: SSHClient {
    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession {
        let fingerprint = HostKeyFingerprint(
            hostname: request.profile.hostname,
            port: request.profile.port,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "quiettermUITestHostKey"
        )

        switch try await handlers.validateHostKey(fingerprint) {
        case .trusted:
            break
        case .rejected(let reason):
            throw SSHConnectionError.hostKeyRejected(reason)
        }

        var credential = try await handlers.requestPassword(request.profile)
        defer {
            credential.discard()
        }

        guard !credential.isEmpty else {
            throw SSHConnectionError.authenticationFailed
        }

        let session = UITestSSHSession()
        session.start()
        return session
    }
}

private actor UITestSSHSession: SSHSession {
    nonisolated let events: AsyncThrowingStream<SSHEvent, Error>

    private let continuation: AsyncThrowingStream<SSHEvent, Error>.Continuation
    private var isClosed = false

    init() {
        var streamContinuation: AsyncThrowingStream<SSHEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation
    }

    nonisolated func start() {
        Task {
            await emitStartup()
        }
    }

    func send(_ data: Data) async throws {
        guard !isClosed else {
            throw SSHConnectionError.sessionClosed("UI test session is closed.")
        }

        continuation.yield(.terminalOutput(data))
    }

    func close() async {
        guard !isClosed else {
            return
        }

        isClosed = true
        continuation.yield(.stateChanged(.disconnected(reason: "Closed.")))
        continuation.finish()
    }

    private func emitStartup() async {
        continuation.yield(.stateChanged(.connected))
        continuation.yield(.terminalOutput(Data("quietterm-ui-test\r\n".utf8)))
    }
}
#endif

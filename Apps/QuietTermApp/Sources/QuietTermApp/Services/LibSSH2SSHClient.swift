#if canImport(CQuietTermLibSSH2)
import CQuietTermLibSSH2
import Darwin
import Foundation
import QuietTermCore

final class LibSSH2SSHClient: SSHClient {
    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession {
        guard case .password(let savedSecretID) = request.profile.authMethod else {
            throw SSHConnectionError.unsupportedAuthMethod(request.profile.authMethod.displayName)
        }

        guard savedSecretID == nil else {
            throw SSHConnectionError.unsupportedAuthMethod("Saved passwords are outside KAN-16.")
        }

        guard LibSSH2Runtime.initResult == 0 else {
            throw SSHConnectionError.connectionFailed("libssh2 initialization failed with code \(LibSSH2Runtime.initResult).")
        }

        let connection = try await Task.detached {
            try LibSSH2ConnectionBox.connect(hostname: request.profile.hostname, port: request.profile.port)
        }.value

        do {
            let fingerprint = try connection.hostKeyFingerprint(
                hostname: request.profile.hostname,
                port: request.profile.port
            )

            switch try await handlers.validateHostKey(fingerprint) {
            case .trusted:
                break
            case .rejected(let reason):
                connection.close()
                throw SSHConnectionError.hostKeyRejected(reason)
            }

            var credential = try await handlers.requestPassword(request.profile)
            defer {
                credential.discard()
            }

            try connection.authenticatePassword(
                username: request.profile.username,
                credential: &credential
            )
            try connection.openShell(size: request.terminalSize)

            let session = LibSSH2Session(connection: connection)
            session.start()
            return session
        } catch {
            connection.close()
            throw error
        }
    }
}

private enum LibSSH2Runtime {
    static let initResult: Int32 = libssh2_init(0)
}

private enum LibSSH2NonblockingResult: Error {
    case wouldBlock
}

private final class LibSSH2ConnectionBox: @unchecked Sendable {
    private var socket: Int32
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var isClosed = false

    private init(socket: Int32, session: OpaquePointer) {
        self.socket = socket
        self.session = session
    }

    deinit {
        close()
    }

    static func connect(hostname: String, port: UInt16) throws -> LibSSH2ConnectionBox {
        let socket = try openSocket(hostname: hostname, port: port)

        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            Darwin.close(socket)
            throw SSHConnectionError.connectionFailed("Could not create libssh2 session.")
        }

        libssh2_session_set_blocking(session, 1)
        libssh2_session_set_timeout(session, 15_000)

        let box = LibSSH2ConnectionBox(socket: socket, session: session)
        let handshakeResult = libssh2_session_handshake(session, socket)
        guard handshakeResult == 0 else {
            let message = box.lastErrorMessage(prefix: "SSH handshake failed", fallbackCode: handshakeResult)
            box.close()
            throw SSHConnectionError.connectionFailed(message)
        }

        return box
    }

    func hostKeyFingerprint(hostname: String, port: UInt16) throws -> HostKeyFingerprint {
        guard let session else {
            throw SSHConnectionError.sessionClosed("Session closed before host-key validation.")
        }

        var hostKeyLength = 0
        var hostKeyType: Int32 = 0
        guard libssh2_session_hostkey(session, &hostKeyLength, &hostKeyType) != nil else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Could not read host key", fallbackCode: nil))
        }

        guard let hashPointer = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256) else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Could not hash host key", fallbackCode: nil))
        }

        let fingerprint = Data(bytes: hashPointer, count: 32)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        return HostKeyFingerprint(
            hostname: hostname,
            port: port,
            algorithm: Self.algorithmName(for: hostKeyType),
            sha256Fingerprint: fingerprint
        )
    }

    func authenticatePassword(username: String, credential: inout SSHPasswordCredential) throws {
        guard let session else {
            throw SSHConnectionError.sessionClosed("Session closed before authentication.")
        }

        let passwordByteCount = credential.byteCount
        let result = username.withCString { usernamePointer in
            credential.withNullTerminatedUTF8 { passwordPointer in
                libssh2_userauth_password_ex(
                    session,
                    usernamePointer,
                    UInt32(username.utf8.count),
                    passwordPointer,
                    UInt32(passwordByteCount),
                    nil
                )
            }
        }

        guard result == 0 else {
            if result == LIBSSH2_ERROR_AUTHENTICATION_FAILED {
                throw SSHConnectionError.authenticationFailed
            }

            throw SSHConnectionError.connectionFailed(
                lastErrorMessage(prefix: "Password authentication failed", fallbackCode: result)
            )
        }
    }

    func openShell(size: TerminalSize) throws {
        guard let session else {
            throw SSHConnectionError.sessionClosed("Session closed before shell startup.")
        }

        guard channel == nil else {
            return
        }

        guard let openedChannel = "session".withCString({
            libssh2_channel_open_ex(
                session,
                $0,
                UInt32("session".utf8.count),
                UInt32(2 * 1024 * 1024),
                UInt32(32_768),
                nil,
                0
            )
        }) else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Could not open SSH channel", fallbackCode: nil))
        }

        channel = openedChannel

        let ptyResult = "xterm-256color".withCString {
            libssh2_channel_request_pty_ex(
                openedChannel,
                $0,
                UInt32("xterm-256color".utf8.count),
                nil,
                0,
                Int32(size.columns),
                Int32(size.rows),
                0,
                0
            )
        }

        guard ptyResult == 0 else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "PTY allocation failed", fallbackCode: ptyResult))
        }

        let shellResult = "shell".withCString {
            libssh2_channel_process_startup(
                openedChannel,
                $0,
                UInt32("shell".utf8.count),
                nil,
                0
            )
        }

        guard shellResult == 0 else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Shell startup failed", fallbackCode: shellResult))
        }

        libssh2_session_set_blocking(session, 0)
    }

    func readAvailable() throws -> [Data] {
        guard let channel else {
            throw SSHConnectionError.sessionClosed("Channel is not open.")
        }

        var chunks: [Data] = []
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                libssh2_channel_read_ex(
                    channel,
                    0,
                    rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self),
                    rawBuffer.count
                )
            }

            if count > 0 {
                chunks.append(Data(buffer.prefix(Int(count))))
                continue
            }

            if count == Int(LIBSSH2_ERROR_EAGAIN) || count == 0 {
                return chunks
            }

            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Channel read failed", fallbackCode: Int32(count)))
        }
    }

    func write(_ data: Data, offset: Int) throws -> Int {
        guard let channel else {
            throw SSHConnectionError.sessionClosed("Channel is not open.")
        }

        guard offset < data.count else {
            return 0
        }

        let written = data.withUnsafeBytes { rawBuffer in
            libssh2_channel_write_ex(
                channel,
                0,
                rawBuffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: CChar.self),
                data.count - offset
            )
        }

        if written == Int(LIBSSH2_ERROR_EAGAIN) {
            throw LibSSH2NonblockingResult.wouldBlock
        }

        guard written >= 0 else {
            throw SSHConnectionError.connectionFailed(lastErrorMessage(prefix: "Channel write failed", fallbackCode: Int32(written)))
        }

        return Int(written)
    }

    func isEOF() -> Bool {
        guard let channel else {
            return true
        }

        return libssh2_channel_eof(channel) != 0
    }

    func close() {
        guard !isClosed else {
            return
        }

        isClosed = true

        if let channel {
            _ = libssh2_channel_close(channel)
            _ = libssh2_channel_free(channel)
            self.channel = nil
        }

        if let session {
            _ = libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "QuietTerm closing session.", "")
            _ = libssh2_session_free(session)
            self.session = nil
        }

        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
    }

    private func lastErrorMessage(prefix: String, fallbackCode: Int32?) -> String {
        guard let session else {
            return fallbackCode.map { "\(prefix) [\($0)]" } ?? prefix
        }

        var messagePointer: UnsafeMutablePointer<CChar>?
        var messageLength: Int32 = 0
        let code = libssh2_session_last_error(session, &messagePointer, &messageLength, 0)

        if let messagePointer {
            return "\(prefix): \(String(cString: messagePointer)) [\(code)]"
        }

        return fallbackCode.map { "\(prefix) [\($0)]" } ?? "\(prefix) [\(code)]"
    }

    private static func algorithmName(for hostKeyType: Int32) -> String {
        switch hostKeyType {
        case LIBSSH2_HOSTKEY_TYPE_RSA:
            "ssh-rsa"
        case LIBSSH2_HOSTKEY_TYPE_DSS:
            "ssh-dss"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256:
            "ecdsa-sha2-nistp256"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384:
            "ecdsa-sha2-nistp384"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521:
            "ecdsa-sha2-nistp521"
        case LIBSSH2_HOSTKEY_TYPE_ED25519:
            "ssh-ed25519"
        default:
            "unknown"
        }
    }

    private static func openSocket(hostname: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var results: UnsafeMutablePointer<addrinfo>?
        let lookupResult = getaddrinfo(hostname, String(port), &hints, &results)
        guard lookupResult == 0, let results else {
            let message = gai_strerror(lookupResult).map(String.init(cString:)) ?? "unknown lookup failure"
            throw SSHConnectionError.connectionFailed("Could not resolve \(hostname): \(message).")
        }
        defer {
            freeaddrinfo(results)
        }

        var current: UnsafeMutablePointer<addrinfo>? = results
        var lastError: Int32 = 0

        while let address = current {
            let socketDescriptor = Darwin.socket(
                address.pointee.ai_family,
                address.pointee.ai_socktype,
                address.pointee.ai_protocol
            )

            if socketDescriptor >= 0 {
                if Darwin.connect(socketDescriptor, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 {
                    return socketDescriptor
                }

                lastError = errno
                Darwin.close(socketDescriptor)
            } else {
                lastError = errno
            }

            current = address.pointee.ai_next
        }

        throw SSHConnectionError.connectionFailed("Could not connect to \(hostname):\(port) [\(lastError)].")
    }
}

private actor LibSSH2Session: SSHSession {
    nonisolated let events: AsyncThrowingStream<SSHEvent, Error>

    private let continuation: AsyncThrowingStream<SSHEvent, Error>.Continuation
    private let connection: LibSSH2ConnectionBox
    private var pendingWrites: [Data] = []
    private var isClosed = false

    init(connection: LibSSH2ConnectionBox) {
        self.connection = connection

        var streamContinuation: AsyncThrowingStream<SSHEvent, Error>.Continuation!
        self.events = AsyncThrowingStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation
    }

    nonisolated func start() {
        Task {
            await readLoop()
        }
    }

    func send(_ data: Data) async throws {
        guard !isClosed else {
            throw SSHConnectionError.sessionClosed("Cannot send input to a closed session.")
        }

        if !data.isEmpty {
            pendingWrites.append(data)
        }
    }

    func close() async {
        guard !isClosed else {
            return
        }

        isClosed = true
        connection.close()
        continuation.yield(.stateChanged(.disconnected(reason: "Closed.")))
        continuation.finish()
    }

    private func readLoop() async {
        continuation.yield(.stateChanged(.connected))

        while !isClosed {
            do {
                try flushPendingWrites()

                let chunks = try connection.readAvailable()
                for chunk in chunks where !chunk.isEmpty {
                    continuation.yield(.terminalOutput(chunk))
                }

                if connection.isEOF() {
                    await close()
                    return
                }

                if chunks.isEmpty {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            } catch LibSSH2NonblockingResult.wouldBlock {
                try? await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                isClosed = true
                connection.close()
                continuation.finish(throwing: error)
                return
            }
        }
    }

    private func flushPendingWrites() throws {
        guard !pendingWrites.isEmpty else {
            return
        }

        var remaining: [Data] = []

        for (index, data) in pendingWrites.enumerated() {
            var offset = 0
            while offset < data.count {
                do {
                    let written = try connection.write(data, offset: offset)
                    guard written > 0 else {
                        break
                    }
                    offset += written
                } catch LibSSH2NonblockingResult.wouldBlock {
                    remaining.append(Data(data.dropFirst(offset)))
                    remaining.append(contentsOf: pendingWrites.dropFirst(index + 1))
                    pendingWrites = remaining
                    throw LibSSH2NonblockingResult.wouldBlock
                }
            }
        }

        pendingWrites.removeAll(keepingCapacity: true)
    }
}
#endif

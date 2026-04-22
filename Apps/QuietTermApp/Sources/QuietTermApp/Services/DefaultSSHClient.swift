import Foundation
import QuietTermCore

enum DefaultSSHClient {
    static func make() -> any SSHClient {
        #if canImport(CQuietTermLibSSH2)
        LibSSH2SSHClient()
        #else
        UnavailableSSHClient()
        #endif
    }
}

struct UnavailableSSHClient: SSHClient {
    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession {
        throw SSHConnectionError.connectionFailed("libssh2 adapter is not linked in this build.")
    }
}

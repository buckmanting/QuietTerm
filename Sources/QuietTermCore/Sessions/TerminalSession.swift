import Foundation

public struct TerminalSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var profileID: UUID
    public var title: String
    public var state: ConnectionState
    public var createdAt: Date
    public var lastEventAt: Date

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        title: String,
        state: ConnectionState = .idle,
        createdAt: Date = Date(),
        lastEventAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.state = state
        self.createdAt = createdAt
        self.lastEventAt = lastEventAt
    }
}

public enum ConnectionState: Codable, Equatable, Sendable {
    case idle
    case verifyingHostKey
    case authenticating
    case connected
    case disconnected(reason: String?)
    case failed(code: String, message: String)

    public var isTerminalUsable: Bool {
        self == .connected
    }
}

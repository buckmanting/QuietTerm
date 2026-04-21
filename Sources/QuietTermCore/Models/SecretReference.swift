import Foundation

public struct SecretReference: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case privateKey
        case password
    }

    public var id: String
    public var kind: Kind
    public var displayName: String
    public var requiresUserPresence: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        displayName: String,
        requiresUserPresence: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.requiresUserPresence = requiresUserPresence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

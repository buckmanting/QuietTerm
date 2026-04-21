import Foundation

public enum AuthMethod: Codable, Equatable, Sendable {
    case password(savedSecretID: String?)
    case privateKey(secretID: String, requiresUserPresence: Bool)
    case keyboardInteractive

    public var displayName: String {
        switch self {
        case .password(let savedSecretID):
            savedSecretID == nil ? "Password" : "Saved password"
        case .privateKey:
            "Private key"
        case .keyboardInteractive:
            "Keyboard interactive"
        }
    }

    public var referencedSecretIDs: [String] {
        switch self {
        case .password(let savedSecretID):
            savedSecretID.map { [$0] } ?? []
        case .privateKey(let secretID, _):
            [secretID]
        case .keyboardInteractive:
            []
        }
    }
}

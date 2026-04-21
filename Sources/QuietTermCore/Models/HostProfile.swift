import Foundation

public struct HostProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var alias: String
    public var hostname: String
    public var port: UInt16
    public var username: String
    public var authMethod: AuthMethod
    public var tags: [String]
    public var folderName: String?
    public var appearance: AppearancePreference
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        alias: String,
        hostname: String,
        port: UInt16 = 22,
        username: String,
        authMethod: AuthMethod,
        tags: [String] = [],
        folderName: String? = nil,
        appearance: AppearancePreference = .dark,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.alias = alias
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.tags = tags
        self.folderName = folderName
        self.appearance = appearance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var connectionLabel: String {
        "\(username)@\(hostname):\(port)"
    }

    public func validated() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if alias.trimmedForValidation.isEmpty {
            issues.append(.init(field: "alias", message: "Alias is required."))
        }

        if hostname.trimmedForValidation.isEmpty {
            issues.append(.init(field: "hostname", message: "Hostname is required."))
        }

        if username.trimmedForValidation.isEmpty {
            issues.append(.init(field: "username", message: "Username is required."))
        }

        if port == 0 {
            issues.append(.init(field: "port", message: "Port must be between 1 and 65535."))
        }

        return issues
    }

    public func withoutSecretsForSync() -> SyncedHostProfile {
        SyncedHostProfile(
            id: id,
            alias: alias,
            hostname: hostname,
            port: port,
            username: username,
            authMethod: authMethod.syncRepresentation,
            tags: tags,
            folderName: folderName,
            appearance: appearance,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public struct SyncedHostProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var alias: String
    public var hostname: String
    public var port: UInt16
    public var username: String
    public var authMethod: SyncedAuthMethod
    public var tags: [String]
    public var folderName: String?
    public var appearance: AppearancePreference
    public var createdAt: Date
    public var updatedAt: Date
}

public enum SyncedAuthMethod: String, Codable, Equatable, Sendable {
    case password
    case savedPasswordAvailableLocally
    case privateKeyAvailableLocally
    case keyboardInteractive
}

public struct ValidationIssue: Codable, Equatable, Sendable {
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

private extension AuthMethod {
    var syncRepresentation: SyncedAuthMethod {
        switch self {
        case .password(let savedSecretID):
            savedSecretID == nil ? .password : .savedPasswordAvailableLocally
        case .privateKey:
            .privateKeyAvailableLocally
        case .keyboardInteractive:
            .keyboardInteractive
        }
    }
}

private extension String {
    var trimmedForValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

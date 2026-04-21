import Foundation

public struct HostKeyFingerprint: Codable, Equatable, Hashable, Sendable {
    public var hostname: String
    public var port: UInt16
    public var algorithm: String
    public var sha256Fingerprint: String

    public init(hostname: String, port: UInt16, algorithm: String, sha256Fingerprint: String) {
        self.hostname = hostname
        self.port = port
        self.algorithm = algorithm
        self.sha256Fingerprint = sha256Fingerprint
    }

    public var hostIdentity: String {
        "\(hostname):\(port)"
    }
}

public enum HostKeyTrustDecision: Equatable, Sendable {
    case trusted
    case firstUseRequiresApproval(HostKeyFingerprint)
    case changedHostKey(previous: HostKeyFingerprint, presented: HostKeyFingerprint)
}

public protocol HostKeyTrustStoring {
    func decision(for presented: HostKeyFingerprint) -> HostKeyTrustDecision
    mutating func trust(_ fingerprint: HostKeyFingerprint)
    mutating func replaceTrust(with fingerprint: HostKeyFingerprint)
}

public struct InMemoryHostKeyTrustStore: HostKeyTrustStoring, Sendable {
    private var trustedFingerprintsByHost: [String: HostKeyFingerprint]

    public init(trustedFingerprints: [HostKeyFingerprint] = []) {
        trustedFingerprintsByHost = Dictionary(
            uniqueKeysWithValues: trustedFingerprints.map { ($0.hostIdentity, $0) }
        )
    }

    public func decision(for presented: HostKeyFingerprint) -> HostKeyTrustDecision {
        guard let trusted = trustedFingerprintsByHost[presented.hostIdentity] else {
            return .firstUseRequiresApproval(presented)
        }

        if trusted == presented {
            return .trusted
        }

        return .changedHostKey(previous: trusted, presented: presented)
    }

    public mutating func trust(_ fingerprint: HostKeyFingerprint) {
        trustedFingerprintsByHost[fingerprint.hostIdentity] = fingerprint
    }

    public mutating func replaceTrust(with fingerprint: HostKeyFingerprint) {
        trust(fingerprint)
    }
}

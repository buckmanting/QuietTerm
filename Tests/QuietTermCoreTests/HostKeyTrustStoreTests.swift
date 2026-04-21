import Testing
@testable import QuietTermCore

@Test func unknownHostKeyRequiresExplicitFirstUseTrust() {
    let store = InMemoryHostKeyTrustStore()
    let fingerprint = HostKeyFingerprint(
        hostname: "example.com",
        port: 22,
        algorithm: "ssh-ed25519",
        sha256Fingerprint: "SHA256:first"
    )

    #expect(store.decision(for: fingerprint) == .firstUseRequiresApproval(fingerprint))
}

@Test func changedHostKeyIsBlockedByTrustDecision() {
    let original = HostKeyFingerprint(
        hostname: "example.com",
        port: 22,
        algorithm: "ssh-ed25519",
        sha256Fingerprint: "SHA256:first"
    )
    let changed = HostKeyFingerprint(
        hostname: "example.com",
        port: 22,
        algorithm: "ssh-ed25519",
        sha256Fingerprint: "SHA256:changed"
    )
    let store = InMemoryHostKeyTrustStore(trustedFingerprints: [original])

    #expect(store.decision(for: changed) == .changedHostKey(previous: original, presented: changed))
}

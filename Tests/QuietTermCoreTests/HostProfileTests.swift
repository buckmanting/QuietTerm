import Foundation
import Testing
@testable import QuietTermCore

@Test func hostProfileValidationRequiresCoreConnectionFields() {
    let profile = HostProfile(
        alias: " ",
        hostname: "",
        port: 0,
        username: "\n",
        authMethod: .password(savedSecretID: nil)
    )

    let issues = profile.validated()

    #expect(issues.map(\.field) == ["alias", "hostname", "username", "port"])
}

@Test func syncedProfileDoesNotExposeSecretIDs() {
    let profile = HostProfile(
        alias: "Prod",
        hostname: "prod.example.com",
        username: "deploy",
        authMethod: .privateKey(secretID: "local-key-id", requiresUserPresence: true)
    )

    let synced = profile.withoutSecretsForSync()

    #expect(synced.authMethod == .privateKeyAvailableLocally)
}

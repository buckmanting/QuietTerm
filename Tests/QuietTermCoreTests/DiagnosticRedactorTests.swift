import Testing
@testable import QuietTermCore

@Test func diagnosticRedactorRemovesPrivateKeyBlocksAndSecrets() {
    let input = """
    profile=prod
    password: hunter2
    passphrase=my-passphrase
    token = abc123
    -----BEGIN OPENSSH PRIVATE KEY-----
    secret-key-data
    -----END OPENSSH PRIVATE KEY-----
    """

    let output = DiagnosticRedactor().redact(input)

    #expect(!output.contains("hunter2"))
    #expect(!output.contains("my-passphrase"))
    #expect(!output.contains("abc123"))
    #expect(!output.contains("secret-key-data"))
    #expect(output.contains("[REDACTED PRIVATE KEY]"))
}

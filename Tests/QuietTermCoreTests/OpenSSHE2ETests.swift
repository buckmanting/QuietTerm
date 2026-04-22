import Foundation
import Testing

@Test func dockerPasswordSSHOverOpenSSH() throws {
    guard ProcessInfo.processInfo.environment["QUIETTERM_RUN_DOCKER_E2E"] == "1" else {
        return
    }

    let config = OpenSSHE2EConfig.docker
    let tempDirectory = try TemporaryDirectory()
    try assertPasswordCommandSucceeds(config: config, knownHostsPath: tempDirectory.url.appendingPathComponent("known_hosts").path)
    try assertChangedHostKeyIsBlocked(config: config, tempDirectory: tempDirectory.url)
}

@Test func realHostPasswordSSHOverOpenSSH() throws {
    guard ProcessInfo.processInfo.environment["QUIETTERM_REQUIRE_REAL_SSH"] == "1" else {
        return
    }

    let config = try OpenSSHE2EConfig.realHost()
    let tempDirectory = try TemporaryDirectory()

    let presentedFingerprint = try fetchSHA256HostKeyFingerprint(config: config)
    #expect(presentedFingerprint == config.expectedHostKeySHA256)

    try assertPasswordCommandSucceeds(config: config, knownHostsPath: tempDirectory.url.appendingPathComponent("known_hosts").path)
    try assertChangedHostKeyIsBlocked(config: config, tempDirectory: tempDirectory.url)
}

private struct OpenSSHE2EConfig {
    var host: String
    var port: UInt16
    var username: String
    var password: String
    var expectedHostKeySHA256: String?

    static var docker: OpenSSHE2EConfig {
        let environment = ProcessInfo.processInfo.environment
        return OpenSSHE2EConfig(
            host: environment["QUIETTERM_DOCKER_SSH_HOST"] ?? "127.0.0.1",
            port: UInt16(environment["QUIETTERM_DOCKER_SSH_PORT"] ?? "2222") ?? 2222,
            username: environment["QUIETTERM_DOCKER_SSH_USERNAME"] ?? "quiet",
            password: environment["QUIETTERM_DOCKER_SSH_PASSWORD"] ?? "quiet-password",
            expectedHostKeySHA256: nil
        )
    }

    static func realHost() throws -> OpenSSHE2EConfig {
        let environment = ProcessInfo.processInfo.environment
        let requiredKeys = [
            "QUIETTERM_SSH_HOST",
            "QUIETTERM_SSH_PORT",
            "QUIETTERM_SSH_USERNAME",
            "QUIETTERM_SSH_PASSWORD",
            "QUIETTERM_SSH_HOSTKEY_SHA256"
        ]

        let missingKeys = requiredKeys.filter { environment[$0]?.isEmpty ?? true }
        guard missingKeys.isEmpty else {
            throw E2EError.missingEnvironment(missingKeys)
        }

        guard let port = UInt16(environment["QUIETTERM_SSH_PORT"] ?? "") else {
            throw E2EError.invalidPort(environment["QUIETTERM_SSH_PORT"] ?? "")
        }

        return OpenSSHE2EConfig(
            host: environment["QUIETTERM_SSH_HOST"]!,
            port: port,
            username: environment["QUIETTERM_SSH_USERNAME"]!,
            password: environment["QUIETTERM_SSH_PASSWORD"]!,
            expectedHostKeySHA256: normalizedFingerprint(environment["QUIETTERM_SSH_HOSTKEY_SHA256"]!)
        )
    }
}

private struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quietterm-ssh-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private enum E2EError: Error, CustomStringConvertible {
    case missingEnvironment([String])
    case invalidPort(String)
    case commandTimedOut(String)
    case commandFailed(String, ProcessResult)
    case hostKeyScanFailed
    case hostKeyFingerprintNotFound(String)

    var description: String {
        switch self {
        case .missingEnvironment(let keys):
            "Missing required SSH E2E environment variables: \(keys.joined(separator: ", "))"
        case .invalidPort(let value):
            "Invalid SSH port: \(value)"
        case .commandTimedOut(let executable):
            "Command timed out: \(executable)"
        case .commandFailed(let executable, let result):
            "Command failed: \(executable) [\(result.status)]\nstdout: \(result.stdout)\nstderr: \(result.stderr)"
        case .hostKeyScanFailed:
            "ssh-keyscan did not return a host key."
        case .hostKeyFingerprintNotFound(let output):
            "Could not parse SHA256 host-key fingerprint from: \(output)"
        }
    }
}

private func assertPasswordCommandSucceeds(config: OpenSSHE2EConfig, knownHostsPath: String) throws {
    let script = """
    set timeout 20
    set target "$env(QUIETTERM_TEST_USERNAME)@$env(QUIETTERM_TEST_HOST)"
    spawn ssh -p $env(QUIETTERM_TEST_PORT) -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$env(QUIETTERM_TEST_KNOWN_HOSTS) -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -- $target "printf quietterm-e2e"
    expect {
      -re "(?i)password:" {
        send -- "$env(QUIETTERM_TEST_PASSWORD)\\r"
        exp_continue
      }
      eof
      timeout { exit 124 }
    }
    catch wait result
    exit [lindex $result 3]
    """

    let result = try runProcess(
        "/usr/bin/expect",
        arguments: ["-c", script],
        environment: processEnvironment(for: config, knownHostsPath: knownHostsPath),
        timeout: 30
    )

    guard result.status == 0, result.stdout.contains("quietterm-e2e") else {
        throw E2EError.commandFailed("expect ssh password command", result)
    }
}

private func assertChangedHostKeyIsBlocked(config: OpenSSHE2EConfig, tempDirectory: URL) throws {
    let keyPath = tempDirectory.appendingPathComponent("wrong_host_key").path
    let knownHostsPath = tempDirectory.appendingPathComponent("changed_known_hosts").path

    let keygenResult = try runProcess(
        "/usr/bin/ssh-keygen",
        arguments: ["-q", "-t", "ed25519", "-N", "", "-f", keyPath],
        timeout: 15
    )
    guard keygenResult.status == 0 else {
        throw E2EError.commandFailed("ssh-keygen", keygenResult)
    }

    let publicKey = try String(contentsOfFile: "\(keyPath).pub", encoding: .utf8)
    let publicKeyParts = publicKey.split(separator: " ")
    let knownHostName = config.port == 22 ? config.host : "[\(config.host)]:\(config.port)"
    let knownHostsLine = "\(knownHostName) \(publicKeyParts[0]) \(publicKeyParts[1])\n"
    try knownHostsLine.write(toFile: knownHostsPath, atomically: true, encoding: .utf8)

    let result = try runProcess(
        "/usr/bin/ssh",
        arguments: [
            "-p", String(config.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(knownHostsPath)",
            "--",
            "\(config.username)@\(config.host)",
            "true"
        ],
        timeout: 20
    )

    #expect(result.status != 0)
    let combinedOutput = result.stdout + result.stderr
    #expect(
        combinedOutput.contains("Host key verification failed")
            || combinedOutput.contains("REMOTE HOST IDENTIFICATION HAS CHANGED")
    )
}

private func fetchSHA256HostKeyFingerprint(config: OpenSSHE2EConfig) throws -> String {
    let keyscanResult = try runProcess(
        "/usr/bin/ssh-keyscan",
        arguments: ["-p", String(config.port), "-T", "10", config.host],
        timeout: 20
    )

    guard keyscanResult.status == 0, !keyscanResult.stdout.isEmpty else {
        throw E2EError.hostKeyScanFailed
    }

    let keygenResult = try runProcess(
        "/usr/bin/ssh-keygen",
        arguments: ["-lf", "-", "-E", "sha256"],
        standardInput: keyscanResult.stdout,
        timeout: 20
    )

    guard keygenResult.status == 0 else {
        throw E2EError.commandFailed("ssh-keygen -lf", keygenResult)
    }

    for token in keygenResult.stdout.split(whereSeparator: { $0.isWhitespace }) {
        if token.hasPrefix("SHA256:") {
            return normalizedFingerprint(String(token))
        }
    }

    throw E2EError.hostKeyFingerprintNotFound(keygenResult.stdout)
}

private func normalizedFingerprint(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "SHA256:", with: "")
        .replacingOccurrences(of: "=", with: "")
}

private func processEnvironment(for config: OpenSSHE2EConfig, knownHostsPath: String) -> [String: String] {
    [
        "QUIETTERM_TEST_HOST": config.host,
        "QUIETTERM_TEST_PORT": String(config.port),
        "QUIETTERM_TEST_USERNAME": config.username,
        "QUIETTERM_TEST_PASSWORD": config.password,
        "QUIETTERM_TEST_KNOWN_HOSTS": knownHostsPath
    ]
}

private func runProcess(
    _ executable: String,
    arguments: [String],
    environment: [String: String] = [:],
    standardInput: String? = nil,
    timeout: TimeInterval
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let stdin = Pipe()
    if standardInput != nil {
        process.standardInput = stdin
    }

    try process.run()

    if let standardInput {
        stdin.fileHandleForWriting.write(Data(standardInput.utf8))
        try stdin.fileHandleForWriting.close()
    }

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        process.waitUntilExit()
        group.leave()
    }

    if group.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        throw E2EError.commandTimedOut(executable)
    }

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
        status: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

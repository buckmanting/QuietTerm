import Foundation

public struct DiagnosticRedactor: Sendable {
    public init() {}

    public func redact(_ input: String) -> String {
        var output = input
        output = redactPrivateKeyBlocks(in: output)
        output = redactKeyValueSecrets(in: output)
        return output
    }

    private func redactPrivateKeyBlocks(in input: String) -> String {
        let pattern = #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#
        return replace(pattern: pattern, in: input, with: "[REDACTED PRIVATE KEY]")
    }

    private func redactKeyValueSecrets(in input: String) -> String {
        let secretKeys = [
            "password",
            "passphrase",
            "token",
            "secret",
            "privateKey",
            "keyboardInteractiveResponse"
        ]

        return secretKeys.reduce(input) { partial, key in
            let pattern = #"(?i)(\b\#(key)\b\s*[:=]\s*)([^\n\r,}]+)"#
                .replacingOccurrences(of: #"\#(key)"#, with: NSRegularExpression.escapedPattern(for: key))
            return replace(pattern: pattern, in: partial, with: "$1[REDACTED]")
        }
    }

    private func replace(pattern: String, in input: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return input
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}

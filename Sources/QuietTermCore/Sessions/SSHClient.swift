import Foundation

public struct SSHConnectionRequest: Equatable, Sendable {
    public var profile: HostProfile
    public var terminalSize: TerminalSize

    public init(profile: HostProfile, terminalSize: TerminalSize) {
        self.profile = profile
        self.terminalSize = terminalSize
    }
}

public struct TerminalSize: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

public protocol SSHClient: Sendable {
    func connect(_ request: SSHConnectionRequest) async throws -> AsyncThrowingStream<SSHEvent, Error>
}

public enum SSHEvent: Equatable, Sendable {
    case stateChanged(ConnectionState)
    case terminalOutput(Data)
    case hostKeyChallenge(HostKeyFingerprint)
    case keyboardInteractivePrompt(KeyboardInteractivePrompt)
}

public struct KeyboardInteractivePrompt: Codable, Equatable, Sendable {
    public var name: String
    public var instruction: String
    public var prompts: [Prompt]

    public init(name: String, instruction: String, prompts: [Prompt]) {
        self.name = name
        self.instruction = instruction
        self.prompts = prompts
    }

    public struct Prompt: Codable, Equatable, Sendable {
        public var text: String
        public var isEchoEnabled: Bool

        public init(text: String, isEchoEnabled: Bool) {
            self.text = text
            self.isEchoEnabled = isEchoEnabled
        }
    }
}

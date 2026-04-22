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

public struct SSHConnectionHandlers: Sendable {
    public var requestPassword: @Sendable (HostProfile) async throws -> SSHPasswordCredential
    public var validateHostKey: @Sendable (HostKeyFingerprint) async throws -> SSHHostKeyValidation

    public init(
        requestPassword: @escaping @Sendable (HostProfile) async throws -> SSHPasswordCredential,
        validateHostKey: @escaping @Sendable (HostKeyFingerprint) async throws -> SSHHostKeyValidation
    ) {
        self.requestPassword = requestPassword
        self.validateHostKey = validateHostKey
    }
}

public struct SSHPasswordCredential: Equatable, Sendable {
    private var bytes: [UInt8]

    public init(_ password: String) {
        self.bytes = Array(password.utf8)
    }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var isEmpty: Bool {
        bytes.isEmpty
    }

    public var byteCount: Int {
        bytes.count
    }

    public mutating func withNullTerminatedUTF8<Result>(
        _ body: (UnsafePointer<CChar>) throws -> Result
    ) rethrows -> Result {
        var cString = bytes.map { CChar(bitPattern: $0) }
        cString.append(0)
        defer {
            cString.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
        }

        return try cString.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }

    public mutating func discard() {
        bytes.withUnsafeMutableBufferPointer { buffer in
            buffer.initialize(repeating: 0)
        }
        bytes.removeAll(keepingCapacity: false)
    }
}

public enum SSHHostKeyValidation: Equatable, Sendable {
    case trusted
    case rejected(reason: String)

    public var isTrusted: Bool {
        self == .trusted
    }
}

public enum SSHConnectionError: Error, Equatable, Sendable {
    case passwordRequired
    case passwordCancelled
    case hostKeyRejected(String)
    case authenticationFailed
    case connectionFailed(String)
    case sessionClosed(String?)
    case unsupportedAuthMethod(String)
}

public protocol SSHClient: Sendable {
    func connect(
        _ request: SSHConnectionRequest,
        handlers: SSHConnectionHandlers
    ) async throws -> any SSHSession
}

public protocol SSHSession: Sendable {
    var events: AsyncThrowingStream<SSHEvent, Error> { get }

    func send(_ data: Data) async throws
    func close() async
}

public enum SSHEvent: Equatable, Sendable {
    case stateChanged(ConnectionState)
    case terminalOutput(Data)
    case hostKeyChallenge(HostKeyFingerprint)
    case keyboardInteractivePrompt(KeyboardInteractivePrompt)
}

public enum TerminalInput: Equatable, Sendable {
    case text(String)
    case enter
    case backspace
    case tab
    case arrowUp
    case arrowDown
    case arrowRight
    case arrowLeft
    case control(Character)
    case raw([UInt8])

    public var bytes: [UInt8] {
        switch self {
        case .text(let text):
            Array(text.utf8)
        case .enter:
            [0x0d]
        case .backspace:
            [0x7f]
        case .tab:
            [0x09]
        case .arrowUp:
            [0x1b, 0x5b, 0x41]
        case .arrowDown:
            [0x1b, 0x5b, 0x42]
        case .arrowRight:
            [0x1b, 0x5b, 0x43]
        case .arrowLeft:
            [0x1b, 0x5b, 0x44]
        case .control(let character):
            TerminalInput.controlByte(for: character).map { [$0] } ?? []
        case .raw(let bytes):
            bytes
        }
    }

    private static func controlByte(for character: Character) -> UInt8? {
        guard let scalar = character.unicodeScalars.first else {
            return nil
        }

        let value = scalar.value
        switch value {
        case 64...95:
            return UInt8(value - 64)
        case 96...122:
            return UInt8(value - 96)
        default:
            return nil
        }
    }
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

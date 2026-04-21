import Foundation

public struct DiagnosticSnapshot: Codable, Equatable, Sendable {
    public var appVersion: String
    public var buildNumber: String
    public var deviceModel: String
    public var osVersion: String
    public var syncStatus: String
    public var profiles: [SyncedHostProfile]
    public var sessions: [TerminalSession]
    public var events: [String]

    public init(
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        osVersion: String,
        syncStatus: String,
        profiles: [SyncedHostProfile],
        sessions: [TerminalSession],
        events: [String]
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.syncStatus = syncStatus
        self.profiles = profiles
        self.sessions = sessions
        self.events = events
    }

    public func exportText(redactor: DiagnosticRedactor = DiagnosticRedactor()) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return redactor.redact("Diagnostic export failed to encode.")
        }

        return redactor.redact(text)
    }
}

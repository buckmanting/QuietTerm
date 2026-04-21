import Foundation

public enum AppearancePreference: String, Codable, CaseIterable, Equatable, Sendable {
    case dark
    case light
    case system

    public var displayName: String {
        switch self {
        case .dark:
            "Dark"
        case .light:
            "Light"
        case .system:
            "System"
        }
    }
}

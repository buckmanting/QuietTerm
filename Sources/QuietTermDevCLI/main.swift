import Foundation
import QuietTermCore

let profile = HostProfile(
    alias: "Example host",
    hostname: "example.com",
    username: "aaron",
    authMethod: .keyboardInteractive
)

print("QuietTerm core initialized")
print("Profile: \(profile.alias) -> \(profile.connectionLabel)")

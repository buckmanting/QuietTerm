import Foundation
import QuietTermCore

let profile = HostProfile(
    alias: "Example host",
    hostname: "example.com",
    username: "aaron",
    authMethod: .keyboardInteractive
)

print("Quiet Term core initialized")
print("Profile: \(profile.alias) -> \(profile.connectionLabel)")

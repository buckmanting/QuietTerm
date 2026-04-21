# Quiet Term

Quiet Term is a native iOS/iPadOS SSH terminal beta for highly technical users who need reliable foreground SSH sessions from Apple mobile devices.

## Current Status

The repository is initialized with:
- `QuietTermCore`: buildable Swift package target for profiles, sync merge policy, host-key trust, secret storage abstractions, SSH/session contracts, and diagnostics redaction.
- `Apps/QuietTermApp`: native SwiftUI app shell for host library, per-device terminal tabs, dark-default appearance, settings, and diagnostics.
- `project.yml`: XcodeGen project definition for creating the iOS app project when XcodeGen is available.
- `.github/workflows/ci.yml`: Swift package CI for core tests.
- `tooling/ssh-fixtures`: placeholder for repeatable OpenSSH beta fixtures.
- `Docs`: release, QA, and architecture notes.

## Jira

Backlog lives in the Quiet Term Jira project:
- Epics: `KAN-1` through `KAN-6`
- Stories/Tasks: `KAN-7` through `KAN-34`
- Query: <https://buckmanting.atlassian.net/issues?jql=project%20%3D%20KAN%20ORDER%20BY%20key%20ASC>

## Local Development

Run the core tests:

```sh
swift test
```

Run the development CLI:

```sh
swift run quietterm-dev
```

Generate the iOS project once XcodeGen is installed:

```sh
xcodegen generate
open QuietTerm.xcodeproj
```

## Beta Scope

In scope:
- iOS and iPadOS internal TestFlight beta.
- Host profiles and non-secret iCloud sync.
- Local Keychain secrets.
- Strict trust-on-first-use host-key verification.
- Password, private-key, passphrase, and keyboard-interactive auth.
- Multiple foreground sessions in tabs.
- Basic theme toggle with dark as the default.
- Sanitized diagnostics export.

Out of scope:
- macOS release.
- SFTP, port forwarding, mosh, agent forwarding.
- Team cloud/admin features.
- Profile import/export.
- Public App Store purchase flows.

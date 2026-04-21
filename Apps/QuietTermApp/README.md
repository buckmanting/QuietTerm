# Quiet Term App Shell

This folder contains the native SwiftUI iOS/iPadOS shell for Quiet Term.

Current state:
- Host library first navigation.
- Per-device terminal tabs.
- Dark default with a basic theme toggle.
- Sanitized diagnostics export surface.
- Placeholder terminal surface pending SwiftTerm/libssh2 integration.

The buildable domain layer lives in the root Swift package as `QuietTermCore`.
Generate or create the Xcode application target from `project.yml`, then link the local package product `QuietTermCore`.

# Quiet Term App Shell

This folder contains the native SwiftUI iOS/iPadOS shell for Quiet Term.

Current state:
- Host library first navigation.
- Per-device terminal tabs.
- Dark default with a basic theme toggle.
- Sanitized diagnostics export surface.
- SwiftTerm-backed terminal renderer fixture for KAN-21. It renders local fixture bytes only; SSH, PTY lifecycle, keyboard dispatch, and tabs hardening remain separate tickets.

The buildable domain layer lives in the root Swift package as `QuietTermCore`.
Generate or create the Xcode application target from `project.yml`, then link the local package product `QuietTermCore`.

KAN-21 simulator proof is manual until app-project generation is available in CI:
generate the project with XcodeGen, run one iPhone simulator and one iPad simulator, open the example host, and verify terminal fixture rendering and resize behavior. Set `QUIET_TERM_SCROLLBACK_SMOKE=1` in the scheme launch environment for the 10k-line scrollback smoke run.

# Architecture Overview

Quiet Term is split into a testable Swift package and a native app shell.

## Core Package

`QuietTermCore` owns platform-neutral domain behavior:
- Host profile model and validation.
- Secret references and secret-store protocol.
- Keychain-backed secret store for Apple platforms.
- Host-key trust decisions.
- Last-edit-wins profile sync merge.
- SSH client/session contracts.
- Diagnostic export and redaction.

The core package is intentionally independent of SwiftUI so it can be tested quickly and reused by a future macOS target.

## App Shell

`Apps/QuietTermApp` owns iOS/iPadOS presentation:
- Host library first navigation.
- Multiple foreground terminal sessions as tabs.
- Settings with basic theme selection.
- Diagnostics export surface.

The terminal view currently uses a placeholder. `KAN-21` will replace it with the selected terminal renderer, expected to be SwiftTerm or a comparable proven component.

## SSH Adapter

The production SSH adapter will sit behind `SSHClient`.

Initial dependency assumption:
- Terminal rendering: SwiftTerm.
- SSH transport/auth: libssh2, because keyboard-interactive auth is mandatory for beta.

`KAN-15` tracks the dependency review before integration.

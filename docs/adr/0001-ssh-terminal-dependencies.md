# ADR 0001: SSH and Terminal Dependencies for Beta

Date: 2026-04-21

Status: Proposed

Jira: [KAN-15](https://buckmanting.atlassian.net/browse/KAN-15)

## Context

Quiet Term needs one recommended SSH library and one recommended terminal rendering
library before implementation work proceeds on password authentication, private-key
authentication, keyboard-interactive authentication, and xterm-style terminal
rendering.

This ADR is a recommendation artifact only. It does not add packages, perform a
build spike, write wrappers, integrate SSH, integrate a terminal view, or generate
OSS notices.

Primary audience: the beta implementer for KAN-16, KAN-17, KAN-18, and KAN-21.

## Decision

Recommend this beta stack:

- SSH: [libssh2](https://github.com/libssh2/libssh2)
- Terminal rendering: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)

The recommendation is security and maintainability led. It prioritizes explicit
support for the beta authentication requirements over the convenience of a pure
Swift API.

The main accepted risk is iOS packaging for `libssh2`. KAN-15 accepts this as a
documented risk only. A later implementation task must prove packaging, link
behavior, crypto backend selection, and binary/source provenance before shipping.

## Hard Gates

| Gate | Required bar | libssh2 | SwiftNIO SSH | Citadel | SwiftTerm | xterm.js WebView |
| --- | --- | --- | --- | --- | --- | --- |
| App Store compatible license | Permissive or otherwise App Store compatible | PASS: BSD-3-Clause | PASS: Apache-2.0 | PASS: MIT | PASS: MIT | PASS: MIT |
| iPhone/iPad beta suitability | Usable in an iOS/iPadOS app, with packaging risk documented | RISK: C library, packaging must be proven | RISK: Swift package, lower-level API | RISK: Swift package, wrapper maturity and transitive dependency review required | PASS: native UIKit support | RISK: WebView bridge, web runtime, and input handling |
| Maintenance and security posture | Active enough for beta and has a security reporting/update path | PASS: mature project, latest GitHub release is [1.11.1](https://github.com/libssh2/libssh2/releases) | PASS: Apple project, latest release is [0.13.0](https://github.com/apple/swift-nio-ssh/releases) | PASS/RISK: active project, latest release is [0.12.1](https://swiftpackageindex.com/orlandos-nl/Citadel) | PASS: latest release is [v1.13.0](https://github.com/migueldeicaza/SwiftTerm/releases/tag/v1.13.0), but policy supports only latest release | PASS: mature project, latest release is [6.0.0](https://github.com/xtermjs/xterm.js/releases) |
| Host-key trust | Must support TOFU with mismatch blocking | PASS: provides host-key and known-host APIs | RISK: implementer must build policy around lower-level primitives | RISK: exposes host key validators, but app policy still must forbid accept-anything | N/A | N/A |
| Password auth | Must support username/password SSH login | PASS: documented `libssh2_userauth_password` family | PASS: documented password user authentication | PASS: documented password-based client usage | N/A | N/A |
| Private-key auth | Must support private key auth with passphrase path | PASS: [`libssh2_userauth_publickey_frommemory`](https://libssh2.org/libssh2_userauth_publickey_frommemory.html) supports private-key material and passphrase | RISK: supports public key auth, but client key parsing/import work remains | RISK: helper support exists, but RSA support notes depend on NIOSSH/fork state | N/A | N/A |
| Keyboard-interactive auth | Must support challenge/response and MFA-style prompts | PASS: [`libssh2_userauth_keyboard_interactive_ex`](https://libssh2.org/libssh2_userauth_keyboard_interactive_ex.html) directly models prompts and responses | FAIL/RISK: not advertised in the project feature list reviewed for this ADR | FAIL/RISK: not clearly advertised and inherits NIOSSH limitations | N/A | N/A |
| Ed25519 and RSA-SHA2 viability | Must be viable for beta after backend selection | PASS/RISK: release notes document modern key and RSA-SHA2 work; implementation must pin a crypto backend that exposes required algorithms | FAIL/RISK: feature list emphasizes Ed25519/ECDSA and does not establish RSA-SHA2 as beta-ready | RISK: README notes RSA authentication work depends on NIOSSH/fork state | N/A | N/A |
| Terminal capability | Unicode, ANSI color, cursor movement, resize, scrollback, xterm-style behavior | N/A | N/A | N/A | PASS: native VT100/xterm library for Swift apps with UIKit/AppKit front ends | PASS/RISK: very mature terminal emulator, but WebView integration is a product and security tradeoff |

## SSH Candidate Rationale

### Recommended: libssh2

`libssh2` is the best fit for the beta SSH requirements because it directly
covers the requirements that drive KAN-16, KAN-17, and KAN-18:

- Keyboard-interactive authentication is a first-class API via
  [`libssh2_userauth_keyboard_interactive_ex`](https://libssh2.org/libssh2_userauth_keyboard_interactive_ex.html).
- In-memory private-key authentication with passphrase is documented via
  [`libssh2_userauth_publickey_frommemory`](https://libssh2.org/libssh2_userauth_publickey_frommemory.html).
- Host-key and known-host handling can be implemented using
  [`libssh2_session_hostkey`](https://libssh2.org/libssh2_session_hostkey.html)
  and [`libssh2_knownhost_check`](https://libssh2.org/libssh2_knownhost_check.html).
- The project is mature, BSD-3-Clause licensed, and has a current public release
  train through [1.11.1](https://github.com/libssh2/libssh2/releases).

Accepted risks:

- It is a C library, so Swift memory ownership, callback bridging,
  non-blocking I/O, and cancellation must be wrapped carefully.
- iOS packaging is not proven by this ADR. The implementation must either build
  from source or explicitly vet any XCFramework/prebuilt binary for provenance,
  version, crypto backend, update path, license, and reproducibility.
- Ed25519 and RSA-SHA2 support depends on the selected libssh2 version and crypto
  backend. Implementation must record the backend and supported algorithms before
  closing the first integration ticket.

### Rejected for beta recommendation: SwiftNIO SSH

[SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) is attractive because it
is Swift-native, Apple maintained, Apache-2.0 licensed, and avoids C packaging
work. It is not the beta recommendation because its public positioning is a
lower-level SSH protocol toolkit rather than a ready client library, and the
reviewed feature list does not establish keyboard-interactive authentication or
RSA-SHA2 private-key workflows as ready for Quiet Term's beta requirements.

Use SwiftNIO SSH later if the product deliberately chooses a larger pure-Swift
SSH investment over beta speed and authentication breadth.

### Rejected for beta recommendation: Citadel

[Citadel](https://github.com/orlandos-nl/Citadel) is a higher-level Swift client
and server framework around NIOSSH. It is easier to adopt than raw SwiftNIO SSH
and exposes useful client APIs, including password authentication and PTY usage.
It is not the beta recommendation because it inherits key parts of the NIOSSH
risk profile, does not clearly establish keyboard-interactive support in the
reviewed public docs, and documents RSA authentication caveats tied to NIOSSH
fork state.

Citadel remains the most plausible Swift-native fallback if libssh2 packaging
or bridging becomes unacceptable.

## Terminal Candidate Rationale

### Recommended: SwiftTerm

[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) is the recommended
terminal renderer because it is native Swift, MIT licensed, supports iOS/UIKit
and macOS/AppKit front ends, and is explicitly built for VT100/xterm terminal
emulation. Its README documents Unicode, ANSI/256/TrueColor, mouse events,
resizing, graphics capabilities, testing against terminal compatibility suites,
and real-world use in commercial SSH clients.

Accepted risks:

- The [security policy](https://github.com/migueldeicaza/SwiftTerm/blob/main/SECURITY.md)
  says only the latest release is supported, so Quiet Term must keep updates
  current and avoid pinning indefinitely.
- Terminal behavior still needs app-level verification for keyboard behavior,
  resize propagation, scrollback limits, selection, accessibility, and diagnostic
  redaction once integrated.

### Rejected as primary beta renderer: xterm.js in a WebView

[xterm.js](https://github.com/xtermjs/xterm.js) is mature, MIT licensed, widely
used, and a strong fallback comparison. It is not the primary beta recommendation
because embedding it in a native iPhone/iPad app would add a WebView bridge
between SSH I/O and terminal rendering, complicating input handling, paste,
keyboard shortcuts, accessibility, theming, diagnostics, and security review.

xterm.js should remain a fallback only if SwiftTerm fails capability testing or
maintenance expectations during implementation.

## Implementation Guidance for Follow-up Tickets

KAN-15 does not implement these items, but the first integration tickets should
use this ADR as the acceptance baseline:

- Build a small `libssh2` adapter boundary that owns session lifecycle,
  non-blocking socket integration, callback bridging, cancellation, and secret
  redaction.
- Implement TOFU host-key storage with mismatch blocking. Do not expose or ship
  an accept-anything mode.
- Capture password, private-key passphrase, and keyboard-interactive responses
  through secure prompts, and redact all secret material from diagnostics.
- Select and document the libssh2 crypto backend before shipping beta builds.
- Prove iPhone and iPad packaging, including simulator/device builds, symbols,
  bitcode-related constraints if any, license files, and binary provenance if a
  prebuilt artifact is used.
- Integrate SwiftTerm as the native terminal surface, with app-level tests for
  Unicode, ANSI color, cursor movement, resize/PTY propagation, scrollback,
  paste, keyboard input, and diagnostic export boundaries.

## Inputs for KAN-33

KAN-33 should receive these compliance inputs:

- OSS notices must include libssh2's BSD-3-Clause license and SwiftTerm's MIT
  license if this recommendation is implemented.
- If a prebuilt libssh2/OpenSSL/LibreSSL/mbedTLS artifact is used, notices must
  include every bundled transitive component and its exact version.
- Export compliance review must account for SSH and the selected cryptographic
  backend.
- Privacy docs should state that SSH credentials, private keys, passphrases,
  keyboard-interactive responses, and host-key trust state are local secrets and
  must not be synced or included in diagnostics.

## Approval

This ADR should be approved through PR review. After approval, link the merged
PR or commit back to [KAN-15](https://buckmanting.atlassian.net/browse/KAN-15).

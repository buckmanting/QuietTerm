# Privacy and Export Notes

## Data Posture

QuietTerm is local-first.

Synced through iCloud:
- Host aliases.
- Hostnames.
- Ports.
- Usernames.
- Tags/folders.
- Non-secret settings such as appearance.
- Secret availability metadata only.

Never synced by QuietTerm profile sync:
- Private keys.
- Passwords.
- Passphrases.
- Keyboard-interactive responses.
- Raw terminal content.

## Diagnostics

Diagnostics are generated only after explicit user action and must be redacted before display or sharing.

Diagnostics may include:
- App version/build.
- Device and OS metadata.
- Non-secret profile metadata.
- Sync status.
- Session lifecycle states.
- Error codes.

Diagnostics must not include:
- Private keys.
- Passwords.
- Passphrases.
- Tokens.
- Raw MFA/challenge responses.

## Export Compliance

QuietTerm uses SSH and therefore encryption. App Store Connect encryption/export answers must be completed before TestFlight/App Review submission.

This document is not legal advice; it is the engineering checklist source for `KAN-33`.

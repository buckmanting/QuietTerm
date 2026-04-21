# SSH Fixtures

This folder will hold repeatable OpenSSH fixtures for `KAN-31`.

Required beta scenarios:
- Password authentication.
- Private-key authentication.
- Passphrase-protected key authentication.
- Keyboard-interactive authentication.
- Unknown host key.
- Changed host key.
- Forced disconnect.
- Pty resize.

The fixture implementation should be deterministic and runnable locally. Container support should be added only once the SSH adapter integration begins.

# Beta Readiness

The internal TestFlight beta is blocked unless these journeys pass on supported iPhone and iPad devices:

1. Create a host profile.
2. Manage key/password authentication.
3. Verify unknown and changed SSH host keys.
4. Run and interact with a terminal session.
5. Recover from failure and export sanitized diagnostics.

## Quality Bar

No known P0/P1 defects in:
- Local secret handling.
- Host-key trust decisions.
- SSH connection lifecycle.
- Profile sync.
- Terminal input/output.

Performance must meet the responsive baseline:
- Launch has no obvious stall.
- Typing echo feels immediate.
- Scrollback remains usable.
- Tab switching is responsive.
- SSH throughput has no obvious UI blocking.

## Bug Policy

Do not create speculative bugs. Create a Bug issue only for a reproducible failure, with:
- Device and OS.
- App version/build.
- Host fixture or server details.
- Steps to reproduce.
- Expected and actual results.
- Sanitized logs or diagnostics.

## KAN-25 Phase 1

The detailed Phase 1 hardening gate for `KAN-25` is tracked in `Docs/QA/kan-25-phase1-validation.md`.

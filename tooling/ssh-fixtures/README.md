# SSH Fixtures

Deterministic OpenSSH fixtures for `KAN-31`.

## Scenarios

The fixture suite validates all mandatory scenarios:

1. Password authentication (`password`, port `2222`)
2. Private-key authentication with Ed25519 and RSA-SHA2 (`key-auth`, port `2223`)
3. Passphrase-protected key authentication (`passphrase`, port `2224`)
4. Keyboard-interactive authentication (`keyboard-interactive`, port `2225`)
5. Unknown host key trust flow (`unknown-host`, port `2226`)
6. Changed host key detection on the same host/port (`changed-host`, port `2227`)
7. Forced disconnect after authentication (`forced-disconnect`, port `2228`)
8. PTY resize propagation (`pty-resize`, port `2229`)

## Determinism Rules

- Fixture containers use a pinned base image digest.
- Non-secret fixture material is committed under `materials/`.
- Throwaway fixture credentials are static and intentionally non-production:
  - Username: `quiet`
  - Password: `quiet-password`
  - Passphrase key passphrase: `fixture-passphrase`

## Local Run

Run all scenario checks:

```sh
tooling/ssh-fixtures/scripts/run-fixture-checks.sh
```

Write artifacts to a custom path:

```sh
tooling/ssh-fixtures/scripts/run-fixture-checks.sh /tmp/quietterm-ssh-fixtures
```

The runner always writes per-scenario logs plus Docker Compose diagnostics to the artifact directory.

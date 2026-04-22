#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <scenario-name> <artifact-dir>" >&2
    exit 1
fi

readonly SCENARIO_NAME="$1"
readonly SCENARIO_ARTIFACT_DIR="$2"
mkdir -p "$SCENARIO_ARTIFACT_DIR"

# shellcheck source=tooling/ssh-fixtures/scripts/lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_commands expect python3 ssh ssh-keygen ssh-keyscan

materialize_private_key() {
    local source_key_path="$1"
    local destination_dir="$2"
    local destination_name="$3"

    if [[ ! -f "$source_key_path" ]]; then
        echo "Missing private key: $source_key_path" >&2
        return 1
    fi

    mkdir -p "$destination_dir"
    local destination_key_path="$destination_dir/$destination_name"
    cp "$source_key_path" "$destination_key_path"
    chmod 600 "$destination_key_path"
    printf '%s\n' "$destination_key_path"
}

scenario_password_auth() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    write_known_hosts 2222 "$known_hosts"

    run_expect_password_command 2222 "$known_hosts" "printf PASSWORD_AUTH_OK" "PASSWORD_AUTH_OK"
}

scenario_key_auth() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    local key_dir="$SCENARIO_ARTIFACT_DIR/private-keys"
    write_known_hosts 2223 "$known_hosts"

    local ed25519_key
    ed25519_key="$(materialize_private_key "$USER_KEYS_DIR/id_ed25519" "$key_dir" "id_ed25519")"
    local rsa_key
    rsa_key="$(materialize_private_key "$USER_KEYS_DIR/id_rsa" "$key_dir" "id_rsa")"

    ssh -i "$ed25519_key" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        -o IdentitiesOnly=yes \
        -p 2223 \
        "$SSH_USER@$SSH_HOST" \
        "sh -lc 'printf KEY_ED25519_OK'" > "$SCENARIO_ARTIFACT_DIR/ed25519.out"

    ssh -i "$rsa_key" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" \
        -o PreferredAuthentications=publickey \
        -o PasswordAuthentication=no \
        -o IdentitiesOnly=yes \
        -o PubkeyAcceptedAlgorithms=rsa-sha2-512,rsa-sha2-256 \
        -p 2223 \
        "$SSH_USER@$SSH_HOST" \
        "sh -lc 'printf KEY_RSA_SHA2_OK'" > "$SCENARIO_ARTIFACT_DIR/rsa.out"

    grep -q "KEY_ED25519_OK" "$SCENARIO_ARTIFACT_DIR/ed25519.out"
    grep -q "KEY_RSA_SHA2_OK" "$SCENARIO_ARTIFACT_DIR/rsa.out"
}

scenario_passphrase_auth() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    local key_dir="$SCENARIO_ARTIFACT_DIR/private-keys"
    write_known_hosts 2224 "$known_hosts"

    local passphrase_key
    passphrase_key="$(materialize_private_key "$USER_KEYS_DIR/id_ed25519_passphrase" "$key_dir" "id_ed25519_passphrase")"

    local askpass_script="$SCENARIO_ARTIFACT_DIR/askpass.sh"
    cat > "$askpass_script" <<'ASKPASS'
#!/usr/bin/env bash
printf '%s\n' "fixture-passphrase"
ASKPASS
    chmod 700 "$askpass_script"

    DISPLAY=quietterm-fixture \
    SSH_ASKPASS="$askpass_script" \
    SSH_ASKPASS_REQUIRE=force \
    ssh -i "$passphrase_key" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o BatchMode=no \
        -o IdentitiesOnly=yes \
        -p 2224 \
        "$SSH_USER@$SSH_HOST" \
        "sh -lc 'printf KEY_PASSPHRASE_OK'" > "$SCENARIO_ARTIFACT_DIR/passphrase.out"

    grep -q "KEY_PASSPHRASE_OK" "$SCENARIO_ARTIFACT_DIR/passphrase.out"
}

scenario_keyboard_interactive() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    write_known_hosts 2225 "$known_hosts"

    run_expect_keyboard_interactive_command \
        2225 \
        "$known_hosts" \
        "printf KEYBOARD_INTERACTIVE_OK" \
        "KEYBOARD_INTERACTIVE_OK"
}

scenario_unknown_host() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    local initial_stderr="$SCENARIO_ARTIFACT_DIR/initial_stderr.log"
    : > "$known_hosts"

    set +e
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" \
        -o ConnectTimeout=5 \
        -p 2226 \
        "$SSH_USER@$SSH_HOST" \
        "true" > /dev/null 2> "$initial_stderr"
    local initial_status=$?
    set -e

    if (( initial_status == 0 )); then
        echo "Unknown host check unexpectedly succeeded before trust pinning" >&2
        return 1
    fi

    write_known_hosts 2226 "$known_hosts"
    run_expect_password_command 2226 "$known_hosts" "printf UNKNOWN_HOST_TRUSTED_OK" "UNKNOWN_HOST_TRUSTED_OK"
}

scenario_changed_host() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    local fingerprint_before_file="$SCENARIO_ARTIFACT_DIR/fingerprint_before.txt"
    local fingerprint_after_file="$SCENARIO_ARTIFACT_DIR/fingerprint_after.txt"
    local changed_stderr="$SCENARIO_ARTIFACT_DIR/changed_host_stderr.log"

    write_known_hosts 2227 "$known_hosts"
    host_fingerprint_from_known_hosts "$known_hosts" > "$fingerprint_before_file"

    run_expect_password_command 2227 "$known_hosts" "printf CHANGED_HOST_INITIAL_OK" "CHANGED_HOST_INITIAL_OK"

    (cd "$FIXTURE_ROOT" && HOST_KEY_PROFILE=v2 docker compose up -d --force-recreate --no-deps changed-host >/dev/null)
    wait_for_ssh_port 2227 30

    local rescanned_known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts_v2"
    write_known_hosts 2227 "$rescanned_known_hosts"
    host_fingerprint_from_known_hosts "$rescanned_known_hosts" > "$fingerprint_after_file"

    if cmp -s "$fingerprint_before_file" "$fingerprint_after_file"; then
        echo "Changed-host scenario failed because host fingerprint did not rotate" >&2
        return 1
    fi

    set +e
    ssh -o BatchMode=yes \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" \
        -o ConnectTimeout=5 \
        -p 2227 \
        "$SSH_USER@$SSH_HOST" \
        "true" > /dev/null 2> "$changed_stderr"
    local changed_status=$?
    set -e

    if (( changed_status == 0 )); then
        echo "Changed-host scenario unexpectedly succeeded after key rotation" >&2
        return 1
    fi
}

scenario_forced_disconnect() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    write_known_hosts 2228 "$known_hosts"

    local start_epoch
    start_epoch="$(date +%s)"

    set +e
    run_expect_forced_disconnect 2228 "$known_hosts"
    local disconnect_status=$?
    set -e

    local elapsed
    elapsed=$(( $(date +%s) - start_epoch ))

    printf '%s\n' "$disconnect_status" > "$SCENARIO_ARTIFACT_DIR/status.txt"
    printf '%s\n' "$elapsed" > "$SCENARIO_ARTIFACT_DIR/elapsed_seconds.txt"

    if (( disconnect_status == 0 )); then
        echo "Forced-disconnect scenario unexpectedly exited with status 0" >&2
        return 1
    fi

    if (( elapsed > 5 )); then
        echo "Forced-disconnect scenario took too long (${elapsed}s)" >&2
        return 1
    fi
}

scenario_pty_resize() {
    local known_hosts="$SCENARIO_ARTIFACT_DIR/known_hosts"
    local key_dir="$SCENARIO_ARTIFACT_DIR/private-keys"
    write_known_hosts 2229 "$known_hosts"

    local resize_key
    resize_key="$(materialize_private_key "$USER_KEYS_DIR/id_ed25519" "$key_dir" "id_ed25519")"

    python3 "$SCRIPT_DIR/check_resize.py" \
        --host "$SSH_HOST" \
        --port 2229 \
        --user "$SSH_USER" \
        --private-key "$resize_key" \
        --known-hosts "$known_hosts" \
        --rows 40 \
        --cols 120 \
        --artifact "$SCENARIO_ARTIFACT_DIR"
}

case "$SCENARIO_NAME" in
    password_auth)
        scenario_password_auth
        ;;
    key_auth)
        scenario_key_auth
        ;;
    passphrase_auth)
        scenario_passphrase_auth
        ;;
    keyboard_interactive)
        scenario_keyboard_interactive
        ;;
    unknown_host)
        scenario_unknown_host
        ;;
    changed_host)
        scenario_changed_host
        ;;
    forced_disconnect)
        scenario_forced_disconnect
        ;;
    pty_resize)
        scenario_pty_resize
        ;;
    *)
        echo "Unknown scenario: $SCENARIO_NAME" >&2
        exit 2
        ;;
esac

printf 'scenario=%s status=pass\n' "$SCENARIO_NAME" > "$SCENARIO_ARTIFACT_DIR/result.txt"

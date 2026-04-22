#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FIXTURE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SSH_HOST="127.0.0.1"
readonly SSH_USER="quiet"
readonly SSH_PASSWORD="quiet-password"
readonly SSH_PASSPHRASE="fixture-passphrase"
readonly USER_KEYS_DIR="$FIXTURE_ROOT/materials/user-keys"

compose() {
    (cd "$FIXTURE_ROOT" && docker compose "$@")
}

require_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if ((${#missing[@]} > 0)); then
        echo "Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

wait_for_ssh_port() {
    local port="$1"
    local timeout_seconds="$2"
    local started_at
    started_at="$(date +%s)"

    while true; do
        if ssh-keyscan -T 2 -p "$port" "$SSH_HOST" >/dev/null 2>&1; then
            return 0
        fi

        if (( "$(date +%s)" - started_at >= timeout_seconds )); then
            echo "Timed out waiting for SSH on ${SSH_HOST}:${port}" >&2
            return 1
        fi

        sleep 1
    done
}

write_known_hosts() {
    local port="$1"
    local destination="$2"
    mkdir -p "$(dirname "$destination")"

    local attempt
    for attempt in $(seq 1 20); do
        if ssh-keyscan -T 2 -p "$port" -t ed25519 "$SSH_HOST" > "$destination" 2>/dev/null && [[ -s "$destination" ]]; then
            return 0
        fi

        sleep 1
    done

    echo "Unable to write known_hosts entry for ${SSH_HOST}:${port}" >&2
    return 1
}

host_fingerprint_from_known_hosts() {
    local known_hosts_file="$1"
    ssh-keygen -lf "$known_hosts_file" | awk 'NR==1 { print $2 }'
}

run_expect_password_command() {
    local port="$1"
    local known_hosts_file="$2"
    local remote_command="$3"
    local expected_token="$4"

    EXPECT_PORT="$port" \
    EXPECT_KNOWN_HOSTS="$known_hosts_file" \
    EXPECT_REMOTE_COMMAND="$remote_command" \
    EXPECT_EXPECTED_TOKEN="$expected_token" \
    EXPECT_HOST="$SSH_HOST" \
    EXPECT_USER="$SSH_USER" \
    EXPECT_PASSWORD="$SSH_PASSWORD" \
    expect <<'EXPECT'
set timeout 20
set host $env(EXPECT_HOST)
set user $env(EXPECT_USER)
set port $env(EXPECT_PORT)
set knownHosts $env(EXPECT_KNOWN_HOSTS)
set password $env(EXPECT_PASSWORD)
set remoteCommand $env(EXPECT_REMOTE_COMMAND)
set expectedToken $env(EXPECT_EXPECTED_TOKEN)

spawn ssh -o StrictHostKeyChecking=yes \
          -o UserKnownHostsFile=$knownHosts \
          -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no \
          -o NumberOfPasswordPrompts=1 \
          -p $port \
          $user@$host \
          "sh -lc '$remoteCommand'"

expect {
    -re "(?i)password:" {
        send -- "$password\r"
    }
    timeout {
        puts stderr "Password prompt timed out"
        exit 10
    }
}

expect {
    -re $expectedToken {}
    timeout {
        puts stderr "Expected token not found in SSH output"
        exit 11
    }
}

expect eof
catch wait result
set status [lindex $result 3]
exit $status
EXPECT
}

run_expect_keyboard_interactive_command() {
    local port="$1"
    local known_hosts_file="$2"
    local remote_command="$3"
    local expected_token="$4"

    EXPECT_PORT="$port" \
    EXPECT_KNOWN_HOSTS="$known_hosts_file" \
    EXPECT_REMOTE_COMMAND="$remote_command" \
    EXPECT_EXPECTED_TOKEN="$expected_token" \
    EXPECT_HOST="$SSH_HOST" \
    EXPECT_USER="$SSH_USER" \
    EXPECT_PASSWORD="$SSH_PASSWORD" \
    expect <<'EXPECT'
set timeout 20
set host $env(EXPECT_HOST)
set user $env(EXPECT_USER)
set port $env(EXPECT_PORT)
set knownHosts $env(EXPECT_KNOWN_HOSTS)
set password $env(EXPECT_PASSWORD)
set remoteCommand $env(EXPECT_REMOTE_COMMAND)
set expectedToken $env(EXPECT_EXPECTED_TOKEN)

spawn ssh -o StrictHostKeyChecking=yes \
          -o UserKnownHostsFile=$knownHosts \
          -o PreferredAuthentications=keyboard-interactive \
          -o KbdInteractiveAuthentication=yes \
          -o PasswordAuthentication=no \
          -o PubkeyAuthentication=no \
          -o NumberOfPasswordPrompts=1 \
          -p $port \
          $user@$host \
          "sh -lc '$remoteCommand'"

expect {
    -re "(?i)(password|verification|code):" {
        send -- "$password\r"
    }
    timeout {
        puts stderr "Keyboard-interactive prompt timed out"
        exit 20
    }
}

expect {
    -re $expectedToken {}
    timeout {
        puts stderr "Expected token not found after keyboard-interactive auth"
        exit 21
    }
}

expect eof
catch wait result
set status [lindex $result 3]
exit $status
EXPECT
}

run_expect_passphrase_key_command() {
    local port="$1"
    local known_hosts_file="$2"
    local key_path="$3"
    local remote_command="$4"
    local expected_token="$5"

    EXPECT_PORT="$port" \
    EXPECT_KNOWN_HOSTS="$known_hosts_file" \
    EXPECT_KEY_PATH="$key_path" \
    EXPECT_REMOTE_COMMAND="$remote_command" \
    EXPECT_EXPECTED_TOKEN="$expected_token" \
    EXPECT_HOST="$SSH_HOST" \
    EXPECT_USER="$SSH_USER" \
    EXPECT_PASSPHRASE="$SSH_PASSPHRASE" \
    expect <<'EXPECT'
set timeout 20
set host $env(EXPECT_HOST)
set user $env(EXPECT_USER)
set port $env(EXPECT_PORT)
set knownHosts $env(EXPECT_KNOWN_HOSTS)
set keyPath $env(EXPECT_KEY_PATH)
set passphrase $env(EXPECT_PASSPHRASE)
set remoteCommand $env(EXPECT_REMOTE_COMMAND)
set expectedToken $env(EXPECT_EXPECTED_TOKEN)

spawn ssh -i $keyPath \
          -o StrictHostKeyChecking=yes \
          -o UserKnownHostsFile=$knownHosts \
          -o PreferredAuthentications=publickey \
          -o PubkeyAuthentication=yes \
          -o PasswordAuthentication=no \
          -o NumberOfPasswordPrompts=0 \
          -o IdentitiesOnly=yes \
          -p $port \
          $user@$host \
          "sh -lc '$remoteCommand'"

expect {
    -re "(?i)enter passphrase for key" {
        send -- "$passphrase\r"
    }
    timeout {
        puts stderr "Passphrase prompt timed out"
        exit 30
    }
}

expect {
    -re $expectedToken {}
    timeout {
        puts stderr "Expected token not found after passphrase auth"
        exit 31
    }
}

expect eof
catch wait result
set status [lindex $result 3]
exit $status
EXPECT
}

run_expect_forced_disconnect() {
    local port="$1"
    local known_hosts_file="$2"

    EXPECT_PORT="$port" \
    EXPECT_KNOWN_HOSTS="$known_hosts_file" \
    EXPECT_HOST="$SSH_HOST" \
    EXPECT_USER="$SSH_USER" \
    EXPECT_PASSWORD="$SSH_PASSWORD" \
    expect <<'EXPECT'
set timeout 20
set host $env(EXPECT_HOST)
set user $env(EXPECT_USER)
set port $env(EXPECT_PORT)
set knownHosts $env(EXPECT_KNOWN_HOSTS)
set password $env(EXPECT_PASSWORD)

spawn ssh -o StrictHostKeyChecking=yes \
          -o UserKnownHostsFile=$knownHosts \
          -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no \
          -o NumberOfPasswordPrompts=1 \
          -p $port \
          $user@$host \
          "true"

expect {
    -re "(?i)password:" {
        send -- "$password\r"
    }
    timeout {
        puts stderr "Password prompt timed out for forced disconnect scenario"
        exit 40
    }
}

expect eof
catch wait result
set status [lindex $result 3]
exit $status
EXPECT
}

run_expect_resize_check() {
    local port="$1"
    local known_hosts_file="$2"
    local expected_rows="$3"
    local expected_cols="$4"

    EXPECT_PORT="$port" \
    EXPECT_KNOWN_HOSTS="$known_hosts_file" \
    EXPECT_EXPECTED_ROWS="$expected_rows" \
    EXPECT_EXPECTED_COLS="$expected_cols" \
    EXPECT_HOST="$SSH_HOST" \
    EXPECT_USER="$SSH_USER" \
    EXPECT_PASSWORD="$SSH_PASSWORD" \
    expect <<'EXPECT'
set timeout 25
set host $env(EXPECT_HOST)
set user $env(EXPECT_USER)
set port $env(EXPECT_PORT)
set knownHosts $env(EXPECT_KNOWN_HOSTS)
set password $env(EXPECT_PASSWORD)
set expectedRows $env(EXPECT_EXPECTED_ROWS)
set expectedCols $env(EXPECT_EXPECTED_COLS)

stty rows 24 columns 80

spawn ssh -tt -o StrictHostKeyChecking=yes \
             -o UserKnownHostsFile=$knownHosts \
             -o PreferredAuthentications=password \
             -o PubkeyAuthentication=no \
             -o NumberOfPasswordPrompts=1 \
             -p $port \
             $user@$host \
             "sh -lc 'stty size; read -r _; stty size'"

expect {
    -re "(?i)password:" {
        send -- "$password\r"
    }
    timeout {
        puts stderr "Password prompt timed out for resize scenario"
        exit 50
    }
}

expect {
    -re {([0-9]+) ([0-9]+)} {
        set initialRows $expect_out(1,string)
        set initialCols $expect_out(2,string)
    }
    timeout {
        puts stderr "Did not receive initial stty size output"
        exit 51
    }
}

stty rows $expectedRows columns $expectedCols
after 300
send -- "\r"

expect {
    -re {([0-9]+) ([0-9]+)} {
        set resizedRows $expect_out(1,string)
        set resizedCols $expect_out(2,string)

        if { $resizedRows != $expectedRows || $resizedCols != $expectedCols } {
            puts stderr "Unexpected resized dimensions: $resizedRows $resizedCols"
            exit 52
        }

        if { $initialRows == $resizedRows && $initialCols == $resizedCols } {
            puts stderr "Resize did not change terminal dimensions"
            exit 53
        }
    }
    timeout {
        puts stderr "Did not receive resized stty size output"
        exit 54
    }
}

expect eof
catch wait result
set status [lindex $result 3]
exit $status
EXPECT
}

#!/usr/bin/env bash
set -euo pipefail

readonly RUNNER_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tooling/ssh-fixtures/scripts/lib.sh
source "$RUNNER_SCRIPT_DIR/lib.sh"

require_commands docker expect python3 ssh ssh-keygen ssh-keyscan

ARTIFACTS_DIR="${1:-$FIXTURE_ROOT/artifacts/latest}"
readonly ARTIFACTS_DIR
readonly LOGS_DIR="$ARTIFACTS_DIR/logs"
readonly SCENARIOS_DIR="$ARTIFACTS_DIR/scenarios"
mkdir -p "$LOGS_DIR" "$SCENARIOS_DIR"

collect_diagnostics() {
    set +e
    compose ps > "$ARTIFACTS_DIR/compose.ps.txt" 2>&1
    compose config > "$ARTIFACTS_DIR/compose.resolved.yml" 2>&1
    compose logs --no-color > "$ARTIFACTS_DIR/compose.logs.txt" 2>&1
    set -e
}

cleanup() {
    local status="$1"
    collect_diagnostics
    compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    exit "$status"
}

trap 'cleanup "$?"' EXIT

compose down --remove-orphans --volumes >/dev/null 2>&1 || true

compose build --pull
HOST_KEY_PROFILE=v1 compose up -d

wait_for_ssh_port 2222 45
wait_for_ssh_port 2223 45
wait_for_ssh_port 2224 45
wait_for_ssh_port 2225 45
wait_for_ssh_port 2226 45
wait_for_ssh_port 2227 45
wait_for_ssh_port 2228 45
wait_for_ssh_port 2229 45

declare -a scenarios=(
    password_auth
    key_auth
    passphrase_auth
    keyboard_interactive
    unknown_host
    changed_host
    forced_disconnect
    pty_resize
)

declare -a scenario_names=()
declare -a scenario_pids=()

for scenario in "${scenarios[@]}"; do
    scenario_log="$LOGS_DIR/${scenario}.log"
    scenario_artifacts="$SCENARIOS_DIR/${scenario}"

    "$RUNNER_SCRIPT_DIR/run-scenario.sh" "$scenario" "$scenario_artifacts" > "$scenario_log" 2>&1 &
    scenario_names+=("$scenario")
    scenario_pids+=("$!")
done

failure=0

while true; do
    any_running=0

    for i in "${!scenario_pids[@]}"; do
        pid="${scenario_pids[$i]}"
        scenario_name="${scenario_names[$i]}"

        if [[ "$pid" == "0" ]]; then
            continue
        fi

        if kill -0 "$pid" >/dev/null 2>&1; then
            any_running=1
            continue
        fi

        if wait "$pid"; then
            exit_code=0
        else
            exit_code=$?
        fi

        scenario_pids[$i]=0

        if (( exit_code != 0 )); then
            echo "Scenario failed: ${scenario_name} (exit ${exit_code})" >&2
            failure=$exit_code

            for pending_pid in "${scenario_pids[@]}"; do
                if [[ "$pending_pid" != "0" ]]; then
                    kill "$pending_pid" >/dev/null 2>&1 || true
                fi
            done

            for pending_pid in "${scenario_pids[@]}"; do
                if [[ "$pending_pid" != "0" ]]; then
                    wait "$pending_pid" >/dev/null 2>&1 || true
                fi
            done

            break 2
        fi
    done

    if (( any_running == 0 )); then
        break
    fi

    sleep 0.2
done

if (( failure != 0 )); then
    exit "$failure"
fi

echo "All SSH fixture scenarios passed."

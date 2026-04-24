#!/usr/bin/env bash
set -euo pipefail

readonly USERNAME="${FIXTURE_USER:-quiet}"
readonly PASSWORD="${FIXTURE_PASSWORD:-quiet-password}"
readonly HOST_KEYS_PATH="${HOST_KEYS_PATH:-/fixture/host-keys/current}"
readonly AUTHORIZED_KEYS_PATH="${AUTHORIZED_KEYS_PATH:-}"
readonly SSHD_CONFIG_PATH="${SSHD_CONFIG_PATH:-/fixture/sshd_config}"

if [[ ! -f "$SSHD_CONFIG_PATH" ]]; then
    echo "Missing sshd config at $SSHD_CONFIG_PATH" >&2
    exit 1
fi

if [[ ! -f "$HOST_KEYS_PATH/ssh_host_ed25519_key" ]]; then
    echo "Missing host key at $HOST_KEYS_PATH/ssh_host_ed25519_key" >&2
    exit 1
fi

mkdir -p /var/run/sshd /home/$USERNAME/.ssh
chown "$USERNAME:$USERNAME" /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh

echo "$USERNAME:$PASSWORD" | chpasswd

cp "$HOST_KEYS_PATH/ssh_host_ed25519_key" /etc/ssh/ssh_host_ed25519_key
cp "$HOST_KEYS_PATH/ssh_host_ed25519_key.pub" /etc/ssh/ssh_host_ed25519_key.pub
chmod 600 /etc/ssh/ssh_host_ed25519_key
chmod 644 /etc/ssh/ssh_host_ed25519_key.pub

cp "$SSHD_CONFIG_PATH" /etc/ssh/sshd_config
chmod 644 /etc/ssh/sshd_config

if [[ -n "$AUTHORIZED_KEYS_PATH" ]]; then
    if [[ ! -f "$AUTHORIZED_KEYS_PATH" ]]; then
        echo "Missing authorized_keys file at $AUTHORIZED_KEYS_PATH" >&2
        exit 1
    fi

    cp "$AUTHORIZED_KEYS_PATH" /home/$USERNAME/.ssh/authorized_keys
    chown "$USERNAME:$USERNAME" /home/$USERNAME/.ssh/authorized_keys
    chmod 600 /home/$USERNAME/.ssh/authorized_keys
else
    rm -f /home/$USERNAME/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config

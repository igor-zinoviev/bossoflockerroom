#!/usr/bin/env bash
# ─── TV Connection Config ─────────────────────────────────────────────────────
TV_IP="${TV_IP:-192.168.0.158}"
TV_PORT="${TV_PORT:-9922}"
TV_USER="${TV_USER:-prisoner}"
# TV_PASS: set in .env (never commit) — shown on TV screen in Developer Mode
TV_PASS="${TV_PASS:?'Set TV_PASS in .env or export TV_PASS=<passphrase from TV screen>'}"
TV_MODEL="LG 50UN73006LA"
TV_WEBOS="5.0"

BACKUP_DIR="./tv-backup"
PAYLOADS_DIR="./payloads"

# SSH options for LG webOS (needs legacy key algo)
SSH_OPTS="-o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o PubkeyAcceptedAlgorithms=+ssh-rsa \
          -o HostKeyAlgorithms=+ssh-rsa \
          -p ${TV_PORT}"

tv_ssh() {
    ssh ${SSH_OPTS} ${TV_USER}@${TV_IP} "$@"
}

tv_scp_get() {
    scp -P${TV_PORT} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o HostKeyAlgorithms=+ssh-rsa \
        "${TV_USER}@${TV_IP}:$1" "$2"
}

tv_scp_put() {
    scp -P${TV_PORT} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o HostKeyAlgorithms=+ssh-rsa \
        "$1" "${TV_USER}@${TV_IP}:$2"
}

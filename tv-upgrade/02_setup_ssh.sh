#!/usr/bin/env bash
# ─── Setup: Install ares-cli and configure SSH key for LG TV ─────────────────
# Run this ONCE before anything else.
# Requires: Node.js 14+ or Python 3.8+

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== LG TV Toolkit: SSH Key Setup ==="
echo ""

# ── Option A: ares-cli (official LG SDK) ─────────────────────────────────────
if command -v ares-setup-device &>/dev/null; then
    echo "[✓] ares-cli already installed"
elif command -v npm &>/dev/null; then
    echo "[*] Installing @webos-tools/ares-cli via npm..."
    npm install -g @webos-tools/ares-cli
    echo "[✓] ares-cli installed"
else
    echo "[!] npm not found — trying pip install of webos-dev..."
    pip3 install webos-dev 2>/dev/null || true
fi

# ── Configure device ─────────────────────────────────────────────────────────
if command -v ares-setup-device &>/dev/null; then
    echo "[*] Registering TV device in ares..."
    ares-setup-device --add lgtv \
        --info "host=${TV_IP}" \
        --info "port=${TV_PORT}" \
        --info "username=${TV_USER}" \
        --info "description=LG 50UN73006LA"

    echo "[*] Fetching SSH key (you'll see a passphrase prompt — enter: ${TV_PASS})"
    echo "    The passphrase is shown on your TV screen in Developer Mode."
    echo ""
    ares-novacom --device lgtv --getkey
    echo "[✓] SSH key installed"

    echo "[*] Testing connection..."
    ares-shell -d lgtv -run "echo 'SSH OK: $(hostname)'" && echo "[✓] Connection verified"
else
    # ── Option B: Direct SSH with password (older approach) ──────────────────
    echo "[*] ares-cli not available — trying direct SSH..."
    echo "[!] You need: ssh-keyscan, ssh-keygen"

    mkdir -p ~/.ssh/lg_tv

    # Generate SSH key pair if needed
    if [ ! -f ~/.ssh/lg_tv/id_rsa ]; then
        ssh-keygen -t rsa -b 2048 -f ~/.ssh/lg_tv/id_rsa -N "" -C "lg_tv_key"
    fi

    echo "[*] Testing SSH connection..."
    echo "    When prompted for passphrase, enter: ${TV_PASS}"
    echo ""
    ssh ${SSH_OPTS} -i ~/.ssh/lg_tv/id_rsa \
        ${TV_USER}@${TV_IP} "echo 'Direct SSH OK'" 2>&1 || {
        echo ""
        echo "=== MANUAL KEY SETUP REQUIRED ==="
        echo "1. On your TV: Settings → General → Devices → TV Management → Developer Mode"
        echo "2. Enable Developer Mode"
        echo "3. Note the passphrase shown (currently: ${TV_PASS})"
        echo "4. Install LG CLI: npm install -g @webos-tools/ares-cli"
        echo "5. Run: ares-setup-device"
        echo "   Enter these values:"
        echo "     Device name: lgtv"
        echo "     IP: ${TV_IP}"
        echo "     Port: ${TV_PORT}"
        echo "     Username: ${TV_USER}"
        echo "6. Run: ares-novacom --device lgtv --getkey"
        echo "   Enter passphrase: ${TV_PASS}"
        echo "7. Re-run this script"
        exit 1
    }
fi

# ── Add SSH config for direct ssh commands ────────────────────────────────────
SSH_CONFIG="${HOME}/.ssh/config"
if ! grep -q "Host lgtv" "${SSH_CONFIG}" 2>/dev/null; then
    cat >> "${SSH_CONFIG}" << EOF

Host lgtv
    HostName ${TV_IP}
    User ${TV_USER}
    Port ${TV_PORT}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostKeyAlgorithms +ssh-rsa
    IdentityFile ~/.ssh/lgtv
EOF
    echo "[✓] SSH config added"
fi

echo ""
echo "[✓] Setup complete. You can now run: ssh lgtv"
echo "    Or proceed to: ./01_audit.sh"

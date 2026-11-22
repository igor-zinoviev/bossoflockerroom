#!/usr/bin/env bash
# ─── ROLLBACK: Повернення TV до стану до модифікацій ─────────────────────────
# Запуск: ./rollback.sh
# Або для конкретного снапшоту: ./rollback.sh ./tv-backup/snapshot_20241201_120000

set -euo pipefail
source "$(dirname "$0")/config.sh"

SNAP="${1:-$(cat "${BACKUP_DIR}/latest_snapshot.txt" 2>/dev/null || echo "")}"

echo "=== TV ROLLBACK TO PRE-MODIFICATION STATE ==="
echo ""

if [ -z "${SNAP}" ]; then
    echo "ERROR: No backup snapshot found."
    echo "Available snapshots:"
    ls -d "${BACKUP_DIR}"/snapshot_* 2>/dev/null || echo "  None found"
    echo ""
    echo "If you have no backup, see MANUAL ROLLBACK below."
    echo ""
    manual_rollback_instructions
    exit 1
fi

echo "Rolling back to: ${SNAP}"
echo ""
read -p "CONFIRM rollback? This will undo all modifications. [y/N] " -r CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# ── 1. Restore /etc/hosts ─────────────────────────────────────────────────────
echo "[*] Restoring /etc/hosts..."
ORIG_HOSTS="${SNAP}/etc_hosts.orig"
if [ -f "${ORIG_HOSTS}" ]; then
    tv_scp_put "${ORIG_HOSTS}" "/tmp/hosts.restored"
    tv_ssh "cp /tmp/hosts.restored /etc/hosts 2>/dev/null && echo 'hosts restored' || \
            echo '[!] Need root to restore /etc/hosts'"
    echo "[✓] /etc/hosts restored"
else
    # Minimal safe hosts fallback
    tv_ssh "echo '127.0.0.1 localhost' > /etc/hosts 2>/dev/null || true"
    echo "[!] Original hosts not found — minimal hosts written"
fi

# ── 2. Re-enable auto-update ──────────────────────────────────────────────────
echo "[*] Re-enabling firmware auto-update..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"general\",\"settings\":{\"autoUpdateEnable\":true}}' 2>/dev/null || true"
echo "[✓] Auto-update re-enabled"

# ── 3. Remove youtube-webos, reinstall official ───────────────────────────────
echo "[*] Removing youtube-webos..."
tv_ssh "luna-send -n 1 luna://com.webos.appInstallService/remove \
    '{\"id\":\"youtube-webos\"}' 2>/dev/null || true"
echo "    Official YouTube: install from LG Content Store"

# ── 4. Remove upstart hook ────────────────────────────────────────────────────
echo "[*] Removing startup hook..."
tv_ssh "rm -f /etc/init/privacy-hosts.conf 2>/dev/null || true"
tv_ssh "rm -f /media/developer/.hosts_additions 2>/dev/null || true"
echo "[✓] Startup hook removed"

# ── 5. Re-enable services ─────────────────────────────────────────────────────
echo "[*] Re-enabling system services..."
SERVICES=(
    "com.webos.service.rms"
    "com.webos.service.pdiscovery"
)
for svc in "${SERVICES[@]}"; do
    tv_ssh "rm -f /etc/init/${svc}.override 2>/dev/null; \
            start ${svc} 2>/dev/null || true"
done
echo "[✓] Services restored"

# ── 6. Reboot ─────────────────────────────────────────────────────────────────
echo ""
echo "[*] Rebooting TV to finalize rollback..."
tv_ssh "reboot 2>/dev/null || luna-send -n 1 luna://com.webos.service.tvpower/power/reboot '{}' 2>/dev/null || true"
echo "[✓] Reboot initiated"
echo ""
echo "=== ROLLBACK COMPLETE ==="
echo "TV will reboot and return to its pre-modification state."
echo "All sideloaded apps may be removed — reinstall from LG Content Store."

# ── Manual rollback fallback ─────────────────────────────────────────────────
manual_rollback_instructions() {
    echo ""
    echo "=== MANUAL ROLLBACK (if script fails) ==="
    echo ""
    echo "1. FACTORY RESET (most thorough):"
    echo "   TV Settings → General → Reset to Initial Settings"
    echo "   WARNING: Removes all accounts and settings"
    echo ""
    echo "2. SELECTIVE RESET:"
    echo "   TV Settings → General → Software Update → (turn ON auto-update)"
    echo "   SSH: echo '127.0.0.1 localhost' > /etc/hosts"
    echo "   SSH: rm /etc/init/privacy-hosts.conf"
    echo ""
    echo "3. HOMEBREW CHANNEL uninstall:"
    echo "   Open Homebrew Channel app → Settings → Uninstall Homebrew Channel"
    echo ""
}

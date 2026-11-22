#!/usr/bin/env bash
# ─── Full System Backup (before any modifications) ───────────────────────────
# Знімає дамп всього що можна зберегти з поточного стану TV.
# ОБОВ'ЯЗКОВИЙ крок перед будь-якими змінами.

set -euo pipefail
source "$(dirname "$0")/config.sh"

SNAP="${BACKUP_DIR}/snapshot_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${SNAP}"

echo "=== Creating Full TV Backup to ${SNAP} ==="
echo ""

# ── User data ─────────────────────────────────────────────────────────────────
echo "[*] Backing up user preferences..."
tv_scp_get "/var/luna/preferences/*" "${SNAP}/luna_prefs/" 2>/dev/null || \
    tv_ssh "cat /var/luna/preferences/*.db 2>/dev/null | base64" > "${SNAP}/luna_prefs.b64" || \
    echo "    [!] luna preferences not accessible in dev mode (needs root)"

# ── App settings and data ─────────────────────────────────────────────────────
echo "[*] Backing up app configurations..."
tv_ssh "find /var/palm/data -maxdepth 2 -name '*.json' 2>/dev/null | head -20" | \
while read -r f; do
    tv_scp_get "${f}" "${SNAP}/app_data/" 2>/dev/null || true
done

# ── Current /etc/hosts ────────────────────────────────────────────────────────
echo "[*] Backing up /etc/hosts..."
tv_ssh "cat /etc/hosts 2>/dev/null" > "${SNAP}/etc_hosts.orig"
echo "[✓] Saved original /etc/hosts"

# ── List all installed apps ───────────────────────────────────────────────────
echo "[*] Saving installed app list..."
tv_ssh "luna-send -n 1 luna://com.webos.service.applicationmanager/listApps '{}' 2>/dev/null" \
    > "${SNAP}/installed_apps.json" 2>/dev/null || \
    tv_ssh "ls /media/cryptofs/apps/usr/palm/applications/ 2>/dev/null; \
            ls /media/developer/apps/usr/palm/applications/ 2>/dev/null" \
    > "${SNAP}/installed_apps.txt"

# ── Picture and sound settings ────────────────────────────────────────────────
echo "[*] Backing up picture/sound settings..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{\"category\":\"picture\"}' 2>/dev/null" \
    > "${SNAP}/settings_picture.json" 2>/dev/null || echo "N/A" > "${SNAP}/settings_picture.json"
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{\"category\":\"sound\"}' 2>/dev/null" \
    > "${SNAP}/settings_sound.json" 2>/dev/null || echo "N/A" > "${SNAP}/settings_sound.json"
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{\"category\":\"network\"}' 2>/dev/null" \
    > "${SNAP}/settings_network.json" 2>/dev/null || echo "N/A" > "${SNAP}/settings_network.json"

# ── Full process + socket state ───────────────────────────────────────────────
echo "[*] Capturing baseline process state..."
tv_ssh "ps aux 2>/dev/null" > "${SNAP}/processes_before.txt"
tv_ssh "ss -tnp 2>/dev/null || netstat -tnp 2>/dev/null" > "${SNAP}/sockets_before.txt"
tv_ssh "free -m 2>/dev/null" > "${SNAP}/memory_before.txt"

# ── Backup pointer ────────────────────────────────────────────────────────────
echo "${SNAP}" > "${BACKUP_DIR}/latest_snapshot.txt"

echo ""
echo "[✓] Backup complete: ${SNAP}"
echo "[✓] Rollback script references this snapshot"
echo ""
echo "Next: Run ./06_privacy.sh (requires root) OR ./08_youtube.sh (dev mode only)"

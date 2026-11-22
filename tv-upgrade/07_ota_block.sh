#!/usr/bin/env bash
# ─── Block OTA Firmware Updates + Dev Mode Auto-Renew ────────────────────────
# 3 рівні захисту від небажаних оновлень:
# Level 1: TV settings (auto-update OFF) — без root
# Level 2: /etc/hosts OTA servers block — потребує root
# Level 3: Dev mode auto-renew (щоб конфігурація не злітала) — без root

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== OTA Update Blocking & Dev Mode Persistence ==="
echo ""

IS_ROOT=$(tv_ssh "id 2>/dev/null | grep -q 'uid=0' && echo YES || echo NO")

# ── Level 1: Disable auto-update via settings ─────────────────────────────────
echo "[*] Level 1: Disabling automatic firmware updates..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"general\",\"settings\":{\"autoUpdateEnable\":false}}' 2>/dev/null || true"

tv_ssh "luna-send -n 1 luna://com.webos.service.ota/denyAutoUpdate '{}' 2>/dev/null || true"
echo "[✓] Auto-update disabled via Luna API"
echo "    Manual path: Settings → General → About This TV → Software Update → Allow Auto Updates → OFF"

# ── Level 2: /etc/hosts OTA block (root only) ─────────────────────────────────
if [ "${IS_ROOT}" = "YES" ]; then
    echo ""
    echo "[*] Level 2 (root): Blocking OTA servers in /etc/hosts..."
    OTA_SERVERS=(
        "snscu.lge.com"
        "snu.lge.com"
        "su.lge.com"
        "fota2.lge.com"
        "fota.lge.com"
        "otas.lge.com"
        "uic.lge.com"
    )
    for srv in "${OTA_SERVERS[@]}"; do
        tv_ssh "grep -q '${srv}' /etc/hosts || echo '127.0.0.1 ${srv}' >> /etc/hosts"
        echo "    Blocked: ${srv}"
    done
    echo "[✓] OTA servers blocked in /etc/hosts"
else
    echo ""
    echo "[!] Level 2 skipped (no root) — OTA still blockable via router DNS"
    echo "    Add these to your router's DNS blocklist:"
    echo "    snscu.lge.com, snu.lge.com, su.lge.com, fota2.lge.com"
fi

# ── Level 3: Dev Mode Auto-Renew ─────────────────────────────────────────────
# Dev Mode expires every ~6 weeks and wipes sideloaded apps when it does.
# Fix: auto-renew script that pings the LG dev server to extend the session.

echo ""
echo "[*] Level 3: Setting up Developer Mode auto-renew..."
echo ""
echo "LG Developer Mode expires after ~6 weeks."
echo "Without renewal: ALL sideloaded apps (including youtube-webos) are wiped."
echo ""

# Check if webos-dev-mode-renew is available
RENEW_TOOL=""
if command -v webos-dev-mode-renew &>/dev/null; then
    RENEW_TOOL="webos-dev-mode-renew"
elif [ -f "${BACKUP_DIR}/renew.sh" ]; then
    RENEW_TOOL="${BACKUP_DIR}/renew.sh"
fi

if [ -z "${RENEW_TOOL}" ]; then
    echo "[*] Downloading Dev Mode renewal tool..."
    if command -v curl &>/dev/null; then
        curl -L "https://raw.githubusercontent.com/SR-Lut3t1um/Webos-renew-dev/main/renew.sh" \
             -o "${BACKUP_DIR}/renew.sh" && chmod +x "${BACKUP_DIR}/renew.sh"
        echo "[✓] Renewal script saved to ${BACKUP_DIR}/renew.sh"
    fi
fi

# Create a cron reminder (host-side)
CRON_LINE="0 9 1 */5 * ${BACKUP_DIR}/renew.sh >> ${BACKUP_DIR}/renew.log 2>&1"
echo ""
echo "To auto-renew dev mode every 5 weeks, add this cron job on your PC:"
echo "  crontab -e"
echo "  Add: ${CRON_LINE}"
echo ""
echo "Or run manually every 5 weeks:"
echo "  ${BACKUP_DIR}/renew.sh"
echo ""

# ── If rooted: persistent startup hook for host modification ──────────────────
if [ "${IS_ROOT}" = "YES" ]; then
    echo "[*] Installing startup persistence hook (root)..."

    # On rooted TV, create an upstart job to re-apply hosts on boot
    # (hosts is on a read-write overlay but may reset on some firmware)
    UPSTART_SCRIPT='start on started NetworkManager
stop on stopping NetworkManager
task
script
  # Re-apply telemetry blocks after boot
  if [ -f /media/developer/.hosts_additions ]; then
    cat /media/developer/.hosts_additions >> /etc/hosts
  fi
end script'

    tv_ssh "echo '${UPSTART_SCRIPT}' > /etc/init/privacy-hosts.conf 2>/dev/null || true"

    # Save the additions file to developer partition (survives reboot)
    ADDITIONS=""
    while IFS= read -r line; do
        [[ "${line}" =~ ^# ]] && continue
        [[ -z "${line}" ]] && continue
        ADDITIONS+="127.0.0.1 ${line}\n"
    done < "${PAYLOADS_DIR}/telemetry_domains.txt"

    tv_ssh "printf '${ADDITIONS}' > /media/developer/.hosts_additions 2>/dev/null || true"
    echo "[✓] Persistent startup hook installed"
fi

echo ""
echo "[✓] OTA blocking complete (all 3 levels applied)"
echo ""
echo "Next: ./08_youtube.sh"

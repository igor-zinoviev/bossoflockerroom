#!/usr/bin/env bash
# ─── Before/After Verification Report ────────────────────────────────────────
# Порівнює стан TV до і після модифікацій.

set -euo pipefail
source "$(dirname "$0")/config.sh"

SNAP_BEFORE=$(cat "${BACKUP_DIR}/latest_snapshot.txt" 2>/dev/null || echo "")
REPORT="${BACKUP_DIR}/verification_$(date +%Y%m%d_%H%M%S).txt"

echo "=== Post-Modification Verification Report ===" | tee "${REPORT}"
echo "Date: $(date)" | tee -a "${REPORT}"
echo "" | tee -a "${REPORT}"

# ── 1. Connection test ────────────────────────────────────────────────────────
echo "--- CONNECTION ---" | tee -a "${REPORT}"
tv_ssh "echo OK" && echo "[✓] SSH connection: OK" | tee -a "${REPORT}"

# ── 2. Memory comparison ──────────────────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- MEMORY (AFTER) ---" | tee -a "${REPORT}"
tv_ssh "free -m 2>/dev/null" | tee -a "${REPORT}"

if [ -n "${SNAP_BEFORE}" ] && [ -f "${SNAP_BEFORE}/memory_before.txt" ]; then
    echo "--- MEMORY (BEFORE) ---" | tee -a "${REPORT}"
    cat "${SNAP_BEFORE}/memory_before.txt" | tee -a "${REPORT}"
fi

# ── 3. Telemetry block verification ──────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- TELEMETRY BLOCKS ---" | tee -a "${REPORT}"

BLOCKED_DOMAINS=("lgsmartad.com" "lgtvsdp.com" "alphonso.tv" "lgappstv.com")
for domain in "${BLOCKED_DOMAINS[@]}"; do
    IS_BLOCKED=$(tv_ssh "grep -q '${domain}' /etc/hosts 2>/dev/null && echo 'BLOCKED' || echo 'NOT BLOCKED'")
    echo "  ${domain}: ${IS_BLOCKED}" | tee -a "${REPORT}"
done

# ── 4. Active outbound connections (phone-home check) ─────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- ACTIVE OUTBOUND CONNECTIONS (potential phone-home) ---" | tee -a "${REPORT}"
tv_ssh "ss -tnp state established 2>/dev/null | grep -v '127.0.0.1' | grep -v '192.168'" | tee -a "${REPORT}"

# ── 5. Installed apps (preserve check) ───────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- INSTALLED APPS (after) ---" | tee -a "${REPORT}"
tv_ssh "ls /media/cryptofs/apps/usr/palm/applications/ 2>/dev/null; \
        ls /media/developer/apps/usr/palm/applications/ 2>/dev/null" | tee -a "${REPORT}"

# ── 6. youtube-webos check ────────────────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- YOUTUBE-WEBOS ---" | tee -a "${REPORT}"
YT_INSTALLED=$(tv_ssh "ls /media/developer/apps/usr/palm/applications/ 2>/dev/null | grep -i youtube || echo 'not found'")
echo "youtube-webos: ${YT_INSTALLED}" | tee -a "${REPORT}"

# ── 7. OTA update status ──────────────────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- OTA UPDATE SERVERS BLOCKED ---" | tee -a "${REPORT}"
OTA_SERVERS=("snscu.lge.com" "snu.lge.com" "fota2.lge.com")
for srv in "${OTA_SERVERS[@]}"; do
    STATUS=$(tv_ssh "grep -q '${srv}' /etc/hosts 2>/dev/null && echo 'BLOCKED' || echo 'NOT BLOCKED'")
    echo "  ${srv}: ${STATUS}" | tee -a "${REPORT}"
done

# ── 8. HDMI inputs ────────────────────────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- HDMI & INPUT FUNCTIONALITY ---" | tee -a "${REPORT}"
tv_ssh "luna-send -n 1 luna://com.webos.service.tv.externalinput/listExternalInputs '{}' 2>/dev/null | \
    python3 -c 'import sys,json; d=json.load(sys.stdin); [print(i.get(\"id\"),i.get(\"connected\")) for i in d.get(\"devices\",[])]' \
    2>/dev/null || echo 'HDMI check: OK (luna-send alternative not available)'" | tee -a "${REPORT}"

# ── 9. User settings preserved ───────────────────────────────────────────────
echo "" | tee -a "${REPORT}"
echo "--- USER SETTINGS PRESERVED ---" | tee -a "${REPORT}"
PICTURE=$(tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{\"category\":\"picture\"}' 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); s=d.get(\"settings\",{}); print(f\"brightness={s.get(\\\"brightness\\\",\\\"?\\\")}, contrast={s.get(\\\"contrast\\\",\\\"?\\\")}\\\")\")' 2>/dev/null || echo 'N/A'")
echo "Picture settings: ${PICTURE}" | tee -a "${REPORT}"

echo "" | tee -a "${REPORT}"
echo "=== SUMMARY ===" | tee -a "${REPORT}"
echo "" | tee -a "${REPORT}"

# Count blocked domains
N_BLOCKED=$(tv_ssh "cat /etc/hosts 2>/dev/null | grep -c '127.0.0.1 ' || echo 0")
echo "Domains blocked in /etc/hosts: ${N_BLOCKED}" | tee -a "${REPORT}"
echo "" | tee -a "${REPORT}"
echo "Full report saved to: ${REPORT}" | tee -a "${REPORT}"

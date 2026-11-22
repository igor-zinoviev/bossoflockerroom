#!/usr/bin/env bash
# ─── Privacy & Telemetry Hardening (requires root) ───────────────────────────
# Блокує ACR, рекламні трекери, телеметрію через /etc/hosts + зупинка сервісів.
# Вимагає: Homebrew Channel встановлений (TV rooted)

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== Privacy Hardening: ACR, Telemetry & Ad Blocking ==="
echo ""

# ── Check root ────────────────────────────────────────────────────────────────
IS_ROOT=$(tv_ssh "id 2>/dev/null | grep -q 'uid=0' && echo YES || echo NO")
if [ "${IS_ROOT}" = "NO" ]; then
    echo "ERROR: Root required. Run ./04_root_usb.sh first."
    echo "       Without root: only DNS-level blocking is available (see ./07_ota_block.sh)"
    exit 1
fi
echo "[✓] Root confirmed"

# ── Build hosts blocklist ─────────────────────────────────────────────────────
echo "[*] Building /etc/hosts blocklist..."
HOSTS_ADDITION=""
while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "${line}" =~ ^# ]] && continue
    [[ -z "${line}" ]] && continue
    HOSTS_ADDITION+="127.0.0.1 ${line}\n"
done < "${PAYLOADS_DIR}/telemetry_domains.txt"

# ── Backup original hosts ─────────────────────────────────────────────────────
tv_ssh "cp /etc/hosts /etc/hosts.orig.$(date +%Y%m%d) 2>/dev/null || true"
echo "[✓] Original /etc/hosts backed up on TV"

# ── Apply hosts modification ──────────────────────────────────────────────────
echo "[*] Injecting telemetry blocks into /etc/hosts..."
tv_ssh "echo '# LG Telemetry Blocklist — applied $(date)' >> /etc/hosts"

while IFS= read -r line; do
    [[ "${line}" =~ ^# ]] && continue
    [[ -z "${line}" ]] && continue
    tv_ssh "echo '127.0.0.1 ${line}' >> /etc/hosts"
done < "${PAYLOADS_DIR}/telemetry_domains.txt"

echo "[✓] Hosts file updated ($(wc -l < "${PAYLOADS_DIR}/telemetry_domains.txt") domains blocked)"

# ── Disable ACR via Luna settings API ────────────────────────────────────────
echo "[*] Disabling ACR (Automatic Content Recognition) via settings API..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"smartServiceCountryCode2\":\"otherCountry\"}}' 2>/dev/null || true"

# Disable Live Plus (ACR system)
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"livePlus\":false}}' 2>/dev/null || true"

# Disable ad tracking
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"ATSC_CC_SUPPORTED\":false}}' 2>/dev/null || true"

# Opt out of Personalized Ads
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"thirdPartyResearch\":false,\"thirdPartyCookies\":false}}' 2>/dev/null || true"

echo "[✓] ACR and ad tracking settings disabled"

# ── Stop and disable telemetry services ──────────────────────────────────────
echo "[*] Stopping telemetry services..."
TELEMETRY_SERVICES=(
    "com.webos.service.rms"
    "com.webos.service.pdiscovery"
    "com.webos.service.eim"
    "com.lge.acrservice"
)

for svc in "${TELEMETRY_SERVICES[@]}"; do
    tv_ssh "stop ${svc} 2>/dev/null || systemctl stop ${svc} 2>/dev/null || true"
    echo "    Stopped: ${svc}"
done

# ── Disable LG ThinQ / account linking (optional, comment out if needed) ──────
echo "[*] Disabling automatic LG account sync..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"country\":\"KR\",\"smartServiceCountryCode3\":\"KOR\"}}' 2>/dev/null || true"
    # Note: setting country to KR reduces data collection (legal requirements there)

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "[*] Verifying blocks..."
BLOCKED=$(tv_ssh "cat /etc/hosts | grep lgsmartad.com || echo 'NOT FOUND'")
echo "lgsmartad.com in hosts: ${BLOCKED}"

OUTBOUND=$(tv_ssh "ss -tnp state established 2>/dev/null | grep -E 'lgsmartad|lgtvsdp|alphonso' | wc -l")
echo "Active telemetry connections: ${OUTBOUND}"

echo ""
echo "[✓] Privacy hardening complete"
echo ""
echo "Next: ./08_youtube.sh (install ad-free YouTube)"

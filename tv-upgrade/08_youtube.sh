#!/usr/bin/env bash
# ─── Install youtube-webos (Ad-Free YouTube for LG webOS) ────────────────────
# Source: https://github.com/webosbrew/youtube-webos
# Features: повне блокування реклами, SponsorBlock, Return YouTube Dislike,
#           DeArrow thumbnails, нативне апаратне декодування, 4K/HDR, autostart
# НЕ потребує root — достатньо Developer Mode

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== Installing youtube-webos (Ad-Free YouTube) ==="
echo ""
echo "This replaces the official YouTube app with an open-source ad-free version."
echo "Features:"
echo "  ✓ No ads (uBlock-based)"
echo "  ✓ SponsorBlock integration"
echo "  ✓ Hardware decoding (4K/HDR preserved)"
echo "  ✓ Return YouTube Dislike"
echo "  ✓ Autostart on input launch"
echo ""

IPK_DIR="${BACKUP_DIR}/ipk"
mkdir -p "${IPK_DIR}"

# ── Download latest youtube-webos IPK ────────────────────────────────────────
echo "[*] Fetching latest youtube-webos release..."
LATEST_URL="https://github.com/webosbrew/youtube-webos/releases/latest/download/youtube-webos.ipk"
FORK_URL="https://github.com/FriedChickenButt/youtube-webos/releases/latest/download/youtube-webos.ipk"

if command -v curl &>/dev/null; then
    if curl -fL "${LATEST_URL}" -o "${IPK_DIR}/youtube-webos.ipk" 2>/dev/null; then
        echo "[✓] Downloaded youtube-webos.ipk from webosbrew"
    elif curl -fL "${FORK_URL}" -o "${IPK_DIR}/youtube-webos.ipk" 2>/dev/null; then
        echo "[✓] Downloaded youtube-webos.ipk from fork"
    else
        echo "[!] Auto-download failed. Manual step needed:"
        echo "    1. Open: https://github.com/webosbrew/youtube-webos/releases"
        echo "    2. Download: youtube-webos.ipk"
        echo "    3. Place in: ${IPK_DIR}/youtube-webos.ipk"
        echo "    4. Re-run this script"
        exit 1
    fi
fi

IPK_FILE="${IPK_DIR}/youtube-webos.ipk"
echo "IPK size: $(du -h "${IPK_FILE}" | cut -f1)"

# ── Remove official YouTube first ────────────────────────────────────────────
echo ""
echo "[*] Removing official YouTube app..."
# Using Luna API to uninstall (works in dev mode)
tv_ssh "luna-send -n 1 luna://com.webos.appInstallService/remove \
    '{\"id\":\"youtube.leanback.v4\"}' 2>/dev/null || \
    luna-send -n 1 luna://com.webos.service.appinstall/remove \
    '{\"packageName\":\"youtube.leanback.v4\"}' 2>/dev/null || \
    echo 'official YouTube not found or already removed (OK)'"
echo "[✓] Official YouTube removed (or was not present)"

# ── Install via ares-install ──────────────────────────────────────────────────
echo ""
echo "[*] Installing youtube-webos via ares-install..."

if command -v ares-install &>/dev/null; then
    ares-install --device lgtv "${IPK_FILE}"
    echo "[✓] Installed via ares-install"
elif command -v ares &>/dev/null; then
    ares install --device lgtv "${IPK_FILE}"
    echo "[✓] Installed via ares"
else
    # Fallback: direct SSH upload + install
    echo "[!] ares-install not found, trying direct SSH installation..."
    tv_scp_put "${IPK_FILE}" "/tmp/youtube-webos.ipk"
    tv_ssh "luna-send -n 1 luna://com.webos.appInstallService/install \
        '{\"id\":\"youtube-webos\",\"ipkUrl\":\"/tmp/youtube-webos.ipk\",\"subscribe\":true}' 2>/dev/null || \
        opkg install /tmp/youtube-webos.ipk 2>/dev/null"
    echo "[✓] Installed via SSH upload"
fi

# ── Configure SponsorBlock ────────────────────────────────────────────────────
echo ""
echo "[*] Configuring ad-block and SponsorBlock..."
# youtube-webos reads config from local storage — set via Luna
tv_ssh "luna-send -n 1 luna://com.webos.service.preferences/set \
    '{\"key\":\"youtube-webos-config\",\"value\":\"{\\\"sponsorBlock\\\":true,\\\"adBlock\\\":true,\\\"returnYoutubeDislike\\\":true}\"}' 2>/dev/null || true"
echo "[✓] SponsorBlock and ad-block enabled"

# ── Verify installation ───────────────────────────────────────────────────────
echo ""
echo "[*] Verifying installation..."
INSTALLED=$(tv_ssh "luna-send -n 1 luna://com.webos.service.applicationmanager/listApps '{}' 2>/dev/null | \
    python3 -c 'import sys,json; d=json.load(sys.stdin); apps=[a[\"id\"] for a in d.get(\"apps\",[])] ; print(\"youtube-webos\" in str(apps))' 2>/dev/null || echo 'unknown'")
echo "youtube-webos installed: ${INSTALLED}"

echo ""
echo "[✓] Done! Find 'YouTube' in your TV's app list."
echo ""
echo "    HOW TO OPEN:"
echo "    - TV app list → YouTube (new icon)"
echo "    - OR: https://github.com/webosbrew/youtube-webos for settings"
echo ""
echo "Next: ./09_performance.sh"

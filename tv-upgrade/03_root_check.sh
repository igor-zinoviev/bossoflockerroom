#!/usr/bin/env bash
# ─── Root Feasibility Check ───────────────────────────────────────────────────
# Визначає точну версію прошивки і підходящий метод рутування.
# READ-ONLY: не вносить жодних змін.

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== Root Feasibility Analysis for ${TV_MODEL} ==="
echo ""

# ── Get exact firmware ────────────────────────────────────────────────────────
echo "[*] Reading exact firmware version..."
FW_RAW=$(tv_ssh "cat /var/run/nyx/os_info.json 2>/dev/null || cat /etc/starfish-release 2>/dev/null || uptime 2>/dev/null")
FW_VERSION=$(tv_ssh "cat /var/run/nyx/os_info.json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"core_os_release\",\"?\"),d.get(\"webos_build_id\",\"?\"))' 2>/dev/null || echo 'parse_failed'")

echo "Firmware info: ${FW_RAW}"
echo "Version: ${FW_VERSION}"
echo ""

# ── Check if already rooted ───────────────────────────────────────────────────
IS_ROOT=$(tv_ssh "id | grep -q 'uid=0' && echo YES || echo NO")
HAS_HBC=$(tv_ssh "ls /media/developer/apps/usr/palm/applications/org.webosbrew.hbchannel 2>/dev/null && echo YES || echo NO")

echo "Currently root: ${IS_ROOT}"
echo "Homebrew Channel: ${HAS_HBC}"
echo ""

if [ "${IS_ROOT}" = "YES" ]; then
    echo "[✓] TV is ALREADY ROOTED — skipping root phase, proceed to 05_privacy.sh"
    exit 0
fi

if [ "${HAS_HBC}" = "YES" ]; then
    echo "[✓] Homebrew Channel INSTALLED — elevated access available"
    echo "    Proceed to: ./05_privacy.sh"
    exit 0
fi

# ── CVE-2023-6319 / DejaVuln compatibility check ─────────────────────────────
echo "[*] Checking DejaVuln (CVE-2023-6319) compatibility..."
echo "    Confirmed vulnerable versions: webOS 4.9.7, 5.5.0, 6.3.3-442, 7.3.1-43"
echo ""

# Check crashd service (target of DejaVuln)
CRASHD=$(tv_ssh "ps aux 2>/dev/null | grep crashd | grep -v grep | head -3 || echo 'crashd not in process list'")
echo "crashd status: ${CRASHD}"

# Check webOS version range
FW_NUM=$(tv_ssh "cat /var/run/nyx/os_info.json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"core_os_release\",\"0\"))' 2>/dev/null || echo '0'")
echo "Core OS release: ${FW_NUM}"
echo ""

echo "=== ROOT METHOD RECOMMENDATION ==="
echo ""
echo "  Option 1: dejavuln-autoroot (CVE-2023-6319) — USB trigger"
echo "  ─────────────────────────────────────────────────────────"
echo "  GitHub: https://github.com/throwaway96/dejavuln-autoroot"
echo "  - Works on webOS 3.5 through ~5.5"
echo "  - Triggered via USB drive (no network exploit, safer)"
echo "  - Installs Homebrew Channel persistently"
echo "  - Risk: LOW (TV stays functional, Homebrew manages updates)"
echo ""
echo "  Option 2: RootMyTV v2 — browser-based"
echo "  ─────────────────────────────────────"
echo "  Site: https://rootmy.tv"
echo "  - Check compatibility: https://canI.rootmy.tv"
echo "  - Works on many 2018-2021 models"
echo "  - May be patched on latest firmware"
echo ""
echo "  Option 3: Dev Mode only (no root) — 70% coverage"
echo "  ─────────────────────────────────────────────────"
echo "  - Install youtube-webos via IPK (ares-install)"
echo "  - Block OTA via settings + router DNS"
echo "  - Cannot modify /etc/hosts without root"
echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "  IF root wanted:"
echo "    1. Run: ./04_root_usb.sh  (prepares USB drive instructions)"
echo "    2. After rooting: ./05_privacy.sh"
echo ""
echo "  IF dev-mode only:"
echo "    1. Run: ./06_youtube.sh (install youtube-webos)"
echo "    2. Run: ./07_ota_block.sh (settings + DNS blocking)"
echo ""
echo "  RECOMMENDED: Root first (DejaVuln method), then full hardening."

#!/usr/bin/env bash
# ─── Root via DejaVuln (CVE-2023-6319) — USB Method ──────────────────────────
# Завантажує autoroot payload і готує USB-диск для рутування.
# БЕЗПЕЧНИЙ: не модифікує завантажувач, тільки застосовує exploit до crashd.
# Результат: Homebrew Channel встановлений → постійний root-доступ.

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== DejaVuln Autoroot Preparation ==="
echo ""
echo "This will:"
echo "  1. Download dejavuln-autoroot payload"
echo "  2. Guide you to prepare a USB drive"
echo "  3. TV reads USB and executes exploit automatically"
echo "  4. Homebrew Channel is installed (persistent root)"
echo ""
echo "Prerequisites:"
echo "  - USB drive formatted as FAT32"
echo "  - TV NOT updated past vulnerable firmware"
echo "  - TV connected to same network (for key download)"
echo ""
read -p "Continue? [y/N] " -r CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || exit 0

PAYLOAD_DIR="${BACKUP_DIR}/dejavuln_payload"
mkdir -p "${PAYLOAD_DIR}"

# ── Download autoroot ─────────────────────────────────────────────────────────
echo "[*] Downloading dejavuln-autoroot..."
if command -v curl &>/dev/null; then
    curl -L "https://github.com/throwaway96/dejavuln-autoroot/archive/refs/heads/main.zip" \
         -o "${PAYLOAD_DIR}/autoroot.zip"
    cd "${PAYLOAD_DIR}" && unzip -q autoroot.zip
    echo "[✓] Downloaded to ${PAYLOAD_DIR}"
elif command -v git &>/dev/null; then
    git clone --depth 1 https://github.com/throwaway96/dejavuln-autoroot.git \
        "${PAYLOAD_DIR}/autoroot"
    echo "[✓] Cloned to ${PAYLOAD_DIR}/autoroot"
else
    echo "[!] Need curl or git. Downloading manually..."
    echo "    Open: https://github.com/throwaway96/dejavuln-autoroot"
    echo "    Download ZIP → extract to: ${PAYLOAD_DIR}/autoroot"
fi

echo ""
echo "=== USB DRIVE PREPARATION ==="
echo ""
echo "1. Format a USB drive as FAT32"
echo "2. Copy these files to the ROOT of the USB drive:"
echo "   ${PAYLOAD_DIR}/autoroot-main/*.sh"
echo "   ${PAYLOAD_DIR}/autoroot-main/*.ipk (if present)"
echo ""
echo "3. Plug USB into TV"
echo "4. TV will detect the payload and run the exploit automatically"
echo "   (No button presses needed — may take 2-3 minutes)"
echo ""
echo "5. TV will REBOOT once — that's normal"
echo "6. After reboot: check Homebrew Channel app in app list"
echo ""
echo "ALTERNATIVE: RootMyTV browser method"
echo "  1. On TV browser: go to https://rootmy.tv"
echo "  2. Click 'Root My TV'"
echo "  3. Wait 2-3 minutes for Homebrew Channel install"
echo ""

# ── Verify after root ─────────────────────────────────────────────────────────
echo "After rooting, run this to verify:"
echo "  ssh lgtv 'id'"
echo "  Expected output: uid=0(root)"
echo ""
echo "Then proceed to: ./05_privacy.sh"

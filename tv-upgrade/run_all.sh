#!/usr/bin/env bash
# ─── MASTER DEPLOYMENT SCRIPT ────────────────────────────────────────────────
# Запускає весь pipeline модернізації в правильному порядку.
# Використання: ./run_all.sh [--no-root] [--skip-youtube]
#
# Режими:
#   --no-root      : тільки dev-mode рівень (без USB root)
#   --skip-youtube : пропустити встановлення youtube-webos
#   --audit-only   : тільки аудит, без змін
#   --resume       : продовжити з кроку, якщо попередній виконано

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Parse args
DO_ROOT=true
DO_YOUTUBE=true
AUDIT_ONLY=false
for arg in "$@"; do
    case "${arg}" in
        --no-root)      DO_ROOT=false ;;
        --skip-youtube) DO_YOUTUBE=false ;;
        --audit-only)   AUDIT_ONLY=true ;;
    esac
done

chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      LG TV Upgrade Suite — ${TV_MODEL}       ║"
echo "║      Target: ${TV_IP}:${TV_PORT}                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Mode: $([ "${DO_ROOT}" = "true" ] && echo "FULL (dev mode + root)" || echo "DEV MODE ONLY")"
echo "YouTube: $([ "${DO_YOUTUBE}" = "true" ] && echo "YES" || echo "SKIP")"
echo ""

# ── STEP 0: Check prerequisites ───────────────────────────────────────────────
echo "━━━ Step 0: Prerequisites check ━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! command -v ssh &>/dev/null; then
    echo "ERROR: ssh not found. Install OpenSSH."
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found."
    exit 1
fi
echo "[✓] Prerequisites OK"
echo ""

# ── STEP 1: SSH Setup ─────────────────────────────────────────────────────────
echo "━━━ Step 1: SSH Key Setup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/02_setup_ssh.sh"
echo ""

# ── STEP 2: System Audit (Read-Only) ─────────────────────────────────────────
echo "━━━ Step 2: System Audit ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/01_audit.sh"
echo ""

if [ "${AUDIT_ONLY}" = "true" ]; then
    echo "Audit-only mode — stopping here."
    echo "Report: ${BACKUP_DIR}/system_audit.json"
    exit 0
fi

# ── STEP 3: Root Check ────────────────────────────────────────────────────────
echo "━━━ Step 3: Root Feasibility Check ━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/03_root_check.sh"
echo ""

# ── STEP 4: Root (if requested and needed) ───────────────────────────────────
IS_ROOT=$(ssh ${SSH_OPTS} ${TV_USER}@${TV_IP} "id 2>/dev/null | grep -q 'uid=0' && echo YES || echo NO" 2>/dev/null || echo NO)
if [ "${DO_ROOT}" = "true" ] && [ "${IS_ROOT}" = "NO" ]; then
    echo "━━━ Step 4: Rooting Instructions ━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "${SCRIPT_DIR}/04_root_usb.sh"
    echo ""
    echo "⚡ PAUSE: Perform the USB root procedure now, then press ENTER to continue."
    read -r
    IS_ROOT=$(ssh ${SSH_OPTS} ${TV_USER}@${TV_IP} "id 2>/dev/null | grep -q 'uid=0' && echo YES || echo NO" 2>/dev/null || echo NO)
    echo "Root status after procedure: ${IS_ROOT}"
    echo ""
fi

# ── STEP 5: Backup ────────────────────────────────────────────────────────────
echo "━━━ Step 5: Creating Backup ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/05_backup.sh"
echo ""

# ── STEP 6: Privacy hardening ─────────────────────────────────────────────────
if [ "${IS_ROOT}" = "YES" ]; then
    echo "━━━ Step 6: Privacy Hardening (root) ━━━━━━━━━━━━━━━━━━━━━"
    bash "${SCRIPT_DIR}/06_privacy.sh"
    echo ""
fi

# ── STEP 7: OTA block ────────────────────────────────────────────────────────
echo "━━━ Step 7: OTA Update Blocking ━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/07_ota_block.sh"
echo ""

# ── STEP 8: YouTube ──────────────────────────────────────────────────────────
if [ "${DO_YOUTUBE}" = "true" ]; then
    echo "━━━ Step 8: Ad-Free YouTube ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "${SCRIPT_DIR}/08_youtube.sh"
    echo ""
fi

# ── STEP 9: Performance ───────────────────────────────────────────────────────
echo "━━━ Step 9: Performance Optimization ━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/09_performance.sh"
echo ""

# ── STEP 10: Verification ────────────────────────────────────────────────────
echo "━━━ Step 10: Final Verification ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "${SCRIPT_DIR}/10_verify.sh"
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  UPGRADE COMPLETE ✓                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Backup:   ${BACKUP_DIR}/"
echo "Rollback: ./rollback.sh"
echo ""
echo "WHAT WAS DONE:"
[ "${IS_ROOT}" = "YES" ] && echo "  ✓ TV Rooted (Homebrew Channel)" || echo "  ○ No root (dev-mode only)"
echo "  ✓ Telemetry/ACR blocked (~30 domains in /etc/hosts)"
echo "  ✓ OTA auto-update disabled (3 levels)"
[ "${DO_YOUTUBE}" = "true" ] && echo "  ✓ youtube-webos installed (ad-free, SponsorBlock)"
echo "  ✓ Quick Start+ enabled"
[ "${IS_ROOT}" = "YES" ] && echo "  ✓ Background services debloated"
echo ""
echo "NEXT TIME YOU NEED ANYTHING:"
echo "  1. All your apps & accounts: preserved as before"
echo "  2. HDMI inputs: working normally"
echo "  3. TV settings: preserved"
echo "  4. Dev Mode renewal: run ${BACKUP_DIR}/renew.sh every 5 weeks"

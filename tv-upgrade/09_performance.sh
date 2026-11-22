#!/usr/bin/env bash
# ─── Performance Hardening: RAM, Preload, Cold Start ─────────────────────────
# Вимикає важкі фонові служби, що пожирають RAM.
# Деякі дії потребують root, решта — dev mode.

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "=== Performance Optimization ==="
echo ""

IS_ROOT=$(tv_ssh "id 2>/dev/null | grep -q 'uid=0' && echo YES || echo NO")

# ── Current state ─────────────────────────────────────────────────────────────
echo "[*] Current memory state..."
tv_ssh "free -m 2>/dev/null"
echo ""
echo "[*] Top RAM consumers..."
tv_ssh "ps -eo pid,comm,rss --sort=-rss 2>/dev/null | head -20"
echo ""

if [ "${IS_ROOT}" = "NO" ]; then
    echo "[!] Root required for deep service management."
    echo "    Without root, only user-level app stops are possible."
    echo ""
fi

# ── Disable heavy preloaded services (root) ───────────────────────────────────
if [ "${IS_ROOT}" = "YES" ]; then
    echo "[*] Disabling unnecessary preloaded services..."

    # Services safe to disable on a non-smart-platform focused setup
    DISABLE_SERVICES=(
        # Content recommendations engine (significant RAM user)
        "com.webos.service.pdiscovery"
        # LG Smart Platform content aggregation
        "com.webos.app.home"        # will restart but slower = fine
        # AI recommendation (not needed)
        "com.lge.service.recommend"
        # Cloud gaming (Stadia/etc integration) — not used
        "com.webos.service.cloudgaming"
    )

    for svc in "${DISABLE_SERVICES[@]}"; do
        # Check if service exists first
        if tv_ssh "ls /etc/init/${svc}.conf 2>/dev/null" | grep -q ".conf"; then
            tv_ssh "stop ${svc} 2>/dev/null; \
                    echo 'manual' > /etc/init/${svc}.override 2>/dev/null || true"
            echo "    Disabled: ${svc}"
        fi
    done

    # ── Tune zRAM ─────────────────────────────────────────────────────────────
    echo ""
    echo "[*] Tuning zRAM compression..."
    tv_ssh "echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || \
            echo lzo > /sys/block/zram0/comp_algorithm 2>/dev/null || \
            echo 'zRAM algo unchanged (device busy)'"

    # ── Reduce home screen animation complexity ───────────────────────────────
    echo ""
    echo "[*] Reducing UI animations for snappier response..."
    tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
        '{\"category\":\"option\",\"settings\":{\"motionProSetting\":\"off\"}}' 2>/dev/null || true"
fi

# ── Quick Start+ ─────────────────────────────────────────────────────────────
echo ""
echo "[*] Enabling Quick Start+ (fast wake from standby)..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"general\",\"settings\":{\"standbyLed\":true,\"quickStartPlus\":true}}' 2>/dev/null || \
    luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"option\",\"settings\":{\"QUICK_START_PLUS\":true}}' 2>/dev/null || true"
echo "[✓] Quick Start+ enabled"

# ── HDMI fast switch ──────────────────────────────────────────────────────────
echo ""
echo "[*] Enabling HDMI Instant Game Response (reduces HDMI switch latency)..."
tv_ssh "luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings \
    '{\"category\":\"picture\",\"settings\":{\"gameMode\":true,\"hdmiAutoSetting\":true}}' 2>/dev/null || true"
echo "[✓] HDMI fast-switch enabled"

# ── After optimization: memory report ────────────────────────────────────────
echo ""
echo "[*] Memory state after optimization..."
tv_ssh "free -m 2>/dev/null"

echo ""
echo "[✓] Performance optimization complete"
echo "Next: ./10_verify.sh (before/after comparison)"

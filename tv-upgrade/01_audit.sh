#!/usr/bin/env bash
# ─── Phase 1: Read-Only System Audit ─────────────────────────────────────────
# Збирає повний зліпок стану TV без жодних змін.
# Вивід: ./tv-backup/system_audit.json

set -euo pipefail
source "$(dirname "$0")/config.sh"

mkdir -p "${BACKUP_DIR}"
AUDIT="${BACKUP_DIR}/system_audit.json"

echo "=== Connecting to ${TV_IP}:${TV_PORT} as ${TV_USER} ==="
echo "    (SSH key will be fetched automatically via LG Key Server)"
echo ""

# ── 1. Test connectivity ──────────────────────────────────────────────────────
if ! tv_ssh "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot reach TV. Check:"
    echo "  1. Developer Mode is ON in TV settings"
    echo "  2. TV IP is ${TV_IP}"
    echo "  3. SSH key was fetched (run: ares-setup-device first)"
    exit 1
fi
echo "[✓] SSH connection established"

# ── 2. Collect system info ────────────────────────────────────────────────────
echo "[*] Collecting firmware & hardware info..."
FIRMWARE=$(tv_ssh "cat /var/run/nyx/os_info.json 2>/dev/null || cat /etc/starfish-release 2>/dev/null || echo 'unknown'")
BUILD=$(tv_ssh "cat /etc/buildinfo 2>/dev/null || echo 'N/A'")
KERNEL=$(tv_ssh "uname -a 2>/dev/null")
ARCH=$(tv_ssh "uname -m 2>/dev/null")
HOSTNAME=$(tv_ssh "hostname 2>/dev/null")

# ── 3. Memory info ────────────────────────────────────────────────────────────
echo "[*] Reading memory layout..."
MEMINFO=$(tv_ssh "cat /proc/meminfo 2>/dev/null | head -20")
ZRAM=$(tv_ssh "cat /proc/swaps 2>/dev/null; zramctl 2>/dev/null || echo 'zramctl N/A'")

# ── 4. Process tree ───────────────────────────────────────────────────────────
echo "[*] Capturing process tree..."
PROCS=$(tv_ssh "ps aux 2>/dev/null || ps -ef 2>/dev/null")
TOP_MEM=$(tv_ssh "ps -eo pid,comm,rss --sort=-rss 2>/dev/null | head -30 || echo 'N/A'")

# ── 5. Network sockets ────────────────────────────────────────────────────────
echo "[*] Enumerating active network connections..."
SOCKETS=$(tv_ssh "ss -tnp 2>/dev/null || netstat -tnp 2>/dev/null || echo 'N/A'")
DNS_SERVERS=$(tv_ssh "cat /etc/resolv.conf 2>/dev/null")

# ── 6. Active outbound connections (phone-home check) ─────────────────────────
echo "[*] Checking outbound connections (telemetry scan)..."
OUTBOUND=$(tv_ssh "ss -tnp state established 2>/dev/null | grep -v '127.0.0.1' || echo 'N/A'")

# ── 7. Installed packages ─────────────────────────────────────────────────────
echo "[*] Listing installed apps and packages..."
APPS=$(tv_ssh "luna-send -n 1 luna://com.webos.service.applicationmanager/listApps '{}' 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); [print(a[\"id\"],a.get(\"version\",\"?\"),a.get(\"type\",\"?\")) for a in d.get(\"apps\",[])]' 2>/dev/null || echo 'luna-send not available in dev mode'")

# ── 8. Autostart / init services ─────────────────────────────────────────────
echo "[*] Reading service autostart configuration..."
UPSTART=$(tv_ssh "ls /etc/init/ 2>/dev/null | head -60 || echo 'N/A'")
PRELOAD=$(tv_ssh "cat /etc/upstart/sam-auto-preload.conf 2>/dev/null || cat /etc/wam/preload.txt 2>/dev/null || echo 'preload config not found'")

# ── 9. Known telemetry processes ─────────────────────────────────────────────
echo "[*] Checking telemetry-related processes..."
TELEMETRY=$(tv_ssh "ps aux 2>/dev/null | grep -iE 'acr|telemetry|analytics|adid|datad|report|lgsdp|collector' | grep -v grep || echo 'None found'")

# ── 10. Disk usage ────────────────────────────────────────────────────────────
echo "[*] Reading storage layout..."
DISKS=$(tv_ssh "df -h 2>/dev/null")
MOUNTS=$(tv_ssh "mount 2>/dev/null | grep -vE '^(devtmpfs|proc|sys|cgroup|tmpfs|devpts)' | head -30")

# ── 11. /etc/hosts (current state) ───────────────────────────────────────────
echo "[*] Reading current /etc/hosts..."
HOSTS=$(tv_ssh "cat /etc/hosts 2>/dev/null || echo 'N/A'")

# ── 12. Root check ────────────────────────────────────────────────────────────
echo "[*] Checking privilege level..."
WHOAMI=$(tv_ssh "whoami 2>/dev/null; id 2>/dev/null")
ROOT_CHECK=$(tv_ssh "ls /etc/opkg/opkg.conf 2>/dev/null && echo 'Homebrew Channel DETECTED' || echo 'No Homebrew Channel'")

# ── Assemble JSON ─────────────────────────────────────────────────────────────
python3 -c "
import json, sys
data = {
    'tv_model': '${TV_MODEL}',
    'audit_time': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'firmware': $(echo "$FIRMWARE" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'build': $(echo "$BUILD" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'kernel': $(echo "$KERNEL" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'arch': '${ARCH}',
    'hostname': '${HOSTNAME}',
    'memory': $(echo "$MEMINFO" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'zram': $(echo "$ZRAM" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'top_memory_procs': $(echo "$TOP_MEM" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'sockets': $(echo "$SOCKETS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'outbound_connections': $(echo "$OUTBOUND" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'dns_servers': $(echo "$DNS_SERVERS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'installed_apps': $(echo "$APPS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'autostart_services': $(echo "$UPSTART" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'preload_config': $(echo "$PRELOAD" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'telemetry_processes': $(echo "$TELEMETRY" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'disk_usage': $(echo "$DISKS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'mounts': $(echo "$MOUNTS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'etc_hosts': $(echo "$HOSTS" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'privilege_level': $(echo "$WHOAMI" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))'),
    'homebrew_channel': $(echo "$ROOT_CHECK" | python3 -c 'import sys,json; t=sys.stdin.read().strip(); print(json.dumps(t))')
}
print(json.dumps(data, indent=2, ensure_ascii=False))
" > "${AUDIT}"

echo ""
echo "[✓] Audit saved to: ${AUDIT}"
echo ""
echo "=== KEY FINDINGS ==="
python3 -c "
import json
with open('${AUDIT}') as f:
    d = json.load(f)
fw = d.get('firmware','?')
priv = d.get('privilege_level','?')
hb = d.get('homebrew_channel','?')
tel = d.get('telemetry_processes','?')
out = d.get('outbound_connections','?')
print(f'Firmware   : {fw[:200]}')
print(f'Privilege  : {priv}')
print(f'Homebrew   : {hb}')
print(f'Telemetry  : {tel[:300]}')
print(f'Outbound   : {out[:300]}')
"

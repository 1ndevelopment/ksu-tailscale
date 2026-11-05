#!/system/bin/sh
# Action button in the KernelSU/Magisk manager: toggles tailscaled.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

if is_running; then
    stop_ts
else
    start_ts
fi

echo ""
if is_running; then
    echo "tailscaled: running"
    "$TAILSCALE" --socket="$SOCK" status 2>/dev/null | head -n 5
else
    echo "tailscaled: stopped"
    if [ -f "$LOG" ]; then
        echo "--- last log lines ---"
        tail -n 20 "$LOG"
    fi
fi

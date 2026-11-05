#!/system/bin/sh
# Runs when the module is removed. Stops the daemon.
# Node state in /data/adb/tailscale is kept so reinstalling keeps the same device identity.
# Delete that directory manually to fully wipe it.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

stop_ts

#!/system/bin/sh
# Boot-time launcher. Runs late_start, after /data is mounted and the system is up.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 5

# Disable without uninstalling: touch /data/adb/modules/ksu_tailscale/disable
[ -f "$MODDIR/disable" ] && exit 0

start_ts

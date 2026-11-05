#!/system/bin/sh
# Installer for KSU Tailscale. Runs inside the KernelSU/Magisk installer.

type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

ui_print "- Installing KSU Tailscale"

ABI=$(getprop ro.product.cpu.abi)
case "$ABI" in
    arm64-v8a)   ARCH=arm64; SRC=arm64-v8a ;;
    armeabi-v7a) ARCH=arm;   SRC=armeabi-v7a ;;
    *) abort "! Unsupported ABI: $ABI (need arm64-v8a or armeabi-v7a)" ;;
esac

ui_print "- Device ABI: $ABI"

mkdir -p "$MODPATH/bin"

if [ -f "$MODPATH/bin/$SRC/tailscale" ] && [ -f "$MODPATH/bin/$SRC/tailscaled" ]; then
    # Binaries bundled in the zip take precedence (offline installs, pinned versions).
    ui_print "- Using bundled Tailscale binaries"
    mv "$MODPATH/bin/$SRC/tailscale" "$MODPATH/bin/tailscale"
    mv "$MODPATH/bin/$SRC/tailscaled" "$MODPATH/bin/tailscaled"
else
    ui_print "- Fetching latest stable Tailscale for $ARCH..."
    ARCH="$ARCH" sh "$MODPATH/fetch-release.sh" --install "$MODPATH/bin" \
        || abort "! Could not fetch Tailscale. Check network, or bundle binaries in bin/$SRC/"
    ui_print "- Fetched Tailscale $(cat "$MODPATH/bin/version")"
fi

rm -rf "$MODPATH/bin/arm64-v8a" "$MODPATH/bin/armeabi-v7a"

chmod 0755 "$MODPATH/bin/tailscale" "$MODPATH/bin/tailscaled"
chmod 0755 "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/uninstall.sh" \
           "$MODPATH/common.sh" "$MODPATH/fetch-release.sh"

mkdir -p /data/adb/tailscale
ui_print "- Runtime state: /data/adb/tailscale"
ui_print "- Add an auth key to /data/adb/tailscale/authkey for unattended login"
ui_print "- Done. Reboot or run the action button to start Tailscale."

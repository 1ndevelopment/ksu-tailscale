#!/system/bin/sh
# Shared helpers for service.sh and action.sh.
# Everything runtime-related lives under $STATE_DIR (/data/adb), so the module
# works under temporary root: no /system writes, no bind mounts, no persistent
# edits outside the module directory itself.

MODDIR=${MODDIR:-${0%/*}}
STATE_DIR=/data/adb/tailscale
LOG="$STATE_DIR/tailscale.log"
SOCK="$STATE_DIR/tailscaled.sock"
STATE_FILE="$STATE_DIR/tailscaled.state"
AUTHKEY_FILE="$STATE_DIR/authkey"
CONF="$STATE_DIR/config"
TAILSCALED="$MODDIR/bin/tailscaled"
TAILSCALE="$MODDIR/bin/tailscale"

# Defaults; override in $CONF (plain KEY=VALUE shell lines).
TS_ACCEPT_DNS=false
TS_EXTRA_ARGS=""
# userspace: no kernel routes or ip rules are installed. Works under temporary root.
# kernel:    uses tailscale0 and kernel routing when /dev/net/tun exists.
TS_TUN_MODE=userspace

load_config() {
    mkdir -p "$STATE_DIR"
    [ -f "$CONF" ] && . "$CONF"
}

log() {
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
    echo "$1"
}

is_running() {
    pidof tailscaled >/dev/null 2>&1
}

start_ts() {
    load_config

    if is_running; then
        log "tailscaled already running"
        return 0
    fi

    if [ ! -x "$TAILSCALED" ]; then
        log "! $TAILSCALED missing or not executable"
        return 1
    fi

    # Userspace networking by default. Kernel TUN installs routing rules that
    # black-hole tailscaled's traffic on some devices, so it is opt-in only.
    if [ "$TS_TUN_MODE" = kernel ] && [ -c /dev/net/tun ]; then
        TUN=tailscale0
    else
        TUN=userspace-networking
    fi

    log "starting tailscaled (tun=$TUN)"
    # shellcheck disable=SC2086
    nohup "$TAILSCALED" \
        --state="$STATE_FILE" \
        --socket="$SOCK" \
        --tun="$TUN" \
        $TS_EXTRA_ARGS >> "$LOG" 2>&1 &

    # Wait for the daemon socket to appear.
    i=0
    while [ ! -S "$SOCK" ] && [ "$i" -lt 15 ]; do
        sleep 1
        i=$((i + 1))
    done

    if [ ! -S "$SOCK" ]; then
        log "! tailscaled did not create its socket; see $LOG"
        return 1
    fi

    if [ -f "$AUTHKEY_FILE" ]; then
        log "bringing node up with authkey"
        "$TAILSCALE" --socket="$SOCK" up \
            --authkey="file:$AUTHKEY_FILE" \
            --accept-dns="$TS_ACCEPT_DNS" >> "$LOG" 2>&1 \
            || log "! tailscale up failed; check authkey"
    else
        log "no $AUTHKEY_FILE found; run 'tailscale up' manually once to log in"
    fi
    return 0
}

stop_ts() {
    if ! is_running; then
        log "tailscaled not running"
        return 0
    fi
    log "stopping tailscaled"
    for p in $(pidof tailscaled); do
        kill "$p"
    done
    rm -f "$SOCK"
}

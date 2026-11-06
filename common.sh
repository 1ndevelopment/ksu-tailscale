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
# auto:      use kernel TUN (tailscale0) when /dev/net/tun is available or can
#            be created; otherwise fall back to userspace networking. This keeps
#            the module working on temporary-root devices while still exposing a
#            real tailscale0 interface whenever the kernel supports it.
# userspace: no kernel routes or ip rules are installed. Works under temporary root.
# kernel:    use tailscale0 and kernel routing when /dev/net/tun exists.
TS_TUN_MODE=auto

load_config() {
    mkdir -p "$STATE_DIR"
    [ -f "$CONF" ] && . "$CONF"
}

log() {
    mkdir -p "$STATE_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
    echo "$1"
}

# PIDs of tailscaled processes that belong to this module (not a system one).
module_pids() {
    for p in $(pidof tailscaled 2>/dev/null); do
        if [ -r "/proc/$p/cmdline" ]; then
            if grep -qa "$STATE_DIR" "/proc/$p/cmdline" 2>/dev/null || grep -qa "$MODDIR" "/proc/$p/cmdline" 2>/dev/null; then
                echo "$p"
            fi
        else
            # No /proc info: assume any tailscaled is ours.
            echo "$p"
        fi
    done
    return 0
}

is_running() {
    [ -n "$(module_pids)" ]
}

# Make sure /dev/net/tun exists. On temporary-root / minimal Android setups the
# device node (and sometimes the tun module) is missing, which prevents
# tailscaled from creating tailscale0. Best-effort: never abort on failure.
ensure_tun() {
    [ -c /dev/net/tun ] && return 0

    mkdir -p /dev/net 2>/dev/null || true

    # Try to load the tun kernel module if the tools are available.
    if ! lsmod 2>/dev/null | grep -q '^tun[[:space:]]'; then
        if command -v modprobe >/dev/null 2>&1; then
            modprobe tun 2>/dev/null || true
        fi
        if ! [ -c /dev/net/tun ]; then
            for ko in \
                "/lib/modules/$(uname -r)/kernel/drivers/net/tun.ko" \
                "/lib/modules/$(uname -r)/tun.ko" \
                "/vendor/lib/modules/tun.ko" \
                "/system/lib/modules/tun.ko"; do
                [ -f "$ko" ] || continue
                if command -v insmod >/dev/null 2>&1; then
                    insmod "$ko" 2>/dev/null || true
                fi
                [ -c /dev/net/tun ] && break
            done
        fi
    fi

    # Create the device node by hand if the kernel supports tun but did not.
    if [ ! -c /dev/net/tun ]; then
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 0600 /dev/net/tun 2>/dev/null || true
    fi

    # SELinux on Android often blocks tun access for untrusted root contexts;
    # relax it best-effort so tailscaled can open the device.
    if command -v setenforce >/dev/null 2>&1; then
        setenforce 0 2>/dev/null || true
    fi

    [ -c /dev/net/tun ]
}

# Kernel TUN installs fwmark policy-routing rules that force tailscaled's own
# (marked) traffic through the "main"/"default" routing tables. On Android those
# tables often have no default route, so the rules end in "unreachable" and
# tailscaled reports "network is unreachable". Make sure "main" has a default
# route before starting, best-effort.
ensure_main_default_route() {
    # IPv4
    if ! ip route show table main 2>/dev/null | grep -q '^default'; then
        line=$(ip -4 route get 1.1.1.1 2>/dev/null | head -n 1)
        dev=$(printf '%s\n' "$line" | sed -n 's/.*dev \([^ ]*\).*/\1/p')
        gw=$(printf '%s\n' "$line" | sed -n 's/.*via \([^ ]*\).*/\1/p')
        if [ -n "$dev" ]; then
            if [ -n "$gw" ]; then
                ip route replace default via "$gw" dev "$dev" table main 2>/dev/null || true
            else
                ip route replace default dev "$dev" table main 2>/dev/null || true
            fi
        fi
    fi
    # IPv6
    if ! ip -6 route show table main 2>/dev/null | grep -q '^default'; then
        line=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | head -n 1)
        dev=$(printf '%s\n' "$line" | sed -n 's/.*dev \([^ ]*\).*/\1/p')
        gw=$(printf '%s\n' "$line" | sed -n 's/.*via \([^ ]*\).*/\1/p')
        if [ -n "$dev" ]; then
            if [ -n "$gw" ]; then
                ip -6 route replace default via "$gw" dev "$dev" table main 2>/dev/null || true
            else
                ip -6 route replace default dev "$dev" table main 2>/dev/null || true
            fi
        fi
    fi
    return 0
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

    # Remove a stale socket left by a crashed previous run.
    if [ -S "$SOCK" ] && [ -z "$(module_pids)" ]; then
        rm -f "$SOCK"
    fi

    # Determine whether to use kernel TUN (tailscale0) or userspace networking.
    # Kernel TUN needs /dev/net/tun; create it on demand for temporary-root
    # devices, and fall back to userspace networking if it cannot be provided.
    use_kernel=false
    case "$TS_TUN_MODE" in
        kernel) use_kernel=true ;;
        auto)
            if ensure_tun; then
                use_kernel=true
            else
                log "no /dev/net/tun available; falling back to userspace networking"
            fi
            ;;
        userspace) use_kernel=false ;;
        *)
            log "! unknown TS_TUN_MODE='$TS_TUN_MODE'; using userspace networking"
            use_kernel=false
            ;;
    esac

    if [ "$use_kernel" = true ]; then
        if ! ensure_tun; then
            log "! could not prepare /dev/net/tun; falling back to userspace networking"
            use_kernel=false
        else
            ensure_main_default_route
            TUN=tailscale0
        fi
    fi

    if [ "$use_kernel" != true ]; then
        TUN=userspace-networking
    fi

    log "starting tailscaled (tun=$TUN)"
    # Keep tailscaled's cache/state writes inside the writable state dir;
    # Android's root has a read-only "/" so the default /.cache path fails.
    # shellcheck disable=SC2086
    HOME="$STATE_DIR" XDG_CACHE_HOME="$STATE_DIR/cache" nohup "$TAILSCALED" \
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
            --accept-dns="$TS_ACCEPT_DNS" \
            --netfilter-mode=off >> "$LOG" 2>&1 \
            || log "! tailscale up failed; check authkey"
    else
        log "no $AUTHKEY_FILE found; run 'tailscale up' manually once to log in"
    fi
    return 0
}

stop_ts() {
    pids=$(module_pids)
    if [ -z "$pids" ]; then
        log "tailscaled not running"
        rm -f "$SOCK"
        return 0
    fi
    log "stopping tailscaled"
    for p in $pids; do
        kill "$p" 2>/dev/null || true
    done
    # Give it a moment to shut down.
    i=0
    while [ -n "$(module_pids)" ] && [ "$i" -lt 5 ]; do
        sleep 1
        i=$((i + 1))
    done
    rm -f "$SOCK"
}

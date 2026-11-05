#!/system/bin/sh
# Finds the latest stable Tailscale release for this device's architecture.
#
# Usage:
#   fetch-release.sh               print the download URL of the latest tgz
#   fetch-release.sh --install DIR download it and place tailscale + tailscaled in DIR
#
# Env overrides:
#   ARCH                   amd64|arm64|arm (default: detected from uname -m)
#   TAILSCALE_STABLE_URL   index URL (default: https://pkgs.tailscale.com/stable/)

set -eu

INDEX_URL="${TAILSCALE_STABLE_URL:-https://pkgs.tailscale.com/stable/}"

if [ -z "${ARCH:-}" ]; then
    case "$(uname -m)" in
        x86_64|amd64)            ARCH=amd64 ;;
        aarch64|arm64)           ARCH=arm64 ;;
        armv7l|armv7|armv8l|arm) ARCH=arm ;;
        *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
    esac
fi

# Use curl if present, otherwise wget (Android installers often have only one).
download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --max-time 60 -o "$2" "$1"
    else
        wget -q -T 60 -O "$2" "$1"
    fi
}

MODE=url
DEST=""
if [ "${1:-}" = "--install" ]; then
    MODE=install
    DEST="${2:?error: --install needs a directory}"
fi

WORK=$(mktemp -d 2>/dev/null || echo "/data/local/tmp/ts-fetch.$$")
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

HTML="$WORK/index.html"
download "$INDEX_URL" "$HTML" || { echo "error: could not download $INDEX_URL" >&2; exit 1; }

LATEST=$(grep -oE "tailscale_[0-9.]+_${ARCH}\.tgz" "$HTML" \
    | sed -E "s/^tailscale_|_${ARCH}\.tgz\$//g" \
    | sort -t . -k1,1n -k2,2n -k3,3n \
    | tail -n 1)
[ -n "$LATEST" ] || { echo "error: no Tailscale version found for $ARCH at $INDEX_URL" >&2; exit 1; }

TGZ="tailscale_${LATEST}_${ARCH}.tgz"
DL_URL="${INDEX_URL}${TGZ}"

if [ "$MODE" = url ]; then
    echo "$DL_URL"
    exit 0
fi

echo "- Latest stable Tailscale: $LATEST ($ARCH)" >&2
download "$DL_URL" "$WORK/$TGZ" || { echo "error: download failed: $DL_URL" >&2; exit 1; }
tar -xzf "$WORK/$TGZ" -C "$WORK"

mkdir -p "$DEST"
for bin in tailscale tailscaled; do
    src=$(find "$WORK" -type f -name "$bin" | head -n 1)
    [ -n "$src" ] || { echo "error: $bin not found in $TGZ" >&2; exit 1; }
    cp "$src" "$DEST/$bin"
    chmod 0755 "$DEST/$bin"
done
echo "$LATEST" > "$DEST/version"
echo "- Installed Tailscale $LATEST to $DEST" >&2

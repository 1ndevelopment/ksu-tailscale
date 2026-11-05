#!/system/bin/env sh

set -eu

export ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; esac

INDEX_URL="${TAILSCALE_STABLE_URL:-https://pkgs.tailscale.com/stable/}"

fetch() { curl -fsSL --retry 2 --max-time 30 "$1" ;}
html=$(fetch "$INDEX_URL") || { echo "error: could not download $INDEX_URL" >&2 ; exit 1 ;}

latest=$(printf '%s\n' "$html" \
  | grep -oE "tailscale_[0-9.]+_${ARCH}\.tgz" \
  | sed -E "s/^tailscale_|_${ARCH}\.tgz\$//g" \
  | sort -t . -k1,1n -k2,2n -k3,3n | tail -n 1 )
[ -z "$latest" ] && { echo "error: no Tailscale version found at $INDEX_URL" >&2; exit 1; }

DL_URL=$(echo "${INDEX_URL}tailscale_${latest}_${ARCH}.tgz")

echo "$DL_URL"

# KSU Tailscale

A KernelSU / Magisk module that runs the Tailscale daemon on Android. It is written to work under temporary root: everything runtime-related lives in `/data/adb/tailscale`, and the module never writes to `/system`.

## Requirements

- KernelSU (or Magisk / APatch) with root
- arm64-v8a or armeabi-v7a device
- Network access during install (to fetch Tailscale), or bundled binaries (see below)

## Tailscale version

At install time the module runs `fetch-release.sh`, which reads the stable index at https://pkgs.tailscale.com/stable/, picks the highest `tailscale_X.Y.Z_<arch>.tgz` for the device, and installs `tailscale` and `tailscaled` into `bin/`. The chosen version is written to `bin/version`.

To pin a version or install offline, bundle the binaries in the zip instead. The installer uses them in preference to fetching:

```
bin/arm64-v8a/tailscale
bin/arm64-v8a/tailscaled
bin/armeabi-v7a/tailscale      # 32-bit devices only
bin/armeabi-v7a/tailscaled
```

`fetch-release.sh` can also be run by hand on a device:

```sh
sh /data/adb/modules/ksu_tailscale/fetch-release.sh            # print the latest tgz URL
sh /data/adb/modules/ksu_tailscale/fetch-release.sh --install DIR
```

Set `TAILSCALE_STABLE_URL` to use a different index.

## Install

1. Flash `ksu-tailscale.zip` in the KernelSU or Magisk manager. The installer fetches the latest stable Tailscale unless you bundled binaries.
2. Reboot, or press the module's action button to start it now.
3. Log in, either with an auth key or interactively:
   - Unattended: write a reusable auth key to `/data/adb/tailscale/authkey`, then restart the module.
   - Interactive: `su -c '/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock up'` and open the printed URL.

## Temporary root

Temporary root does not persist across reboots, so after a reboot you need to re-grant root and re-run the boot step (or press the action button). Node identity and state survive because they live in `/data/adb/tailscale`.

## Configuration

Optional file `/data/adb/tailscale/config`, plain shell `KEY=VALUE` lines:

```sh
TS_ACCEPT_DNS=false          # set true to let Tailscale manage DNS
TS_EXTRA_ARGS="--port=41641" # extra flags passed to tailscaled
```

## Disabling and removing

- Disable without uninstalling: `touch /data/adb/modules/ksu_tailscale/disable`, then reboot.
- Uninstall: remove the module in the manager. This stops the daemon and keeps `/data/adb/tailscale`. Delete that directory to wipe the node identity.

## Logs

`/data/adb/tailscale/tailscale.log`

## Notes

- Kernel TUN is used when `/dev/net/tun` exists. Otherwise the module falls back to userspace networking.
- The original template's installer redirected users to an external Telegram channel. That is not included here.

## License

MIT

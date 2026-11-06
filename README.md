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
   - Interactive: `su -c '/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock up --netfilter-mode=off'` and open the printed URL.

## Temporary root

Temporary root does not persist across reboots, so after a reboot you need to re-grant root and re-run the boot step (or press the action button). Node identity and state survive because they live in `/data/adb/tailscale`.

## Configuration

Optional file `/data/adb/tailscale/config`, plain shell `KEY=VALUE` lines:

```sh
TS_ACCEPT_DNS=false          # set true to let Tailscale manage DNS
TS_TUN_MODE=auto             # auto (default: kernel TUN/tailscale0 when /dev/net/tun is available, else userspace), userspace, or kernel
TS_EXTRA_ARGS="--port=41641" # extra flags passed to tailscaled
```

By default (`TS_TUN_MODE=auto`) the module uses kernel TUN (`tailscale0`) when `/dev/net/tun` is available or can be created on the device, and falls back to `--tun=userspace-networking` otherwise. This keeps it working under temporary root while exposing a real `tailscale0` interface whenever the kernel supports it. Set `TS_TUN_MODE=userspace` to force userspace mode, or `TS_TUN_MODE=kernel` to require kernel TUN.

## Disabling and removing

- Disable without uninstalling: `touch /data/adb/modules/ksu_tailscale/disable`, then reboot.
- Uninstall: remove the module in the manager. This stops the daemon and keeps `/data/adb/tailscale`. Delete that directory to wipe the node identity.

## Troubleshooting

Use `--socket` with every `tailscale` command. The default socket path doesn't match the module's.

Alias for convenience (add to your Termux shell profile):

```sh
alias ts='/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock'
```

### Daemon starts but `tailscale up` hangs or reports "Logged out"

1. Check that the device has a working connection from a root shell:
   ```sh
   ping -c 2 1.1.1.1
   ```
2. Check the log for `network is unreachable` lines:
   ```sh
   sudo tail -n 50 /data/adb/tailscale/tailscale.log
   ```
3. Check whether the control server is reachable:
   ```sh
   tailscale --socket=/data/adb/tailscale/tailscaled.sock netcheck
   ```

### Suspected routing conflict (kernel TUN)

The module now adds a default route to the `main` routing table automatically when using kernel TUN, which resolves the `network is unreachable` black-hole on most devices.

With kernel TUN, tailscaled adds policy-routing rules that match its own marked packets (fwmark `0x80000`) and send them to tables that have no default route, followed by an `unreachable` rule. Connections then fail with `network is unreachable` even though the device has internet access.

To check:

1. Stop the module with the action button, or run `sh /data/adb/modules/ksu_tailscale/action.sh`.
2. Confirm the rules are gone:
   ```sh
   ip rule | grep -c 0x80000
   ```
   A count of `0` means they were cleared.
3. Run the daemon in userspace mode in the foreground, which doesn't install those rules:
   ```sh
   cd /data/adb/modules/ksu_tailscale/bin
   ./tailscaled --state=/data/adb/tailscale/tailscaled.state \
     --socket=/data/adb/tailscale/tailscaled.sock --tun=userspace-networking
   ```
4. In a second root shell, run `netcheck` or `up` with `--socket`.

If userspace mode connects, set `TS_EXTRA_ARGS="--tun=userspace-networking"` in `/data/adb/tailscale/config`. Repeated flags may conflict with the `--tun` the module passes, so verify which one takes effect in the log.

### Plain `ssh` to tailnet devices from Termux

With kernel TUN (`tailscale0`, the default when available) plain `ssh`, `ping`, and other normal apps can reach `100.x.x.x` addresses directly. The `~/.ssh/config` ProxyCommand below is only needed when running in userspace mode (`TS_TUN_MODE=userspace`), where there is no `tailscale0` interface.

To use plain `ssh`, route the connection through `tailscale nc`. Add this to `~/.ssh/config` in Termux:

```
Match exec "su -c '/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock status' | awk '{print $2}' | grep -qx %h"
  ProxyCommand su -c "/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock nc %h %p"
```

Then connect with `ssh user@100.x.x.x`.

Notes:
- The socket is root-owned, so the proxy runs through `sudo`. If `sudo` prompts for a password, the connection will hang or fail.
- The target device must run an OpenSSH server (`sshd`) listening on the port you connect to.
- MagicDNS names won't match the `Host 100.*` pattern. Use the `100.x.x.x` address, or add a `Host` entry for the device name with the same `ProxyCommand`.

### DNS on temporary root

Android's `/etc` is read-only, so Tailscale cannot rewrite `/etc/resolv.conf`.
Keep `TS_ACCEPT_DNS=false` (the default). If a previous run enabled DNS
management, turn it off:

```sh
/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock set --accept-dns=false
/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock up --accept-dns=false --netfilter-mode=off
```

### Netfilter / `ip6tables` errors on Android

Android kernels often lack working `ip6tables` support, and Tailscale's netfilter
setup fails with `ip6tables: ... invalid argument`. Pass `--netfilter-mode=off`
to `tailscale up` (the module does this automatically for authkey logins) to
skip netfilter management. This does not affect the `tailscale0` interface or
routing.

### Checking the interface

```sh
ip link show tailscale0
/data/adb/modules/ksu_tailscale/bin/tailscale --socket=/data/adb/tailscale/tailscaled.sock status
```

## Logs

`/data/adb/tailscale/tailscale.log`

## Notes

- `TS_TUN_MODE=auto` (default) prefers kernel TUN (`tailscale0`) and falls back to userspace networking when `/dev/net/tun` cannot be used. Kernel TUN installs routing rules that can break connectivity on some devices; set `TS_TUN_MODE=userspace` if that happens.
- The original template's installer redirected users to an external Telegram channel. That is not included here.

## License

MIT

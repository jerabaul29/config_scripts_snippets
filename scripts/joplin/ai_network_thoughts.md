# Network restriction for the Joplin sandbox: design thoughts

Status: ideas only, nothing implemented in `joplin_run.sh`. Details marked (?)
are from memory and need verification.

# CURRENT PLAN: no network in the sandbox, filtering proxy on the host

Everything after the "OUTDATED" heading further down is kept for reference only.

## Idea

Today Joplin shares the host network. Instead, run it with `bwrap --unshare-net`
(no network at all) and give it one way out: a unix socket file leading to a
filtering proxy on the host. The proxy only lets through connections to an
allowlist of exact hostnames on port 443. Joplin is told to use that proxy.

```
Joplin -> 127.0.0.1:3128 -> [socat, in sandbox] -> unix socket file
          (sandbox wall: only the socket file crosses)
unix socket file -> [socat, host] -> 127.0.0.1:PORT -> [tinyproxy, host] -> internet (filtered)
```

- Sandbox socat: Joplin can only speak TCP to a proxy, so this turns a local TCP
  port into the socket file.
- Host socat: tinyproxy listens on TCP only (?, no unix socket listen seen), so
  this turns the socket file back into a local TCP port.
- tinyproxy: the "doorman". Checks the hostname against the allowlist, then
  opens the real connection and does the DNS lookup itself.
- A small custom Python proxy listening directly on the unix socket would
  remove the host-side socat (and give per-host byte counts). Not written.

In practice: the script starts tinyproxy and the host socat (with config and
filter file in a private dir under `$XDG_RUNTIME_DIR`), starts bwrap with
`--unshare-net`, the socket bind-mounted in, the sandbox socat started before
Joplin, and Joplin pointed at `http://127.0.0.1:3128` (Electron
`--proxy-server=...`; possibly also Joplin's own proxy setting under
Settings > Synchronisation). On exit the script stops the helper processes.

## What it closes

- Notes cannot be sent to arbitrary hosts (not on the list = refused).
- No access to host localhost services, LAN devices, or abstract unix sockets
  (including the Xwayland abstract socket) because no network is shared.
- No DNS tunnelling: the sandbox does no DNS at all.
- Fail closed: code that ignores the proxy (for example Node `http` in a plugin)
  simply has no network and fails instead of leaking.

## What stays at risk

- Allowed destinations: anything Joplin can send to Joplin Cloud it can send
  to an attacker's own Joplin Cloud account; same for any other allowed host
  (for example GitHub). Keep the list minimal; few or no plugins is the best
  extra measure.
- Wayland clipboard and other protocols exposed by the Wayland socket. A
  focused app can read the clipboard silently (compositors with data-control
  protocols, e.g. wlroots-based, allow it even unfocused; GNOME does not).
- Joplin and its plugins can still read all notes in the data directory.
- The proxy is new host-side code: it must be strict (port 443 only, exact
  names, no IP literals, no redirects) and run as the user.
- Kernel or bwrap sandbox-escape bugs, same as today.
- Wayland-only session: X11 is not reachable (Mutter starts Xwayland with
  `-auth` cookie in `$XDG_RUNTIME_DIR`; tested: connection without cookie was
  refused), and `--clearenv` leaves `DISPLAY` unset.

## What was tested (on this machine, Ubuntu 24.04)

- `tinyproxy-bin` 1.11.1 and `socat` 1.8.0 exist in the Ubuntu repositories
  (not installed; run from extracted .deb files for the test, then deleted).
- tinyproxy config used for the test:
  ```
  Listen 127.0.0.1
  Port <random>
  FilterType ere
  FilterDefaultDeny Yes
  Filter "<file with lines like ^api\.joplincloud\.com$>"
  ConnectPort 443
  LogLevel Connect
  LogFile "<path>"
  ```
- Through it, `api.joplincloud.com` connected; `example.com` was refused and
  logged ("Proxying refused on filtered domain").
- NOT working yet: `bwrap --unshare-net` fails here with
  `loopback: Failed RTM_NEWADDR: Operation not permitted`, also with
  `--unshare-user`. Cause: `kernel.apparmor_restrict_unprivileged_userns=1` and
  no AppArmor profile for `/usr/bin/bwrap` (the current shared-network sandbox
  never configures a private loopback, so it works). Needs a root-installed
  AppArmor profile allowing `userns` for `/usr/bin/bwrap`. Because of this, the
  sandbox-side socat bridge and Joplin through the proxy are untested.

## Is HTTP/HTTPS enough for Joplin?

- tinyproxy handles plain HTTP and `CONNECT` tunnels (HTTPS, WebSockets); with
  `ConnectPort 443` only port 443. No UDP (QUIC falls back to HTTPS) and no
  non-HTTP protocols.
- Joplin Cloud sync is a REST API over HTTPS, as are WebDAV, Nextcloud,
  OneDrive, Dropbox and S3 sync. Plugin downloads and update checks are HTTPS.
- Open question (?): Chromium honours `--proxy-server`, but Joplin's Node-side
  sync and plugin code may not. Joplin has its own proxy setting that probably
  covers sync; verify by testing and reading the proxy log. Failure is safe
  (no network), only features may break.

## Logging and discovering the hostnames

- tinyproxy writes plain text to `LogFile` or syslog (`Syslog On`); there is no
  database. With `LogLevel Connect` each line has a timestamp, target
  `host:port` and allowed/refused/established, for example:
  ```
  CONNECT [pid]: Request (file descriptor 2): CONNECT example.com:443 HTTP/1.1
  NOTICE  [pid]: Proxying refused on filtered domain "example.com"
  CONNECT [pid]: Established connection to host "api.joplincloud.com" ...
  ```
- Refused attempts are logged too, which is how to discover which hostnames
  Joplin needs: run a sync with a broad filter (or none) and read the
  `CONNECT` lines.
- Not visible: HTTPS URLs/paths/headers/content (encrypted inside the tunnel;
  TLS interception is not wanted), bytes transferred per connection, the
  resolved IP, which Joplin component made the request. Per-host byte counts
  would need the custom Python proxy.
- Keep the log somewhere persistent (for example `~/.local/state/`), not
  `/tmp`, and rotate it like `joplin_run.log`.

## Next steps

1. Write and install (sudo) the AppArmor profile for `/usr/bin/bwrap` so
   `--unshare-net` works; re-test.
2. Test the sandbox-side socat bridge and curl through it.
3. Run Joplin through the proxy with a broad filter, collect hostnames from the
   log, tighten the allowlist.
4. Implement in `joplin_run.sh` (start/stop helpers, preflight that proves the
   sandbox has no direct network and that a non-listed host is refused), and
   keep `AGENTS.md` in sync.
5. Decide whether to replace tinyproxy + host socat with a custom Python proxy.

---

# OUTDATED: earlier notes (superseded by the plan above)

The sections below were the first brainstorm (pasta, nft, podman). Kept for
reference; the plan above is the way forward.

## Goal

Replace the current shared host network (`joplin_run.sh` leaves the network
namespace shared, so Joplin or any plugin can send notes anywhere) with a
private network namespace that:

- drops all incoming connections;
- allows outgoing traffic only to the Joplin server and safe DNS servers (or no
  DNS at all);
- cannot be reconfigured from inside the sandbox.

## Key facts

- `bwrap` has no option to join an existing network namespace. It inherits
  whatever namespace it starts in, so a pre-made namespace could be entered with
  `nsenter --net=...` before `bwrap`. Pre-making one rootless needs an owning
  user namespace, which is fiddly.
- Network settings are checked against the user namespace that owns the network
  namespace. A process in the sandbox with no capabilities there cannot change
  the firewall rules. Setuid-root binaries from the host do not map into the
  namespace, so they cannot regain capabilities.
- Everything below can be rootless. Only one-time installs (`passt`,
  `nftables`, possibly `podman`) and AppArmor profiles need admin rights. On
  this machine `kernel.apparmor_restrict_unprivileged_userns=1`.
- Checked here: `nft` is installed; `podman`, `pasta`/`passt` and `netavark` are
  not.

## Option A: stay with bwrap, configure its own netns before Joplin starts

1. Launch `bwrap --unshare-net --block-fd N --json-status-fd M ...`.
   `--block-fd` holds the app until the descriptor is released. The child PID is
   reported first (?, the ordering needs testing).
2. From the host, `nsenter -U -n -t PID`: bring `lo` up and load an `nft`
   ruleset. Rootless `nft` works inside a user namespace.
3. Attach `pasta` (package `passt`, what rootless podman uses) to the namespace
   for outbound connectivity.
4. Release the block; Joplin starts.

Pros: keeps the current minimal sandbox (bare host `/usr`, synthetic `/etc`,
private AppImage copy), no image, no container runtime.
Cons: the script has to supervise `pasta` and `nft`, and clean up; more
hand-driven plumbing.

## Option B: rootless podman

1. Create a pod. Its infra container holds the network namespace, attached to
   `pasta` (`--network=pasta:...`).
2. Run a short setup container in the pod with `--cap-add=NET_ADMIN` and a tiny
   image containing `nft`; it loads the ruleset and exits.
3. Run Joplin in the same pod with `--cap-drop=all`,
   `--security-opt no-new-privileges`, `--read-only`, `--tmpfs` with sizes and
   `--memory`. It shares the namespace but cannot change the rules.
4. Pass the Wayland socket as a bind mount; use `--dns=none` plus `--add-host`
   for host-resolved IPs.

Pros: standard pattern, no PID or fd juggling, default seccomp profile (bwrap
has none), flags for most hardening, `podman rm` cleanup.
Cons:
- needs an image with Joplin's GTK/NSS dependencies, or `--rootfs` on a host
  `/usr` mount (awkward); the image is a second thing to build, update and trust
  beside the AppImage check;
- the launcher must be rewritten around `podman run`;
- rootless storage and a slow first run;
- Wayland passing, user mapping for the data directory and AppImage
  extract-and-run inside a container all need testing;
- Ubuntu 24.04 ships podman 4.9, where `pasta` support is older (?).

## Option C: host-side rule (needs root)

A root-owned host `nft` rule matching the sandbox's systemd scope cgroup
(`socket cgroupv2`, with a fixed `systemd-run --unit` name). Simple, but outside
the script and needs root. OpenSnitch is the existing idea in `AGENTS.md`.

## Firewall design (for A or B)

- Input: default drop; allow loopback and established/related only.
- Output: default drop; allow only an `nft` set of allowed IPs. Drop IPv6
  (disable it in the namespace) and ICMP.
- `pasta`: use `--no-map-gw` so the sandbox cannot reach host services through
  the gateway address.

## Domain allowlisting is the hard part

Joplin Cloud's IPs can change and may sit on shared CDNs.

- Resolve the hostnames on the host at each launch, fill the `nft` set, and write
  the same entries into the synthetic `/etc/hosts`. The sandbox then needs no
  DNS, which also closes DNS tunnelling. Long sessions need a refresh loop that
  updates the set and the hosts file in place.
- A hostname-allowlist proxy reached through a unix socket gives name-level
  control, but only if every Joplin request honours proxy settings (doubtful).
- The full list of hostnames Joplin needs (sync, plugin repository, update
  checks) is unknown; find it by logging dropped packets.

## Residual limits

- A malicious plugin can still push data to an allowed host, for example
  Joplin Cloud with its own account, or GitHub if it is allowed. This narrows
  exposure; it does not stop it.
- A private namespace has its own loopback, so the web clipper port (and any
  host localhost service) is unreachable. Joplin also has no inbound access.
- Ubuntu 24.04 AppArmor may need profiles for `pasta`, `nsenter` and `unshare`.

## Next steps

1. Install `podman`, `passt` and `nftables` (sudo).
2. Check that `podman info` works rootless and that `pasta` can attach to a pod.
3. Decide A or B, then prototype the launcher (and a Containerfile for B).
4. Find the hostnames Joplin needs by logging drops.

# Network restriction for the Joplin sandbox: design thoughts

Status: ideas only, nothing implemented or tested. Details marked (?) are from
memory and need verification.

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

# Syscall filtering (seccomp) for the Joplin sandbox: design thoughts

Status: ideas only, nothing implemented or tested in `joplin_run.sh`. Details
marked (?) are from memory and need verification.

## Why

`bwrap` applies no seccomp filter by default, so sandboxed Joplin (and any
plugin) can call almost every syscall the kernel offers to an unprivileged
process. Namespaces, dropped capabilities and the restricted filesystem already
limit damage, but a kernel bug reachable through an unneeded syscall (for
example `userfaultfd`, `io_uring`, `perf_event_open`, `ptrace`) is still
exploitable. Podman/Docker ship a default filter for exactly this reason.
`joplin_run.sh` currently has no seccomp usage.

Chromium/Electron installs its own filters in its renderer and utility
processes; they stack with ours (strictest verdict wins).

## Key facts

- Podman's default profile is an **allowlist**: `defaultAction` is
  `SCMP_ACT_ERRNO`, and the `syscalls` array names permitted calls with
  `SCMP_ACT_ALLOW`, some with `includes`/`excludes` conditions (capabilities,
  architecture, kernel version). With `--cap-drop ALL` only the unconditional
  entries apply.
- It is usually at `/usr/share/containers/seccomp.json`, shipped by
  `containers-common` (?, verify the path and package). It is JSON, not BPF.
- `bwrap` 0.9.0 here supports `--seccomp FD` (single) and `--add-seccomp-fd FD`
  (repeatable); both take **compiled BPF** from a file descriptor. Checked with
  `bwrap --help`.
- Seccomp filters stack: every loaded filter runs for each syscall and the
  strictest verdict wins. So the allowed set is the **intersection** of all
  filters. Order does not matter; a later filter can deny more but never
  re-allow. If two filters deny with different actions, the stricter action
  wins (kill > trap > errno > allow). Filters cannot be removed once loaded.
- `bwrap` installs the filter after it has set up its namespaces and mounts, so
  blocking `mount`, `unshare` and similar does not break `bwrap` itself.
- The numbers in `--add-seccomp-fd 4` are file descriptor numbers: arbitrary but
  unused (3 is already the `--json-status-fd`), attached when launching with
  `4<file.bpf 5<file2.bpf`. `bwrap` reads and closes them; Joplin does not
  inherit them.

## Trust model

Having podman (or just `containers-common`) installed and kept updated by apt is
acceptable, even though it is never run: the profile is maintained upstream and
the file is root-owned, so the script can verify it. Podman's rules are a good,
widely tested baseline for Chromium-style apps, but not tailored: roughly 300+
allowed syscalls, including some that Joplin does not need and that appear in
kernel exploits (`ptrace`, `userfaultfd`, `unshare`, `clone` flags, depending on
version and capability conditions (?)).

## Plan

1. Check the profile exists, is a regular file, root-owned, not group/world
   writable. Abort otherwise.
2. Convert podman's JSON to BPF at launch into the private work dir. No
   standard tool does this (podman/runc compile internally), so a small
   converter is needed (Python with `python3-seccomp`, ~60 lines, or C). It must
   honour `defaultAction`, per-syscall actions, argument conditions and the
   `includes`/`excludes` blocks (capabilities dropped; architecture; kernel
   version), and skip syscall names unknown to the local libseccomp, as podman
   does. This converter is the one piece of code we maintain.
3. Second filter: our own **observed-allowlist** built once and reviewed (see
   below), compiled to BPF, committed next to the script with a pinned sha512
   that the script verifies (same pattern as the AppImage). A plain static
   deny-list of unneeded calls (`ptrace`, `userfaultfd`, `io_uring_*`,
   `perf_event_open`, `process_vm_readv`/`writev`, `kcmp`, `pidfd_getfd`) is a
   simpler alternative or addition. Use an errno return (`EPERM`), not kill, so
   denials are visible.
4. Pass both with `--add-seccomp-fd 4 --add-seccomp-fd 5` (stacked, intersection
   semantics). Merging the deny list into the converter and passing one
   `--seccomp` gives the same result but more code; two filters keep podman's
   file untouched and our list small.
5. Preflight inside the sandbox: try one syscall blocked by each filter and
   require it to fail (extend the existing sandbox probe). Any failure aborts.

## Building our own allowlist (manual, one-time, not automatic)

- Run Joplin under `strace -f -c` (or `-f -o` to a file) several times covering
  every feature in use (sync, attachments, import/export, printing, plugins,
  update check, crash paths), merge the syscall names, review, add a small
  margin of calls Chromium is known to use, then compile and commit.
- Tracing under `bwrap` may hit `ptrace` limits (Yama `ptrace_scope`) (?); try
  it first. Alternative: a temporary `SCMP_ACT_LOG` filter, but reading the
  audit/kernel log may need privileges.
- Redo deliberately after Joplin/Electron or kernel updates.
- Do **not** record syscalls automatically on each run and feed them into the
  next run's allowlist: observed syscalls miss rare paths (features break
  later), and a malicious plugin could run chosen syscalls during a learning
  run to get them allowed.

## Failure handling: fail closed

- Do not "delete our seccomp and re-run if it fails": that fails open, cannot
  distinguish a seccomp failure from any other crash, can be triggered by an
  attacker causing a crash, and contradicts the script rule that any failed
  assumption aborts with an error.
- If Joplin breaks, abort with a clear message. Optionally an explicit,
  never-automatic flag (for example `--no-extra-seccomp`: podman's filter only)
  with a loud warning. For debugging use errno/log actions and `strace` to see
  which syscall was denied.

## Downsides

- Security: none by itself, a filter can only restrict. It narrows kernel
  exposure but not syscalls Joplin must keep.
- Costs: a too-strict filter breaks Joplin or plugins, sometimes confusingly
  (denials show up as unrelated errors); a podman package update may change the
  allowlist (breakage, or looser rules: review the diff after major updates);
  the converter, filter files and preflight must be maintained; the profile path
  may move between package versions (launch then aborts until fixed); more fd
  plumbing in the script.

## Next steps

1. Install podman or `containers-common`; confirm the profile path and contents
   (allowlist, `defaultAction`, conditions).
2. Install `python3-seccomp` (libseccomp bindings) and write the converter;
   test it on the stock profile.
3. Launch Joplin with only podman's filter via `--add-seccomp-fd`; confirm it
   runs and the preflight blocked-call check works.
4. Trace Joplin, build and review the second filter, pin its sha512.
5. Implement in `joplin_run.sh` and keep `AGENTS.md` in sync.

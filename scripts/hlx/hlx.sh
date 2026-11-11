#!/usr/bin/env bash
# hlx: run the Helix editor (AppImage) inside a bubblewrap sandbox.
# On every edit of this file, run shfmt -d hlx.sh and shellcheck hlx.sh.
#
# USAGE
#   hlx [hx flags] [path[:line[:col]]]...
#   hlx --self-test            check that the sandbox really blocks what it should (see below)
#   hlx --clean-cache          empty SANDBOX_CACHE_DIR (LSP indexes etc.); refuses while a session runs.
#                              Use it after opening an untrusted project or when the cache grows
#   HLX_NO_SANDBOX=1 hlx ...   run unsandboxed (needed e.g. for `--grammar fetch`, or to edit
#                              protected files such as the helix config itself)
#
# INSTALL
#   Add an alias to ~/.bashrc (adjust the path to where this script lives):
#     alias hlx='$HOME/path/to/scripts/hlx/hlx.sh'
#   Aliases only work in interactive shells; for non-interactive use (e.g. EDITOR=hlx git
#   commit) symlink the script into a PATH dir instead: ln -s /path/to/hlx.sh ~/.local/bin/hlx
#   `git commit` then works: the message files git hands to the editor (.git/COMMIT_EDITMSG,
#   MERGE_MSG, TAG_EDITMSG, SQUASH_MSG) are the only files inside .git that are accepted.
#   Interactive rebase todo lists are not (they can contain exec lines): use HLX_NO_SANDBOX=1.
#   Then create ~/.config/hlx/hlx.conf from hlx.conf.example and set HELIX_APPIMAGE.
#
# THREAT MODEL
#   Host: trusted. Opened folder: middle trust (not assumed hostile, but not a place for
#   credentials). Main goal: contain a compromised Helix, language server, or their
#   dependencies, assuming the host and that folder are not the attacker. That process
#   must not read host secrets, change login/shell files, or plant anything a later
#   unsandboxed git, hx, or login will run (hooks, .helix, this script, the AppImage,
#   the helix config). No network is what makes containment hold.
#   Accepted leaks: terminal output, the clipboard when enabled, and host details that
#   stay visible (PATH, user name, /etc/passwd, the paths of the read-only mounts).
#   Not contained, by design:
#   - Files in the writable opened folder: they can be changed and then run or followed by
#     later unsandboxed tools (Makefile, .envrc, scripts, venv .pth files, package scripts,
#     .vscode, symlinks). Treat the folder as untrusted after a session. After the session
#     hlx reports new .git/.helix, new or changed auto-run files (.envrc, .vscode/*,
#     .nvim.lua, .exrc, .mise.toml, .tool-versions, .husky/*, ...) and new symlinks that
#     point out of the opened folders (see LINKS). Nothing is reported for Makefiles or
#     scripts.
#   - Secrets in the opened folder are hidden from the sandbox, not made harmless: .env,
#     .env.* and *.pem/*.key files are masked (HLX_ALLOW_SECRETS=1 turns that off), but a
#     secret under another name is readable and can leave through the clipboard or the
#     terminal.
#   - The persistent SANDBOX_CACHE_DIR: a compromise can survive there between sandboxed
#     runs (never executed unsandboxed). Reset it with `hlx --clean-cache`.
#   Out of scope: kernel, bubblewrap and libseccomp vulnerabilities (the seccomp filter is
#   a deny-list, defence in depth only), and resource exhaustion (see NOT IMPLEMENTED).
#   Hardening that depends on the host (checked at startup, see HLX_CHECKS):
#   - bubblewrap >= 0.12.0 resolves symlinks in mount paths inside the new root
#     (openat2 RESOLVE_IN_ROOT) instead of on the host. Ubuntu 24.04 ships 0.9.0.
#   - fs.protected_hardlinks=1 and fs.protected_symlinks=1 (the usual default). They only
#     stop links to files you do not own; the sandbox runs as you, so they add little here.
#   Read-only mounts are part of the boundary; see LINKS.
#
# LINKS
#   Soft links cannot escape the sandbox itself. They are resolved in the sandbox mount
#   namespace, so a symlink to a host path that was not mounted (credentials, the rest of
#   $HOME, host /proc) is broken. Projects need symlink following (venvs, node_modules);
#   nosymfollow on the opened directory would break them, so it is not used.
#   But a symlink the sandbox leaves in the writable folder resolves on the HOST later:
#   a plain unsandboxed write through `x -> ~/.bashrc` would clobber the target. hlx
#   itself refuses such targets (it resolves paths first), other tools do not. After the
#   session hlx therefore reports every symlink that is new or changed in the opened
#   directories (PROTECT_DEPTH levels deep, not inside node_modules) whose target lies
#   outside the opened folders, the read-only mounts (conda, venv, helix config) and the
#   system dirs (/usr, /lib*, /bin, /sbin, /dev, /proc). Review or delete it before using
#   other tools there. At most 20 are listed.
#   Hard links would be the hole a read-only bind does not close: link/linkat needs write
#   permission only on the destination, and a read-only bind shares the inode of the
#   writable one. A hardlinked .git/hooks, languages.toml, conda script or AppRun in the
#   opened directory could be written, and the next unsandboxed git or hx would run it.
#   With this mount layout the kernel already refuses it: every read-only or read-write
#   target is its own mount, and link across mounts fails with EXDEV. seccomp denies link
#   and linkat anyway (EPERM), so the layout cannot silently become exploitable. The
#   self-test checks the filter itself with direct probes. Helix and language servers
#   save with rename, which cannot cross these mounts either. A tool that hardlinks on
#   purpose (cargo sometimes, cp -l) fails with EPERM.
#   SECCOMP_ALLOW=(link linkat) turns the deny off. If a real tool breaks, the finer fix
#   is Landlock REFER (link only inside the opened directory), applied by the wrapper
#   before seccomp — not done here.
#   A startup crawl is no alternative: it cannot see a link created after Helix starts, and
#   following symlinks on the host walks out of the tree. A hard link that was already
#   in the opened folder is still another name for that inode (protection is path based):
#   a middle-trust residual, not the compromised-editor case.
#
# WHAT THE SANDBOX ALLOWS
#   - no network, no IPC, own PID namespace, new session (see HLX_NEW_SESSION), cleared environment,
#     all capabilities dropped, no_new_privs, and a seccomp deny-list (seccomp.py, built with
#     libseccomp) for kernel calls such as ptrace, mount, io_uring, bpf, keyctl, unshare,
#     seccomp, vmsplice, socket families other than unix/inet/inet6 (netlink, packet,
#     vsock, ...), and link/linkat (hard-link aliasing of read-only files; see LINKS)
#   - read-only: the extracted AppImage, the helix config, conda/mamba/venv prefixes, EXTRA_RO
#   - read-write: ONLY the things you ask to open:
#       * an existing file    -> that single file (helix writes in place)
#       * a new file          -> an empty placeholder file is created and that single file is
#                                bound; it is removed again on exit if it is still untouched
#       * a directory         -> that directory
#       * no path argument    -> the current directory; if that is a forbidden location
#                                (e.g. $HOME) you are asked whether to use the scratch
#                                directory /tmp/hlx_scratchbook (mode 700, kept between runs)
#     plus EXTRA_RW and the file given to --log. Everything else (including the rest of $HOME)
#     is invisible. $HOME is an empty tmpfs. Consequently helix can only see/write what was
#     passed on the command line: opening or saving-as other paths fails by design.
#   - git repositories: if a target lies inside a git repo (found with
#     `git rev-parse`, run with fsmonitor disabled), the whole repo including its `.git` is mounted
#     READ-ONLY, and only the targets you opened stay read-write on top of it. So started in a
#     subdir, only that subdir is writable; started at the repo root, the root is writable
#     except `.git`. Reading history and `git diff` work (GIT_OPTIONAL_LOCKS=0 avoids index
#     writes); commits/staging must be done outside. For worktrees/submodules (`.git` is a
#     file) the real git dir and the common dir are mounted read-only too, but only if that
#     path looks like git metadata, is not a system location, and does not contain a path
#     that is bound read-write (that mount is applied later and would hide it). Announced
#     when it is outside the work tree; /proc or a session bus must not be mountable this way.
#     A repo rooted at
#     $HOME or above is ignored (it would expose all of $HOME), and so is a repo whose root
#     does not contain the target (a hostile `core.worktree` could point anywhere).
#   - inside a read-write directory, existing `.git` and `.helix` entries (up to
#     PROTECT_DEPTH levels deep, same filesystem, not inside node_modules; `.git` unless
#     HLX_GIT_RW=1, which only affects a repo root that is itself opened read-write) and any
#     DENY_PATHS entries are mounted read-only / masked. Unix sockets (ssh-agent, docker, IDE
#     or fsmonitor sockets...) found there (same PROTECT_DEPTH and filesystem limits; also
#     in the read-only repo) are masked too, since a read-only mount does not
#     stop connect(). A missing root-level `.git`/`.helix` is covered by an empty read-only
#     placeholder dir that is removed on exit by the last session using it (sessions share it
#     through flock files in "<SANDBOX_CACHE_DIR>.locks"; after a kill -9 the empty dir stays
#     and is cleaned up by the next session). Missing ones
#     deeper down cannot be pre-protected, so any new one is reported after the session
#     (review it before running hx or git there). Entries deeper than PROTECT_DEPTH are
#     neither protected nor reported.
#   - DENY_PATHS always includes hlx.sh's own directory, the hlx config dir and the AppImage,
#     since those run unsandboxed on the next invocation.
#   - a config file given with -c/--config is bound read-only and refused when it lies inside
#     a DENY_PATHS entry (so it cannot be used to expose credentials to the sandbox).
#   - refused outright: "/", $HOME or any ancestor of it, system locations and their children
#     (/tmp, /var, /opt, /mnt, /media, /srv, /boot, /run, /etc, /usr, /dev, /proc, /sys, ...
#     they can hold sockets or host state; /tmp/hlx_scratchbook is the one exception),
#     DENY_PATHS entries,
#     anything inside the read-only locations above or inside a .git/.helix dir (files too,
#     except the git commit message files listed under INSTALL),
#     and any directory that contains a not-yet-existing protected path (it could be created
#     from inside). Use HLX_NO_SANDBOX=1 to edit those.
#
# CONFIGURATION (the optional file $HLX_CONFIG, default ~/.config/hlx/hlx.conf, which is
# sourced as bash before the sandbox starts; see hlx.conf.example). Only the scalar settings
# HELIX_APPIMAGE, HELIX_CONFIG_DIR, SANDBOX_CACHE_DIR and PROTECT_DEPTH can also come from
# the environment; the lists (arrays) are set in the config file only. Nothing is
# hardcoded: HELIX_APPIMAGE has to be set.
#   HELIX_APPIMAGE     path of the Helix AppImage (required)
#   HELIX_CONFIG_DIR   helix config dir, mounted read-only at ~/.config/helix
#   SANDBOX_CACHE_DIR  the only persistent writable dir (mounted at ~/.cache/helix)
#   CONDA_DIRS         read-only conda/mamba roots; active CONDA_PREFIX, MAMBA_ROOT_PREFIX and
#                      VIRTUAL_ENV are added automatically
#   EXTRA_RO / EXTRA_RW  extra read-only / read-write paths (e.g. language servers, caches)
#   DENY_PATHS         never writable, masked inside read-write dirs (credentials, shell rc, ...)
#   PASS_ENV           extra environment variable names to pass through
#   PROTECT_DEPTH      how deep to look for .git/.helix inside read-write directories
#                      (positive integer, default 4)
#   SECCOMP_ALLOW      syscall names from the seccomp.py deny list to allow after all, plus
#                      "socket" (lifts the socket-family filter; some tools list network
#                      interfaces through AF_NETLINK). "seccomp" lifts both seccomp(2) and
#                      prctl(PR_SET_SECCOMP). Do not add link or linkat unless a tool breaks
#                      (see LINKS).
#
# ENVIRONMENT TOGGLES
#   HLX_DRY_RUN=1      print the bwrap command and exit (creates nothing, but a missing AppImage
#                      extraction is still offered first; --self-test still builds its temp repo)
#   HLX_CHECKS=on|off  (default on) warn at startup when the host is not in its best state:
#                      bubblewrap older than 0.12.0, or fs.protected_hardlinks /
#                      fs.protected_symlinks not 1. Warnings only, nothing is blocked.
#   HLX_NO_SANDBOX=1   run helix directly, no sandbox
#   HLX_ALLOW_SECRETS=1  do not mask .env, .env.* (not .example/.sample/.template/.dist) and
#                      *.pem/*.key files inside opened folders. A file named on the command
#                      line is never masked. Not allowed with --self-test.
#   HLX_GIT_RW=1       leave the .git of an opened repo root writable
#   HLX_NEW_SESSION=on|off (default on) bwrap --new-session: the sandbox has no controlling
#                      terminal. With "off" the sandbox shares yours: Ctrl-Z and terminal resize
#                      (SIGWINCH) reach helix, at the price of one defence layer (TIOCSTI is
#                      still denied by seccomp). Try "off" if resizing the terminal does not
#                      redraw helix.
#   HLX_SECCOMP=on|off (default on) the seccomp filter is compiled automatically into
#                      "<SANDBOX_CACHE_DIR>-seccomp-<arch>.bpf" (deliberately outside the
#                      directory the sandbox can write) and rebuilt whenever seccomp.py,
#                      libseccomp or SECCOMP_ALLOW changed. Needs python3 + libseccomp2.
#   HLX_CLIPBOARD=osc52|wayland|off   (default osc52; HLX_NO_CLIPBOARD=1 is the same as off)
#       wayland: bind only $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY into a private tmpfs runtime dir.
#                There is no network, so no direct exfiltration, but a Wayland client can do
#                whatever the compositor lets it: read the clipboard (GNOME: only while
#                focused; KDE/wlroots data-control: anytime), overwrite it (paste-jacking) and,
#                depending on the compositor, screencopy or virtual input. Best-effort only.
#       osc52:   no Wayland socket at all. shims/wl-copy sends yanks to the terminal as OSC 52
#                (needs a terminal that supports it; GNOME Terminal does not), shims/wl-paste
#                always fails, so paste with the terminal (Ctrl+Shift+V). The default. If yanking
#                does nothing, your terminal lacks OSC 52 support: use wayland or a different
#                terminal. Same accepted leak as wayland paste-jacking: the sandbox can set the
#                host clipboard to anything it can read. Yanks over 1 MiB are refused.
#       off:     no system clipboard.
#
# NOTES
#   - A HELIX_CONFIG_DIR made of symlinks (stow, dotfile managers) has dangling links inside
#     the sandbox unless their targets are added to EXTRA_RO.
#   - Ctrl-Z does not suspend helix (the sandbox has no controlling terminal), and anything
#     in your helix config that needs host services (e.g. tmux sockets) will not work.
#   - The sandbox is only as good as what you open: treat the contents of a read-write
#     directory as untrusted after a session (Makefiles, .envrc, scripts, ...).
#   - Known limits: a hard link that already exists in a read-write directory is not masked
#     (see LINKS; creating new ones from inside is denied). The sandbox can rename a
#     directory that contains a protected .git/.helix and recreate it unprotected (reported
#     after the session, see above). The sandbox owns the terminal output, so escape
#     sequences that make the terminal type text back (e.g. xterm title reports) can inject
#     keystrokes into the shell after helix exits. Use a terminal that does not answer such
#     queries. .git/.helix deeper than PROTECT_DEPTH, and any under node_modules, are neither
#     protected nor reported. Sockets deeper than PROTECT_DEPTH, or on another filesystem
#     mounted inside the opened folder (bind mounts are recursive, and find uses -xdev), are
#     not masked either: do not open folders that contain such sockets or mounts.
#   - Target: Ubuntu 24.04+, bash >= 4.4. Ubuntu 24.04 blocks unprivileged user namespaces via
#     AppArmor, so bwrap needs a profile that allows `userns`. It may or may not be installed:
#       sudo apt install apparmor-profiles apparmor-utils
#       sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
#       sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
#       bwrap --ro-bind / / --unshare-all --die-with-parent true && echo OK
#   - The AppImage is extracted (no FUSE) to "<AppImage>.extracted", named after the full
#     AppImage file name, so a new version is never served from a stale extraction. The
#     extraction itself runs the AppImage unsandboxed, once, after asking for confirmation.
#
# SELF-TEST
#   `hlx --self-test` creates a throwaway git repo next to the cache dir, runs selftest.sh
#   inside the real sandbox configuration (network, hidden files, capabilities, seccomp,
#   read-only repo, hardlink denial, symlink non-escape, masked paths, sockets and .env, git),
#   then verifies on the host that nothing leaked out.
#   Run it after changing this script, the config, bubblewrap or the kernel. Exit status 0 = all ok.
#   It refuses to run with HLX_SECCOMP=off or a non-empty SECCOMP_ALLOW, since it tests the
#   full default filter.
#
# NOT IMPLEMENTED YET
#   - mount targets are passed to bwrap as path strings. A host-side attacker who swaps a
#     symlink between hlx's checks and the mount could redirect it (host is trusted here).
#     bwrap --bind-fd/--ro-bind-fd with a directory fd opened first would close it; bash
#     cannot open with O_NOFOLLOW, so this needs a small helper (python os.open). Only the
#     source side races (destinations live inside the new root), and the helper cannot be
#     tested without a working bwrap, so it is left out rather than shipped untested.
#   - Landlock REFER, only if denying link/linkat breaks a real tool (see LINKS)
#   - seccomp: more denied calls / an allow-list (see the TODO in seccomp.py)
#   - masking of secrets under other names (credentials.json, *.tfvars, ...) and of secrets
#     deeper than PROTECT_DEPTH
#   - resource limits via systemd-run --user / cgroups

set -euo pipefail

HLX_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
HOME="$(realpath "$HOME")"

die() {
	printf 'hlx: %s\n' "$*" >&2
	exit 1
}
warn() { printf 'hlx: note: %s\n' "$*" >&2; }

# within CHILD PARENT: CHILD is PARENT or below it (absolute, normalized paths)
within() { [[ "$1" == "$2" || "$1" == "${2%/}/"* ]]; }

# system locations can hold sockets or host state. Children count: /tmp itself is not the
# only dangerous path (/tmp/.X11-unix, /var/log, /boot/grub). The scratch dir is the one
# exception, created by this script.
is_system_location() {
	local p=$1
	[[ "$p" == /tmp/hlx_scratchbook || "$p" == /tmp/hlx_scratchbook/* ]] && return 1
	case "$p" in
	/tmp | /tmp/* | /var | /var/* | /opt | /opt/* | /mnt | /mnt/* | /media | /media/* | /srv | /srv/* | \
		/boot | /boot/* | /run | /run/* | /etc | /etc/* | /usr | /usr/* | /dev | /dev/* | /proc | /proc/* | \
		/sys | /sys/* | /bin | /bin/* | /sbin | /sbin/* | /lib | /lib/* | /lib32 | /lib32/* | /lib64 | /lib64/* | \
		/libx32 | /libx32/* | /snap | /snap/*)
		return 0 ;;
	*) return 1 ;;
	esac
}

# ---------------------------------------------------------------- config
HLX_CONFIG="${HLX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hlx/hlx.conf}"
HELIX_APPIMAGE="${HELIX_APPIMAGE:-}"
HELIX_CONFIG_DIR="${HELIX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/helix}"
SANDBOX_CACHE_DIR="${SANDBOX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hlx-sandbox}"
CONDA_DIRS=("$HOME/conda" "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/mambaforge" "$HOME/.local/share/mamba")
EXTRA_RO=()
EXTRA_RW=()
PASS_ENV=()
SECCOMP_ALLOW=()
PROTECT_DEPTH="${PROTECT_DEPTH:-4}"
DENY_PATHS=(
	"$HOME/.ssh" "$HOME/.gnupg" "$HOME/.aws" "$HOME/.azure" "$HOME/.kube" "$HOME/.docker"
	"$HOME/.netrc" "$HOME/.password-store" "$HOME/.local/share/keyrings"
	"$HOME/.config/gcloud" "$HOME/.config/gh" "$HOME/.config/git" "$HOME/.gitconfig"
	"$HOME/.mozilla" "$HOME/.config/google-chrome" "$HOME/.config/chromium"
	"$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_logout" "$HOME/.profile"
	"$HOME/.bash_login" "$HOME/.bash_aliases" "$HOME/.inputrc"
	"$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zlogin" "$HOME/.zlogout"
	"$HOME/.config/fish" "$HOME/.config/environment.d" "$HOME/.pam_environment"
	"$HOME/.xprofile" "$HOME/.xsessionrc"
	"$HOME/.npmrc" "$HOME/.pypirc" "$HOME/.config/pip" "$HOME/.cargo/config" "$HOME/.cargo/config.toml"
	"$HOME/.cargo/credentials" "$HOME/.cargo/credentials.toml"
	"$HOME/.config/autostart" "$HOME/.config/systemd" "$HOME/.local/bin"
)

if [[ -f "$HLX_CONFIG" ]]; then
	set +u
	# shellcheck source=/dev/null
	source "$HLX_CONFIG"
	set -u
fi

if [[ "${1:-}" == --self-test ]]; then
	[[ "${HLX_NO_SANDBOX:-0}" != 1 ]] || die "--self-test cannot be combined with HLX_NO_SANDBOX=1"
	[[ "${HLX_ALLOW_SECRETS:-0}" != 1 ]] || die "--self-test cannot be combined with HLX_ALLOW_SECRETS=1"
	[[ "${HLX_SECCOMP:-on}" == on && ${#SECCOMP_ALLOW[@]} -eq 0 ]] ||
		die "--self-test needs the full seccomp filter (HLX_SECCOMP=on, SECCOMP_ALLOW empty)"
fi

[[ "$PROTECT_DEPTH" =~ ^[1-9][0-9]*$ ]] || die "invalid PROTECT_DEPTH: $PROTECT_DEPTH (use a positive integer)"
for v in "${PASS_ENV[@]}"; do
	[[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid variable name in PASS_ENV: $v"
done

if [[ "${1:-}" == --clean-cache ]]; then
	[[ $# -eq 1 ]] || die "--clean-cache takes no other arguments"
	cache="$(realpath -m -- "$SANDBOX_CACHE_DIR")"
	home_real="$(realpath -m -- "$HOME")"
	# a mis-set SANDBOX_CACHE_DIR must never turn this into rm -rf of something important
	if [[ "$cache" == / || "$cache" == "$home_real" || "$home_real" == "$cache"/* || "$cache" != /*/* ]]; then
		die "refusing to clean $cache (it is, or contains, your home or the root); fix SANDBOX_CACHE_DIR"
	fi
	[[ -e "$cache" ]] || {
		echo "hlx: nothing to clean ($cache does not exist)"
		exit 0
	}
	[[ -d "$cache" && ! -L "$cache" ]] || die "$cache is not a plain directory"
	# only ever delete a directory that hlx itself created (marker written at session start)
	[[ -f "$cache/.hlx-cache" ]] ||
		die "$cache has no .hlx-cache marker, so it is not known to be an hlx cache (run hlx once, or touch the marker if you are sure)"
	command -v flock >/dev/null || die "flock is needed (util-linux)"
	(umask 077 && mkdir -p "$cache.locks")
	exec {fd}>"$cache.locks/cache.lock"
	flock -n -x "$fd" || die "an hlx session is running and using $cache; close it first"
	echo "hlx: removing $cache ($(du -sh -- "$cache" 2>/dev/null | cut -f1))"
	# keep the (empty) directory and its marker so owner, mode and the safety check survive
	find "$cache" -mindepth 1 ! -path "$cache/.hlx-cache" -delete || die "could not remove everything in $cache"
	exit 0
fi

[[ -n "$HELIX_APPIMAGE" ]] || die "HELIX_APPIMAGE is not set (set it in the environment or in $HLX_CONFIG)"
HELIX_APPIMAGE="$(realpath -ms -- "$HELIX_APPIMAGE")"
EXTRACT_DIR="$HELIX_APPIMAGE.extracted"

# ---------------------------------------------------------------- AppImage
# extracted AppImage (avoids FUSE, which bwrap cannot use)
if [[ ! -x "$EXTRACT_DIR/AppRun" ]]; then
	[[ ! -e "$EXTRACT_DIR" ]] || die "$EXTRACT_DIR exists but has no AppRun; remove it and retry"
	[[ -f "$HELIX_APPIMAGE" ]] || die "AppImage not found: $HELIX_APPIMAGE"
	[[ -x "$HELIX_APPIMAGE" ]] || die "AppImage is not executable: $HELIX_APPIMAGE"
	[[ -t 0 && -t 2 ]] || die "$EXTRACT_DIR missing and no TTY to ask; extract manually"
	ans=""
	read -rp "hlx: $EXTRACT_DIR not found. Extract the AppImage there? [y/N] " ans || true
	[[ "$ans" == [yY] ]] || die "aborted"
	tmp="$(mktemp -d "$HELIX_APPIMAGE.extract.XXXXXX")" || die "cannot create a temporary directory next to the AppImage"
	if ! (cd "$tmp" && "$HELIX_APPIMAGE" --appimage-extract >/dev/null) || [[ ! -x "$tmp/squashfs-root/AppRun" ]]; then
		rm -rf "$tmp"
		die "extraction failed"
	fi
	mv "$tmp/squashfs-root" "$EXTRACT_DIR"
	rmdir "$tmp"
fi

# informational flags need no sandbox, but only when that is the request itself
case "${1:-}" in
-V | --version | -h | --help) exec "$EXTRACT_DIR/AppRun" "$@" ;;
esac

if [[ "${HLX_NO_SANDBOX:-0}" == 1 ]]; then
	exec "$EXTRACT_DIR/AppRun" "$@"
fi

command -v bwrap >/dev/null || die "bwrap not installed (sudo apt install bubblewrap)"

# fail early with a useful hint if namespaces are blocked (Ubuntu AppArmor)
if [[ "${HLX_DRY_RUN:-0}" != 1 ]] && ! err="$(bwrap --ro-bind / / --unshare-all --die-with-parent true 2>&1)"; then
	if [[ "$err" == *"uid map"* || "$err" == *"Permission denied"* ]]; then
		die "bwrap cannot create user namespaces (Ubuntu AppArmor restriction). Install a bwrap profile:
  sudo apt install apparmor-profiles apparmor-utils
  sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
  sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict"
	fi
	die "bwrap self-check failed: $err"
fi

# warn (never fail) when the host is not in the best state; HLX_CHECKS=off silences it
hardening_checks() {
	local ver v sysctl
	ver="$(bwrap --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
	if [[ -n "$ver" && "$(printf '%s\n0.12.0\n' "$ver" | sort -V | head -n1)" != 0.12.0 ]]; then
		printf 'hlx: WARNING: bubblewrap %s is older than 0.12.0, which resolves symlinks in mount paths on the host while setting up the sandbox (openat2 RESOLVE_IN_ROOT); install a newer bwrap\n' "$ver" >&2
	fi
	for sysctl in protected_hardlinks protected_symlinks; do
		v="$(cat "/proc/sys/fs/$sysctl" 2>/dev/null || true)"
		if [[ -n "$v" && "$v" != 1 ]]; then
			printf 'hlx: WARNING: fs.%s=%s, it should be 1 (sudo sysctl -w fs.%s=1)\n' "$sysctl" "$v" "$sysctl" >&2
		fi
	done
}
case "${HLX_CHECKS:-on}" in
on) hardening_checks ;;
off) ;;
*) die "invalid HLX_CHECKS: ${HLX_CHECKS} (use on or off)" ;;
esac

# ---------------------------------------------------------------- locations
# read-only inside the sandbox; also refused as write targets
ro_mounts=("${CONDA_DIRS[@]}" "${EXTRA_RO[@]}") # bound read-only at their own path
for v in CONDA_PREFIX MAMBA_ROOT_PREFIX VIRTUAL_ENV; do
	if [[ -n "${!v:-}" ]]; then ro_mounts+=("${!v}"); fi
done
for i in "${!ro_mounts[@]}"; do ro_mounts[i]="$(realpath -m -- "${ro_mounts[i]}")"; done
ro_paths=("$(realpath -m -- "$EXTRACT_DIR")" "$(realpath -m -- "$HELIX_CONFIG_DIR")" "$HOME/.config/helix" "${ro_mounts[@]}")

rw_extra=()
for p in "${EXTRA_RW[@]}"; do rw_extra+=("$(realpath -m -- "$p")"); done
deny=()
for p in "${DENY_PATHS[@]}"; do deny+=("$(realpath -m -- "$p")"); done
# the wrapper's own trusted, unsandboxed inputs (this script, its config, the AppImage)
for p in "$HLX_DIR" "$HLX_CONFIG" "$(dirname "$HLX_CONFIG")" "$HELIX_APPIMAGE"; do deny+=("$(realpath -m -- "$p")"); done
SANDBOX_CACHE_DIR="$(realpath -m -- "$SANDBOX_CACHE_DIR")"
# the compiled seccomp filter is trusted input for the next run: never writable from inside
seccomp_bpf="$SANDBOX_CACHE_DIR-seccomp-$(uname -m).bpf"
lock_dir="$SANDBOX_CACHE_DIR.locks"
deny+=("$seccomp_bpf" "$seccomp_bpf.allow" "$lock_dir")

# ---------------------------------------------------------------- self-test setup
# Builds a throwaway repo and then continues as if `hlx <repo>/sub` had been started; the
# command run inside the sandbox is selftest.sh instead of helix (see the end of the bwrap part).
self_test=0
if [[ "${1:-}" == --self-test ]]; then
	[[ $# -eq 1 ]] || die "--self-test takes no other arguments"
	[[ -f "$HLX_DIR/selftest.sh" ]] || die "missing $HLX_DIR/selftest.sh"
	command -v git >/dev/null || die "--self-test needs git"
	self_test=1
	ST_ROOT="$(mktemp -d "$SANDBOX_CACHE_DIR.selftest.XXXXXX")"
	trap 'if [[ -n "${ST_ROOT:-}" ]]; then rm -rf -- "$ST_ROOT"; fi' EXIT
	ST_ROOT="$(realpath -- "$ST_ROOT")"
	HLX_ST_REPO="$ST_ROOT/repo"
	HLX_ST_SUB="$HLX_ST_REPO/sub"
	HLX_ST_OUTSIDE="$ST_ROOT/outside"
	HLX_ST_DENIED="$HLX_ST_SUB/denied.txt"
	mkdir -p "$HLX_ST_SUB" "$HLX_ST_OUTSIDE"
	echo canary >"$HLX_ST_OUTSIDE/canary"
	echo "top secret" >"$HLX_ST_DENIED"
	HLX_ST_ENV="$HLX_ST_SUB/.env"
	echo "API_KEY=must-not-leak" >"$HLX_ST_ENV"
	echo "API_KEY=" >"$HLX_ST_SUB/.env.example"
	HLX_ST_SOCK="$HLX_ST_SUB/agent.sock"
	python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$HLX_ST_SOCK" ||
		die "--self-test needs python3 to create a unix socket"
	echo one >"$HLX_ST_REPO/tracked.txt"
	git_st=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$HLX_ST_REPO" -c user.name=hlx -c user.email=hlx@localhost)
	"${git_st[@]}" init -q --template=
	"${git_st[@]}" add tracked.txt
	"${git_st[@]}" commit -q -m initial
	echo two >>"$HLX_ST_REPO/tracked.txt" # uncommitted change for the `git diff` test
	export HLX_ST_REPO HLX_ST_SUB HLX_ST_OUTSIDE HLX_ST_DENIED HLX_ST_SOCK HLX_ST_ENV
	export HLX_ST_SECRET=must-not-leak # not in PASS_ENV: has to stay outside
	PASS_ENV+=(HLX_ST_REPO HLX_ST_SUB HLX_ST_OUTSIDE HLX_ST_DENIED HLX_ST_SOCK HLX_ST_ENV)
	deny+=("$HLX_ST_DENIED")
	set -- "$HLX_ST_SUB"
fi

# check_writable ABS: refuse targets that must never be (made) writable
check_writable() {
	local p=$1 q
	if [[ "$p" == / ]] || { [[ -d "$p" ]] && within "$HOME" "$p"; }; then
		die "refusing to bind $p read-write (it is / or contains \$HOME); open a specific file or a project directory"
	fi
	if is_system_location "$p"; then
		die "$p is a system location (may hold sockets or host state); to edit it use: HLX_NO_SANDBOX=1 hlx ..."
	fi
	case "$p" in
	*/.helix | */.helix/*) die "$p is workspace config that can run commands; to edit it use: HLX_NO_SANDBOX=1 hlx ..." ;;
	# plain message files git passes to $EDITOR (git commit, merge, tag): text only, and only
	# that single file is bound; hooks, config and rebase todo lists (exec lines) stay refused
	*/.git/COMMIT_EDITMSG | */.git/MERGE_MSG | */.git/TAG_EDITMSG | */.git/SQUASH_MSG)
		[[ -f "$p" || "${HLX_GIT_RW:-0}" == 1 ]] || die "$p is git metadata (hooks run commands); use HLX_GIT_RW=1 or HLX_NO_SANDBOX=1"
		;;
	*/.git | */.git/*) [[ "${HLX_GIT_RW:-0}" == 1 ]] || die "$p is git metadata (hooks run commands); use HLX_GIT_RW=1 or HLX_NO_SANDBOX=1" ;;
	esac
	if [[ -d "$p" ]]; then
		# a protected path that does not exist cannot be masked, so the sandbox could create it
		for q in "${deny[@]}" "${ro_paths[@]}"; do
			if [[ "$q" != "$p" && ! -e "$q" ]] && within "$q" "$p"; then
				die "$p contains $q, which does not exist and could be created inside the sandbox; create it first or open a subdirectory"
			fi
		done
	fi
	for q in "${deny[@]}"; do
		if within "$p" "$q"; then
			die "$p is a protected location ($q); to edit it use: HLX_NO_SANDBOX=1 hlx ..."
		fi
	done
	for q in "${ro_paths[@]}"; do
		if within "$p" "$q"; then
			die "$p is read-only in the sandbox (inside $q); to edit it use: HLX_NO_SANDBOX=1 hlx ..."
		fi
	done
}
# EXTRA_RW is config, but a typo of $HOME or / must not skip the checks above
for p in "${rw_extra[@]}"; do check_writable "$p"; done

# check_readable ABS: a -c config file is bound read-only, so it must not be a protected (secret) path
check_readable() {
	local q
	for q in "${deny[@]}"; do
		if within "$1" "$q"; then die "$1 is a protected location ($q) and cannot be passed as a config file"; fi
	done
}

# ---------------------------------------------------------------- arguments
# Flags are passed through; flags with values are handled explicitly (hx syntax):
#   -c/--config FILE (bound read-only), --log FILE (bound read-write),
#   -w/--working-dir DIR (read-write work dir), -g/--grammar ACTION, --health [CATEGORY]
#   --config=, --log= and --working-dir= are accepted too (otherwise those paths are not mounted).
# Every other argument is a path, optionally with :line[:col].
work_targets=() # read-write: files and directories to open
work_dirs=()    # subset of work_targets that are directories
extra_rw=()     # read-write: --log file
ro_files=()     # read-only: -c file
new_files=()    # to be created as empty placeholders
hx_args=()
workdir=""

# add_target ARG ROLE (work|log): validate ARG and record it
add_target() {
	local a=$1 role=$2 path suffix="" abs kind
	path=$a
	if [[ "$role" == work && ! -e "$path" ]]; then
		# file:line:col first, then file:line
		if [[ "$a" =~ ^(.+)(:[0-9]+:[0-9]+)$ || "$a" =~ ^(.+)(:[0-9]+)$ ]]; then
			path="${BASH_REMATCH[1]}"
			suffix="${BASH_REMATCH[2]}"
		fi
	fi
	abs="$(realpath -m -- "$path")"
	if [[ -d "$abs" ]]; then
		kind=dir
	elif [[ -f "$abs" ]]; then
		kind="file"
	elif [[ -e "$abs" ]]; then
		die "not a regular file or directory: $abs"
	else
		[[ "$path" != */ ]] || die "directory does not exist: $path"
		[[ -d "$(dirname "$abs")" ]] || die "parent directory does not exist: $(dirname "$abs")"
		kind=new
		new_files+=("$abs")
	fi
	check_writable "$abs"

	if [[ "$role" == log ]]; then
		extra_rw+=("$abs")
	else
		work_targets+=("$abs")
		if [[ "$kind" == dir ]]; then work_dirs+=("$abs"); fi
		if [[ -z "$workdir" ]]; then
			if [[ "$kind" == dir ]]; then workdir="$abs"; else workdir="$(dirname "$abs")"; fi
		fi
	fi
	hx_args+=("$abs$suffix")
}

args=("$@")
i=0
end_of_flags=0
while ((i < ${#args[@]})); do
	a="${args[i]}"
	i=$((i + 1))
	if [[ $end_of_flags == 1 ]]; then
		add_target "$a" work
		continue
	fi
	case "$a" in
	--)
		end_of_flags=1
		hx_args+=("$a")
		;;
	-c | --config)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			abs="$(realpath -m -- "${args[i]}")"
			i=$((i + 1))
			[[ -f "$abs" ]] || die "config file not found: $abs"
			check_readable "$abs"
			ro_files+=("$abs")
			hx_args+=("$abs")
		fi
		;;
	--config=*)
		abs="$(realpath -m -- "${a#--config=}")"
		[[ -f "$abs" ]] || die "config file not found: $abs"
		check_readable "$abs"
		ro_files+=("$abs")
		hx_args+=(--config "$abs")
		;;
	--log)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			add_target "${args[i]}" log
			i=$((i + 1))
		fi
		;;
	--log=*)
		hx_args+=(--log)
		add_target "${a#--log=}" log
		;;
	-w | --working-dir)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			abs="$(realpath -m -- "${args[i]}")"
			i=$((i + 1))
			[[ -d "$abs" ]] || die "working directory not found: $abs"
			check_writable "$abs"
			work_targets+=("$abs")
			work_dirs+=("$abs")
			workdir="$abs"
			hx_args+=("$abs")
		fi
		;;
	--working-dir=*)
		abs="$(realpath -m -- "${a#--working-dir=}")"
		[[ -d "$abs" ]] || die "working directory not found: $abs"
		check_writable "$abs"
		work_targets+=("$abs")
		work_dirs+=("$abs")
		workdir="$abs"
		hx_args+=(--working-dir "$abs")
		;;
	-g | --grammar)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			[[ "${args[i]}" == fetch ]] && warn "--grammar fetch needs network; use HLX_NO_SANDBOX=1"
			hx_args+=("${args[i]}")
			i=$((i + 1))
		fi
		;;
	--grammar=*)
		[[ "${a#--grammar=}" == fetch ]] && warn "--grammar fetch needs network; use HLX_NO_SANDBOX=1"
		hx_args+=(--grammar "${a#--grammar=}")
		;;
	--health)
		hx_args+=("$a")
		if ((i < ${#args[@]})) && [[ "${args[i]}" != -* ]]; then
			hx_args+=("${args[i]}")
			i=$((i + 1))
		fi
		;;
	-* | +*) hx_args+=("$a") ;;
	*) add_target "$a" work ;;
	esac
done

# no path arguments: the cwd is the work dir
if [[ ${#work_targets[@]} -eq 0 ]]; then
	workdir="$(realpath "$PWD")"
	if ! err="$(check_writable "$workdir" 2>&1)"; then
		# quick edit from a forbidden place (e.g. $HOME): offer a scratch directory instead
		scratch=/tmp/hlx_scratchbook
		printf '%s\n' "$err" >&2
		[[ -t 0 && -t 2 ]] || exit 1
		ans=""
		read -rp "hlx: Open the scratch directory $scratch instead? [y/N] " ans || true
		[[ "$ans" == [yY] ]] || exit 1
		# /tmp is shared: never trust a pre-existing path that is not our own real directory
		if ! mkdir -m 700 -- "$scratch" 2>/dev/null; then
			[[ -d "$scratch" && ! -L "$scratch" && -O "$scratch" ]] || die "$scratch exists but is not a directory owned by you"
			chmod 700 -- "$scratch"
		fi
		workdir="$(realpath "$scratch")"
		check_writable "$workdir"
	fi
	work_targets+=("$workdir")
	work_dirs+=("$workdir")
fi

# ---------------------------------------------------------------- git repos
# Every repo containing a target is mounted read-only (targets are re-bound read-write on top).
# git runs unsandboxed here. Global config is not read. Command-line -c overrides local
# hooks, fsmonitor and file:// so the repo cannot run those. A timeout bounds a fifo .git.
# rev-parse does not run hooks.
git_ro=()    # whole repos, read-only, bound before the read-write targets
gitdir_ro=() # real git dirs of worktrees/submodules, read-only, bound after the targets
# worktree git dirs have HEAD + commondir and may not have objects (those live in the common dir)
looks_like_git_dir() {
	[[ -d "$1" && -e "$1/HEAD" ]] || return 1
	[[ -d "$1/objects" || -d "$1/refs" || -f "$1/commondir" || -e "$1/config" ]]
}
git_discover() {
	env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0 \
		timeout 10 git -c safe.directory='*' -c core.fsmonitor=false \
		-c core.hooksPath=/dev/null -c protocol.file.allow=never "$@"
}
if command -v git >/dev/null; then
	command -v timeout >/dev/null || die "timeout is needed to bound host-side git (coreutils)"
	for p in "${work_targets[@]}"; do
		d="$p"
		[[ -d "$d" ]] || d="$(dirname "$p")"
		root="$(git_discover -C "$d" rev-parse --show-toplevel 2>/dev/null)" || continue
		root="$(realpath -m -- "$root")"
		# worktrees/submodules keep their real git dir outside the work tree
		for opt in --absolute-git-dir --git-common-dir; do
			g="$(git_discover -C "$d" rev-parse "$opt" 2>/dev/null)" || continue
			[[ "$g" == /* ]] || g="$d/$g"
			g="$(realpath -m -- "$g")"
			within "$g" "$root" && continue
			# a .git file can point anywhere: never mount a system path or a non-git dir
			if [[ "$g" == / ]] || within "$HOME" "$g"; then continue; fi
			if is_system_location "$g"; then
				warn "ignoring git dir $g (system location)"
				continue
			fi
			if ! looks_like_git_dir "$g"; then
				warn "ignoring git dir $g (not git metadata)"
				continue
			fi
			skip_gitdir=0
			for q in "${deny[@]}"; do
				if within "$g" "$q" || within "$q" "$g"; then
					warn "ignoring git dir $g (overlaps protected path $q)"
					skip_gitdir=1
					break
				fi
			done
			[[ "$skip_gitdir" == 0 ]] || continue
			# this ro-bind is applied after the read-write binds, so an ancestor would hide them
			covers_rw=0
			for q in "${work_targets[@]}" "${extra_rw[@]}" "${rw_extra[@]}"; do
				if within "$q" "$g"; then
					warn "ignoring git dir $g (would cover writable path $q)"
					covers_rw=1
					break
				fi
			done
			[[ "$covers_rw" == 0 ]] || continue
			warn "mounting external git dir read-only: $g"
			gitdir_ro+=("$g")
		done
		# a repo at $HOME or above would expose everything; a repo opened as a whole needs nothing extra
		if [[ "$root" == / ]] || within "$HOME" "$root"; then continue; fi
		if is_system_location "$root"; then
			warn "ignoring git work tree $root (system location)"
			continue
		fi
		# a hostile core.worktree can make the "root" any directory: it has to contain the target
		if ! within "$p" "$root"; then
			warn "ignoring git work tree $root (does not contain $p)"
			continue
		fi
		for q in "${work_dirs[@]}"; do [[ "$q" == "$root" ]] && continue 2; done
		git_ro+=("$root")
	done
else
	warn "git not found; repositories are not mounted read-only"
fi
if ((${#git_ro[@]})); then
	mapfile -d '' -t git_ro < <(printf '%s\0' "${git_ro[@]}" | LC_ALL=C sort -zu) # parents before children
fi

# ---------------------------------------------------------------- seccomp
# The compiled filter is cached and rebuilt automatically when it is missing or older than
# seccomp.py / libseccomp, or when SECCOMP_ALLOW changed.
seccomp="${HLX_SECCOMP:-on}"
case "$seccomp" in
on)
	command -v python3 >/dev/null || die "python3 is needed to build the seccomp filter (or use HLX_SECCOMP=off)"
	seccomp_allow="$(IFS=,; echo "${SECCOMP_ALLOW[*]:-}")"
	seccomp_stale=0
	[[ -s "$seccomp_bpf" && "$seccomp_bpf" -nt "$HLX_DIR/seccomp.py" ]] || seccomp_stale=1
	[[ "$(cat "$seccomp_bpf.allow" 2>/dev/null || true)" == "$seccomp_allow" ]] || seccomp_stale=1
	for p in /usr/lib/*/libseccomp.so.2 /usr/lib64/libseccomp.so.2 /lib/*/libseccomp.so.2; do
		if [[ -e "$p" && "$p" -nt "$seccomp_bpf" ]]; then seccomp_stale=1; fi
	done
	if ((seccomp_stale)) && [[ "${HLX_DRY_RUN:-0}" != 1 ]]; then
		warn "building the seccomp filter"
		seccomp_args=(--out "$seccomp_bpf")
		if [[ -n "$seccomp_allow" ]]; then seccomp_args+=(--allow "$seccomp_allow"); fi
		(umask 077 && mkdir -p "$(dirname "$seccomp_bpf")")
		python3 "$HLX_DIR/seccomp.py" "${seccomp_args[@]}" || die "building the seccomp filter failed (HLX_SECCOMP=off disables it)"
		printf '%s\n' "$seccomp_allow" >"$seccomp_bpf.allow.$$"
		mv -f -- "$seccomp_bpf.allow.$$" "$seccomp_bpf.allow"
	fi
	;;
off) warn "seccomp filter disabled (HLX_SECCOMP=off)" ;;
*) die "invalid HLX_SECCOMP: $seccomp (use on or off)" ;;
esac

# ---------------------------------------------------------------- bwrap
bw=(bwrap --unshare-all --die-with-parent --clearenv --cap-drop ALL)
case "${HLX_NEW_SESSION:-on}" in
on) bw+=(--new-session) ;;
off) ;;
*) die "invalid HLX_NEW_SESSION: ${HLX_NEW_SESSION} (use on or off)" ;;
esac
if [[ "$seccomp" == on ]]; then bw+=(--seccomp 9); fi # fd 9 is opened right before the run

for d in /bin /sbin /lib /lib32 /lib64 /libx32; do
	if [[ -L "$d" ]]; then bw+=(--symlink "$(readlink "$d")" "$d"); fi
done
bw+=(--ro-bind /usr /usr --proc /proc --dev /dev --tmpfs /tmp)
for f in ld.so.cache ld.so.conf ld.so.conf.d passwd group nsswitch.conf localtime locale.alias terminfo alternatives; do
	bw+=(--ro-bind-try "/etc/$f" "/etc/$f")
done

# tmpfs $HOME must precede every bind located under it
bw+=(--tmpfs "$HOME")

# whole repos read-only first, so the targets below can be re-bound read-write inside them
for p in "${git_ro[@]}"; do bw+=(--ro-bind "$p" "$p"); done

# read-write: only the targets. Protected paths are mounted afterwards so that a
# read-write parent directory can never override them.
for p in "${work_targets[@]}" "${extra_rw[@]}" "${rw_extra[@]}"; do bw+=(--bind-try "$p" "$p"); done

for p in "${gitdir_ro[@]}"; do bw+=(--ro-bind-try "$p" "$p"); done

# read-only: AppImage contents, helix config (languages.toml can run commands), conda, lsps
bw+=(--ro-bind "$EXTRACT_DIR" "$EXTRACT_DIR")
bw+=(--ro-bind-try "$HELIX_CONFIG_DIR" "$HOME/.config/helix")
for p in "${ro_mounts[@]}" "${ro_files[@]}"; do bw+=(--ro-bind-try "$p" "$p"); done
bw+=(--bind "$SANDBOX_CACHE_DIR" "$HOME/.cache/helix")

# inside read-write dirs: .helix / .git read-only (and say so if a protected path is inside)
protect_names=(-name .helix)
if [[ "${HLX_GIT_RW:-0}" != 1 ]]; then protect_names+=(-o -name .git); fi
find_protected() {
	find "$1" -xdev -maxdepth "$PROTECT_DEPTH" -name node_modules -prune -o \( "${protect_names[@]}" \) -print0 -prune 2>/dev/null || true
}
declare -A known_protected=() # existing .git/.helix entries, to spot new ones after the session
lock_dirs=()                  # root-level .git/.helix that are (or will be) empty placeholder dirs
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p; do
		bw+=(--ro-bind "$p" "$p")
		known_protected["$p"]=1
	done < <(find_protected "$d")
	[[ -d "$d" ]] || continue
	for q in "${deny[@]}"; do
		if [[ "$q" != "$d" ]] && within "$q" "$d" && [[ -e "$q" ]]; then
			warn "$q is masked inside the sandbox"
			if [[ -d "$q" ]]; then bw+=(--tmpfs "$q"); else bw+=(--ro-bind /dev/null "$q"); fi
		fi
	done
	for q in "${ro_paths[@]}"; do
		if [[ "$q" != "$d" ]] && within "$q" "$d" && [[ -e "$q" ]]; then
			warn "$q is read-only inside the sandbox"
		fi
	done
done

# protected paths inside a read-only repo stay unreadable too (silent: the repo is only context)
for d in "${git_ro[@]}"; do
	for q in "${deny[@]}"; do
		if [[ "$q" != "$d" ]] && within "$q" "$d" && [[ -e "$q" ]]; then
			if [[ -d "$q" ]]; then bw+=(--tmpfs "$q"); else bw+=(--ro-bind /dev/null "$q"); fi
		fi
	done
done

# unix sockets (ssh-agent, docker, ...) are reachable through read-only mounts: mask them
find_sockets() {
	find "$1" -xdev -maxdepth "$PROTECT_DEPTH" -name node_modules -prune -o -type s -print0 2>/dev/null || true
}
for d in "${git_ro[@]}" "${work_dirs[@]}" "${rw_extra[@]}"; do
	[[ -d "$d" ]] || continue
	while IFS= read -r -d '' p; do
		warn "$p is a socket and is masked inside the sandbox"
		bw+=(--ro-bind /dev/null "$p")
	done < <(find_sockets "$d")
done

# Secret files (.env, .env.*, *.pem, *.key; not *.example/.sample/.template/.dist) are masked like
# sockets: a compromised language server could read them and yank them out. A file named on the
# command line is opened as asked, not masked. HLX_ALLOW_SECRETS=1 turns this off.
find_secrets() {
	find "$1" -xdev -maxdepth "$PROTECT_DEPTH" -name node_modules -prune -o -type f \
		\( -name .env -o -name '.env.*' -o -name '*.pem' -o -name '*.key' \) \
		! \( -name '*.example' -o -name '*.sample' -o -name '*.template' -o -name '*.dist' \) -print0 2>/dev/null || true
}
if [[ "${HLX_ALLOW_SECRETS:-0}" != 1 ]]; then
	for d in "${git_ro[@]}" "${work_dirs[@]}" "${rw_extra[@]}"; do
		[[ -d "$d" ]] || continue
		while IFS= read -r -d '' p; do
			for q in "${work_targets[@]}"; do
				if [[ "$p" == "$q" ]]; then continue 2; fi
			done
			for q in "${deny[@]}"; do
				if within "$p" "$q"; then continue 2; fi
			done
			warn "$p looks like a secrets file and is masked inside the sandbox (HLX_ALLOW_SECRETS=1 disables)"
			bw+=(--ro-bind /dev/null "$p")
		done < <(find_secrets "$d")
	done
fi

# A missing .helix/.git at a work dir root would otherwise be creatable by the sandbox, so an
# empty placeholder dir is created for it. Concurrent sessions share the placeholder: each
# holds a shared flock on it, and the last one out (exclusive lock) removes it.
for d in "${work_dirs[@]}"; do
	for p in "$d/.helix" "$d/.git"; do
		[[ "$p" != "$d/.git" || "${HLX_GIT_RW:-0}" != 1 ]] || continue
		if [[ ! -e "$p" && ! -L "$p" ]]; then
			lock_dirs+=("$p")
			known_protected["$p"]=1
			bw+=(--ro-bind "$p" "$p")
		elif [[ -d "$p" && ! -L "$p" && -z "$(ls -A -- "$p" 2>/dev/null)" ]]; then
			lock_dirs+=("$p") # possibly another session's placeholder: keep it alive while we run
		fi
	done
done

# environment
sandbox_path="$PATH"
bw+=(--setenv HOME "$HOME" --setenv TERM "${TERM:-xterm-256color}")
bw+=(--setenv GIT_OPTIONAL_LOCKS 0)
for v in LANG LANGUAGE LC_ALL LC_CTYPE LC_MESSAGES LC_COLLATE LC_NUMERIC LC_TIME LC_MONETARY LC_PAPER COLORTERM NO_COLOR USER LOGNAME \
	CONDA_PREFIX CONDA_DEFAULT_ENV MAMBA_ROOT_PREFIX VIRTUAL_ENV "${PASS_ENV[@]}"; do
	if [[ -n "${!v:-}" ]]; then bw+=(--setenv "$v" "${!v}"); fi
done

# clipboard
clip="${HLX_CLIPBOARD:-osc52}"
if [[ "${HLX_NO_CLIPBOARD:-0}" == 1 ]]; then clip=off; fi
case "$clip" in
wayland)
	# only the socket, inside a private runtime dir
	if [[ -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" && "$WAYLAND_DISPLAY" != /* &&
		-S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
		bw+=(--perms 0700 --tmpfs "$XDG_RUNTIME_DIR")
		bw+=(--bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY")
		bw+=(--setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY")
	fi
	;;
osc52)
	# helix picks its wayland provider when WAYLAND_DISPLAY is set and wl-copy/wl-paste exist
	[[ -x "$HLX_DIR/shims/wl-copy" && -x "$HLX_DIR/shims/wl-paste" ]] || die "missing clipboard shims in $HLX_DIR/shims"
	bw+=(--ro-bind "$HLX_DIR/shims" /opt/hlx-shims --setenv WAYLAND_DISPLAY wayland-hlx-osc52)
	sandbox_path="/opt/hlx-shims:$PATH"
	;;
off) ;;
*) die "invalid HLX_CLIPBOARD: $clip (use wayland, osc52 or off)" ;;
esac

bw+=(--setenv PATH "$sandbox_path")
if ((self_test)); then
	bw+=(--ro-bind "$HLX_DIR/selftest.sh" /opt/hlx/selftest.sh --ro-bind "$HLX_DIR/seccomp.py" /opt/hlx/seccomp.py)
	bw+=(--chdir "$workdir" -- bash /opt/hlx/selftest.sh)
else
	bw+=(--chdir "$workdir" -- "$EXTRACT_DIR/AppRun" "${hx_args[@]}")
fi

if [[ "${HLX_DRY_RUN:-0}" == 1 ]]; then
	printf '%q ' "${bw[@]}"
	echo
	exit 0
fi

# ---------------------------------------------------------------- run
declare -A created=()
declare -A lock_fd=() # placeholder dir -> fd holding our shared lock on it
placeholder_lock() { printf '%s/%s' "$lock_dir" "$(printf '%s' "$1" | sha256sum | cut -c1-32)"; }
# shellcheck disable=SC2317 # invoked via trap
cleanup() {
	local f fd lf
	for f in "${!created[@]}"; do
		# remove placeholders that were never written to
		if [[ -f "$f" && ! -s "$f" && "$(stat -c %.9Y "$f")" == "${created[$f]}" ]]; then rm -f -- "$f"; fi
	done
	for f in "${!lock_fd[@]}"; do
		fd="${lock_fd[$f]}"
		exec {fd}>&- # drop our shared lock, then remove the placeholder if nobody else holds one
		lf="$(placeholder_lock "$f")"
		# we are the last session: the placeholder goes, and so does its marker (also when
		# the dir was filled meanwhile, e.g. by git init, so a stale marker cannot delete a later empty dir)
		# shellcheck disable=SC2016 # $1/$2 belong to the inner sh
		flock -xn "$lf" sh -c 'if [ -e "$1" ]; then rmdir -- "$2" 2>/dev/null; rm -f -- "$1"; fi' sh "$lf.created" "$f" || true
	done
	if [[ -n "${ST_ROOT:-}" ]]; then rm -rf -- "$ST_ROOT"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

(umask 077 && mkdir -p "$SANDBOX_CACHE_DIR" && : >>"$SANDBOX_CACHE_DIR/.hlx-cache")
# shared lock for the whole session: --clean-cache refuses to run while one is held
if command -v flock >/dev/null; then
	(umask 077 && mkdir -p "$lock_dir")
	exec {cache_fd}>"$lock_dir/cache.lock"
	flock -s "$cache_fd"
fi
for f in "${new_files[@]}"; do
	# O_EXCL: do not follow a symlink planted at this path after the check above
	if ! (set -C; : >"$f") 2>/dev/null; then
		die "cannot create $f (refusing to follow a symlink or truncate an existing file)"
	fi
	created["$f"]="$(stat -c %.9Y "$f")"
done
if ((${#lock_dirs[@]})); then
	command -v flock >/dev/null || die "flock is needed (util-linux)"
	(umask 077 && mkdir -p "$lock_dir")
	for f in "${lock_dirs[@]}"; do
		exec {fd}>"$(placeholder_lock "$f")"
		flock -s "$fd"
		lock_fd["$f"]="$fd"
		# the dir may have been removed by another session since the bwrap command was built
		if mkdir -- "$f" 2>/dev/null; then : >"$(placeholder_lock "$f").created"; fi
		[[ -d "$f" && ! -L "$f" ]] || die "cannot create the placeholder directory $f (is its parent writable for you?)"
	done
fi

rc=0
# symlinks, to spot new or changed ones after the session (see LINKS)
find_links() { # prints PATH NUL TARGET NUL pairs
	find "$1" -xdev -maxdepth "$PROTECT_DEPTH" -name node_modules -prune -o -type l -printf '%p\0%l\0' 2>/dev/null || true
}
declare -A known_links=()
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p && IFS= read -r -d '' t; do known_links["$p"]="$t"; done < <(find_links "$d")
done
# files that other tools run or load automatically when started in this folder later (direnv,
# VS Code, Neovim, mise, git hooks managers): snapshot now, report new or changed ones afterwards
find_autorun() { # prints PATH NUL "MTIME SIZE" NUL pairs
	find "$1" -xdev -maxdepth "$PROTECT_DEPTH" -name node_modules -prune -o -type f \
		\( -name .envrc -o -name .nvim.lua -o -name .nvimrc -o -name .exrc -o -name .mise.toml -o -name mise.toml \
		-o -name .tool-versions -o -name .pre-commit-config.yaml \
		-o -path '*/.vscode/*' -o -path '*/.husky/*' -o -path '*/.devcontainer/*' \) \
		-printf '%p\0%T@ %s\0' 2>/dev/null || true
}
declare -A known_autorun=()
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p && IFS= read -r -d '' t; do known_autorun["$p"]="$t"; done < <(find_autorun "$d")
done
if [[ "$seccomp" == on ]]; then exec 9<"$seccomp_bpf"; fi
# the lock fds stay with this script (they must not leak into the sandbox)
(
	for fd in "${lock_fd[@]}"; do exec {fd}>&-; done
	if [[ -n "${cache_fd:-}" ]]; then exec {cache_fd}>&-; fi
	exec "${bw[@]}"
) || rc=$?

# .git/.helix entries that did not exist before (deeper than the root) cannot be pre-protected
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p; do
		if [[ -z "${known_protected[$p]:-}" ]]; then
			printf 'hlx: WARNING: %s was created during the session; it can run commands in unsandboxed hx/git, review or delete it\n' "$p" >&2
		fi
	done < <(find_protected "$d")
done

# a new symlink pointing out of the opened folders resolves on the host later: unsandboxed
# writes through it would hit the target. Links into read-only system and toolchain mounts (venv
# python, node_modules/.bin) are normal.
link_warned=0
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p && IFS= read -r -d '' t; do
		if [[ -n "${known_links[$p]+x}" && "${known_links[$p]}" == "$t" ]]; then continue; fi
		if [[ "$t" == /* ]]; then abs="$(realpath -m -- "$t")"; else abs="$(realpath -m -- "$(dirname -- "$p")/$t")"; fi
		skip_link=0
		for q in "${work_dirs[@]}" "${rw_extra[@]}" "${ro_paths[@]}" /usr /bin /sbin /lib /lib32 /lib64 /libx32 /dev /proc; do
			if within "$abs" "$q"; then skip_link=1; break; fi
		done
		[[ "$skip_link" == 0 ]] || continue
		link_warned=$((link_warned + 1))
		if ((link_warned <= 20)); then
			printf 'hlx: WARNING: symlink %s -> %s was created during the session and points outside the opened folders; review or delete it\n' "$p" "$t" >&2
		fi
	done < <(find_links "$d")
done
if ((link_warned > 20)); then printf 'hlx: WARNING: ... and %d more new symlinks pointing outside the opened folders\n' $((link_warned - 20)) >&2; fi

# auto-run files created or changed during the session
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p && IFS= read -r -d '' t; do
		if [[ -z "${known_autorun[$p]+x}" ]]; then
			printf 'hlx: WARNING: %s was created during the session; other tools may run or load it automatically, review it first\n' "$p" >&2
		elif [[ "${known_autorun[$p]}" != "$t" ]]; then
			printf 'hlx: WARNING: %s was changed during the session; other tools may run or load it automatically, review it first\n' "$p" >&2
		fi
	done < <(find_autorun "$d")
done

for f in "${lock_dirs[@]}"; do
	if [[ -d "$f" && -e "$(placeholder_lock "$f").created" && -n "$(ls -A -- "$f" 2>/dev/null)" ]]; then
		printf 'hlx: WARNING: %s was meant to stay empty but has content now; review or delete it\n' "$f" >&2
	fi
done

if ((self_test)); then
	# host side of the self-test: did anything escape the sandbox?
	echo "[host: nothing may have leaked out]"
	host_failed=0
	host_check() { # host_check DESCRIPTION COMMAND...
		local description=$1
		shift
		if "$@"; then printf '  ok    %s\n' "$description"; else printf '  FAIL  %s\n' "$description"; host_failed=1; fi
	}
	host_check "the write inside the opened folder reached the host" test -e "$HLX_ST_SUB/ok"
	host_check "nothing was written next to the repo" test ! -e "$HLX_ST_OUTSIDE/escape"
	host_check "nothing was written elsewhere in the repo" test ! -e "$HLX_ST_REPO/escape"
	host_check "no file was created inside .git" test ! -e "$HLX_ST_REPO/.git/escape"
	host_check "tracked.txt is unchanged (still 'one' + 'two')" test "$(tr '\n' ' ' <"$HLX_ST_REPO/tracked.txt")" == "one two "
	host_check "the repo history is unchanged (1 commit)" test "$(git -C "$HLX_ST_REPO" rev-list --count HEAD)" == 1
	host_check "the denied file still has its content" test "$(cat "$HLX_ST_DENIED")" == "top secret"
	host_check "the .env file still has its content" test "$(cat "$HLX_ST_ENV")" == "API_KEY=must-not-leak"
	host_check "a hardlink of tracked.txt was not created" test ! -e "$HLX_ST_SUB/via-hardlink"
	host_check "a hardlink of .git/HEAD was not created" test ! -e "$HLX_ST_SUB/via-git-head"
	host_check "the sandbox's \$HOME marker did not reach the host" test ! -e "$HOME/hlx-selftest-marker"
	if ((host_failed)); then rc=1; fi
	if ((rc == 0)); then echo "SELF-TEST PASSED"; else echo "SELF-TEST FAILED"; fi
fi
exit "$rc"

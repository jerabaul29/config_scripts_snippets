#!/usr/bin/env bash
# hlx: run the Helix editor (AppImage) inside a bubblewrap sandbox.
# On every edit of this file, run shfmt -d hlx.sh and shellcheck hlx.sh.
#
# USAGE
#   hlx [hx flags] [path[:line[:col]]]...
#   hlx --self-test            check that the sandbox really blocks what it should (see below)
#   HLX_NO_SANDBOX=1 hlx ...   run unsandboxed (needed e.g. for `--grammar fetch`, or to edit
#                              protected files such as the helix config itself)
#
# INSTALL
#   Add an alias to ~/.bashrc (adjust the path to where this script lives):
#     alias hlx='$HOME/path/to/scripts/hlx/hlx.sh'
#   Aliases only work in interactive shells; for non-interactive use (e.g. EDITOR=hlx git
#   commit) symlink the script into a PATH dir instead: ln -s /path/to/hlx.sh ~/.local/bin/hlx
#   Then create ~/.config/hlx/hlx.conf from hlx.conf.example and set HELIX_APPIMAGE.
#
# WHAT THE SANDBOX ALLOWS
#   - no network, no IPC, own PID namespace, new session (blocks TIOCSTI), cleared environment,
#     all capabilities dropped, no_new_privs, and a seccomp deny-list (seccomp.py, built with
#     libseccomp) for kernel calls such as ptrace, mount, io_uring, bpf, keyctl, unshare
#   - read-only: the extracted AppImage, the helix config, conda/mamba/venv prefixes, EXTRA_RO
#   - read-write: ONLY the things you ask to open:
#       * an existing file    -> that single file (helix writes in place)
#       * a new file          -> an empty placeholder file is created and that single file is
#                                bound; it is removed again on exit if it is still untouched
#       * a directory         -> that directory
#       * no path argument    -> the current directory
#     plus EXTRA_RW and the file given to --log. Everything else (including the rest of $HOME)
#     is invisible. $HOME is an empty tmpfs. Consequently helix can only see/write what was
#     passed on the command line: opening or saving-as other paths fails by design.
#   - git repositories: if a target lies inside a git repo (found with
#     `git rev-parse`, run with fsmonitor disabled), the whole repo including its `.git` is mounted
#     READ-ONLY, and only the targets you opened stay read-write on top of it. So started in a
#     subdir, only that subdir is writable; started at the repo root, the root is writable
#     except `.git`. Reading history and `git diff` work (GIT_OPTIONAL_LOCKS=0 avoids index
#     writes); commits/staging must be done outside. For worktrees/submodules (`.git` is a
#     file) the real git dir and the common dir are mounted read-only too. A repo rooted at
#     $HOME or above is ignored (it would expose all of $HOME).
#   - inside a read-write directory, existing `.git` and `.helix` entries (up to
#     PROTECT_DEPTH levels deep, same filesystem, not inside node_modules; `.git` unless
#     HLX_GIT_RW=1, which only affects a repo root that is itself opened read-write) and any
#     DENY_PATHS entries are mounted read-only / masked. A missing root-level `.git`/`.helix`
#     is covered by an empty read-only placeholder dir that is removed on exit (concurrent
#     sessions in the same dir share it, so the first one to exit removes it). Missing ones
#     deeper down cannot be pre-protected, so any new one is reported after the session
#     (review it before running hx or git there). Entries deeper than PROTECT_DEPTH are
#     neither protected nor reported.
#   - DENY_PATHS always includes hlx.sh's own directory, the hlx config dir and the AppImage,
#     since those run unsandboxed on the next invocation.
#   - refused outright: "/", $HOME or any ancestor of it, system dirs (/tmp, /var, /run, /etc,
#     /usr, /dev, /proc, /sys, ... they can hold sockets or host state), DENY_PATHS entries,
#     anything inside the read-only locations above or inside a .git/.helix dir (files too),
#     and any directory that contains a not-yet-existing protected path (it could be created
#     from inside). Use HLX_NO_SANDBOX=1 to edit those.
#
# CONFIGURATION (environment, or the optional file $HLX_CONFIG, default
# ~/.config/hlx/hlx.conf, which is sourced as bash before the sandbox starts; see
# hlx.conf.example). Nothing is hardcoded: HELIX_APPIMAGE has to be set.
#   HELIX_APPIMAGE     path of the Helix AppImage (required)
#   HELIX_CONFIG_DIR   helix config dir, mounted read-only at ~/.config/helix
#   SANDBOX_CACHE_DIR  the only persistent writable dir (mounted at ~/.cache/helix)
#   CONDA_DIRS         read-only conda/mamba roots; active CONDA_PREFIX, MAMBA_ROOT_PREFIX and
#                      VIRTUAL_ENV are added automatically
#   EXTRA_RO / EXTRA_RW  extra read-only / read-write paths (e.g. language servers, caches)
#   DENY_PATHS         never writable, masked inside read-write dirs (credentials, shell rc, ...)
#   PASS_ENV           extra environment variable names to pass through
#   PROTECT_DEPTH      how deep to look for .git/.helix inside read-write directories
#   SECCOMP_ALLOW      syscall names from the seccomp.py deny list to allow after all
#
# ENVIRONMENT TOGGLES
#   HLX_DRY_RUN=1      print the bwrap command and exit (creates nothing, but a missing AppImage
#                      extraction is still offered first; --self-test still builds its temp repo)
#   HLX_NO_SANDBOX=1   run helix directly, no sandbox
#   HLX_GIT_RW=1       leave the .git of an opened repo root writable
#   HLX_SECCOMP=on|off (default on) the seccomp filter is compiled automatically into
#                      "<SANDBOX_CACHE_DIR>-seccomp-<arch>.bpf" (deliberately outside the
#                      directory the sandbox can write) and rebuilt whenever seccomp.py,
#                      libseccomp or SECCOMP_ALLOW changed. Needs python3 + libseccomp2.
#   HLX_CLIPBOARD=wayland|osc52|off   (default wayland; HLX_NO_CLIPBOARD=1 is the same as off)
#       wayland: bind only $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY into a private tmpfs runtime dir.
#                There is no network, so no direct exfiltration, but a Wayland client can do
#                whatever the compositor lets it: read the clipboard (GNOME: only while
#                focused; KDE/wlroots data-control: anytime), overwrite it (paste-jacking) and,
#                depending on the compositor, screencopy or virtual input. Best-effort only.
#       osc52:   no Wayland socket at all. shims/wl-copy sends yanks to the terminal as OSC 52
#                (needs a terminal that supports it; GNOME Terminal does not), shims/wl-paste
#                always fails, so paste with the terminal (Ctrl+Shift+V). Recommended.
#       off:     no system clipboard.
#
# NOTES
#   - A HELIX_CONFIG_DIR made of symlinks (stow, dotfile managers) has dangling links inside
#     the sandbox unless their targets are added to EXTRA_RO.
#   - Ctrl-Z does not suspend helix (the sandbox has no controlling terminal), and anything
#     in your helix config that needs host services (e.g. tmux sockets) will not work.
#   - The sandbox is only as good as what you open: treat the contents of a read-write
#     directory as untrusted after a session (Makefiles, .envrc, scripts, ...).
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
#   read-only repo, masked paths, git), then verifies on the host that nothing leaked out.
#   Run it after changing this script, the config, bubblewrap or the kernel. Exit status 0 = all ok.
#
# NOT IMPLEMENTED YET
#   - masking of .env files inside read-write directories
#   - seccomp: more denied calls / an allow-list (see the TODO in seccomp.py)
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
PROTECT_DEPTH=4
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

# informational flags need no sandbox
for a in "$@"; do
	case "$a" in
	--) break ;;
	-V | --version | -h | --help) exec "$EXTRACT_DIR/AppRun" "$@" ;;
	esac
done

if [[ "${HLX_NO_SANDBOX:-0}" == 1 ]]; then
	exec "$EXTRACT_DIR/AppRun" "$@"
fi

command -v bwrap >/dev/null || die "bwrap not installed (sudo apt install bubblewrap)"

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
deny+=("$seccomp_bpf" "$seccomp_bpf.allow")

# ---------------------------------------------------------------- self-test setup
# Builds a throwaway repo and then continues as if `hlx <repo>/sub` had been started; the
# command run inside the sandbox is selftest.sh instead of helix (see the end of the bwrap part).
self_test=0
if [[ "${1:-}" == --self-test ]]; then
	[[ $# -eq 1 ]] || die "--self-test takes no other arguments"
	[[ "${HLX_NO_SANDBOX:-0}" != 1 ]] || die "--self-test cannot be combined with HLX_NO_SANDBOX=1"
	[[ -f "$HLX_DIR/selftest.sh" ]] || die "missing $HLX_DIR/selftest.sh"
	command -v git >/dev/null || die "--self-test needs git"
	self_test=1
	ST_ROOT="$(mktemp -d "$SANDBOX_CACHE_DIR.selftest.XXXXXX")"
	trap 'rm -rf -- "$ST_ROOT"' EXIT
	ST_ROOT="$(realpath -- "$ST_ROOT")"
	HLX_ST_REPO="$ST_ROOT/repo"
	HLX_ST_SUB="$HLX_ST_REPO/sub"
	HLX_ST_OUTSIDE="$ST_ROOT/outside"
	HLX_ST_DENIED="$HLX_ST_SUB/denied.txt"
	mkdir -p "$HLX_ST_SUB" "$HLX_ST_OUTSIDE"
	echo canary >"$HLX_ST_OUTSIDE/canary"
	echo "top secret" >"$HLX_ST_DENIED"
	echo one >"$HLX_ST_REPO/tracked.txt"
	git_st=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$HLX_ST_REPO" -c user.name=hlx -c user.email=hlx@localhost)
	"${git_st[@]}" init -q --template=
	"${git_st[@]}" add tracked.txt
	"${git_st[@]}" commit -q -m initial
	echo two >>"$HLX_ST_REPO/tracked.txt" # uncommitted change for the `git diff` test
	export HLX_ST_REPO HLX_ST_SUB HLX_ST_OUTSIDE HLX_ST_DENIED
	export HLX_ST_SECRET=must-not-leak # not in PASS_ENV: has to stay outside
	PASS_ENV+=(HLX_ST_REPO HLX_ST_SUB HLX_ST_OUTSIDE HLX_ST_DENIED)
	deny+=("$HLX_ST_DENIED")
	set -- "$HLX_ST_SUB"
fi

# check_writable ABS: refuse targets that must never be (made) writable
check_writable() {
	local p=$1 q
	if [[ "$p" == / ]] || { [[ -d "$p" ]] && within "$HOME" "$p"; }; then
		die "refusing to bind $p read-write (it is / or contains \$HOME); open a specific file or a project directory"
	fi
	case "$p" in
	/tmp | /var | /opt | /mnt | /media | /srv | /boot | /run | /run/* | /etc | /etc/* | /usr | /usr/* | /dev | /dev/* | /proc | /proc/* | /sys | /sys/* | /bin | /bin/* | /sbin | /sbin/* | /lib* | /snap | /snap/*)
		die "$p is a system location (may hold sockets or host state); to edit it use: HLX_NO_SANDBOX=1 hlx ..." ;;
	esac
	case "$p" in
	*/.helix | */.helix/*) die "$p is workspace config that can run commands; to edit it use: HLX_NO_SANDBOX=1 hlx ..." ;;
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

# ---------------------------------------------------------------- arguments
# Flags are passed through; flags with values are handled explicitly (hx syntax):
#   -c/--config FILE (bound read-only), --log FILE (bound read-write),
#   -w/--working-dir DIR (read-write work dir), -g/--grammar ACTION, --health [CATEGORY]
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
			ro_files+=("$abs")
			hx_args+=("$abs")
		fi
		;;
	--log)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			add_target "${args[i]}" log
			i=$((i + 1))
		fi
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
	-g | --grammar)
		hx_args+=("$a")
		if ((i < ${#args[@]})); then
			hx_args+=("${args[i]}")
			i=$((i + 1))
		fi
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
	check_writable "$workdir"
	work_targets+=("$workdir")
	work_dirs+=("$workdir")
fi

# ---------------------------------------------------------------- git repos
# Every repo containing a target is mounted read-only (targets are re-bound read-write on top).
# git runs unsandboxed here, so fsmonitor is disabled and no hooks are involved (rev-parse).
git_ro=()   # whole repos, read-only, bound before the read-write targets
gitdir_ro=() # real git dirs of worktrees/submodules, read-only, bound after the targets
if command -v git >/dev/null; then
	for p in "${work_targets[@]}"; do
		d="$p"
		[[ -d "$d" ]] || d="$(dirname "$p")"
		root="$(git -c core.fsmonitor=false -C "$d" rev-parse --show-toplevel 2>/dev/null)" || continue
		root="$(realpath -m -- "$root")"
		# worktrees/submodules keep their real git dir outside the work tree
		for opt in --absolute-git-dir --git-common-dir; do
			g="$(git -c core.fsmonitor=false -C "$d" rev-parse "$opt" 2>/dev/null)" || continue
			[[ "$g" == /* ]] || g="$d/$g"
			g="$(realpath -m -- "$g")"
			within "$g" "$root" && continue
			# a hostile `.git` file can point anywhere: never expose protected locations through it
			if [[ "$g" == / ]] || within "$HOME" "$g"; then continue; fi
			for q in "${deny[@]}"; do
				if within "$g" "$q" || within "$q" "$g"; then
					warn "ignoring git dir $g (overlaps protected path $q)"
					continue 2
				fi
			done
			gitdir_ro+=("$g")
		done
		# a repo at $HOME or above would expose everything; a repo opened as a whole needs nothing extra
		if [[ "$root" == / ]] || within "$HOME" "$root"; then continue; fi
		for q in "${work_dirs[@]}"; do [[ "$q" == "$root" ]] && continue 2; done
		git_ro+=("$root")
	done
else
	warn "git not found; repositories are not mounted read-only"
fi
if ((${#git_ro[@]})); then
	mapfile -d '' -t git_ro < <(printf '%s\0' "${git_ro[@]}" | sort -zu) # parents before children
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
		mkdir -p "$(dirname "$seccomp_bpf")"
		python3 "$HLX_DIR/seccomp.py" "${seccomp_args[@]}" || die "building the seccomp filter failed (HLX_SECCOMP=off disables it)"
		printf '%s\n' "$seccomp_allow" >"$seccomp_bpf.allow"
	fi
	;;
off) warn "seccomp filter disabled (HLX_SECCOMP=off)" ;;
*) die "invalid HLX_SECCOMP: $seccomp (use on or off)" ;;
esac

# ---------------------------------------------------------------- bwrap
bw=(bwrap --unshare-all --die-with-parent --new-session --clearenv --cap-drop ALL)
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
placeholder_dirs=()           # empty dirs created at the work dir root, removed again on exit
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

# a missing .helix/.git at a work dir root would otherwise be creatable by the sandbox
for d in "${work_dirs[@]}"; do
	for p in "$d/.helix" "$d/.git"; do
		[[ "$p" != "$d/.git" || "${HLX_GIT_RW:-0}" != 1 ]] || continue
		if [[ ! -e "$p" && ! -L "$p" ]]; then
			placeholder_dirs+=("$p")
			known_protected["$p"]=1
			bw+=(--ro-bind "$p" "$p")
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
clip="${HLX_CLIPBOARD:-wayland}"
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

# fail early with a useful hint if namespaces are blocked (Ubuntu AppArmor)
if ! err="$(bwrap --ro-bind / / --unshare-all --die-with-parent true 2>&1)"; then
	if [[ "$err" == *"uid map"* || "$err" == *"Permission denied"* ]]; then
		die "bwrap cannot create user namespaces (Ubuntu AppArmor restriction). Install a bwrap profile:
  sudo apt install apparmor-profiles apparmor-utils
  sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
  sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict"
	fi
	die "bwrap self-check failed: $err"
fi

# ---------------------------------------------------------------- run
declare -A created=()
# shellcheck disable=SC2317 # invoked via trap
cleanup() {
	local f
	for f in "${!created[@]}"; do
		# remove placeholders that were never written to
		if [[ -f "$f" && ! -s "$f" && "$(stat -c %.9Y "$f")" == "${created[$f]}" ]]; then rm -f -- "$f"; fi
	done
	for f in "${placeholder_dirs[@]}"; do rmdir -- "$f" 2>/dev/null || true; done
	if [[ -n "${ST_ROOT:-}" ]]; then rm -rf -- "$ST_ROOT"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

mkdir -p "$SANDBOX_CACHE_DIR"
for f in "${new_files[@]}"; do
	touch -- "$f"
	created["$f"]="$(stat -c %.9Y "$f")"
done
for f in "${placeholder_dirs[@]}"; do mkdir -- "$f"; done

rc=0
if [[ "$seccomp" == on ]]; then exec 9<"$seccomp_bpf"; fi
"${bw[@]}" || rc=$?

# .git/.helix entries that did not exist before (deeper than the root) cannot be pre-protected
for d in "${work_dirs[@]}" "${rw_extra[@]}"; do
	while IFS= read -r -d '' p; do
		if [[ -z "${known_protected[$p]:-}" ]]; then
			printf 'hlx: WARNING: %s was created during the session; it can run commands in unsandboxed hx/git, review or delete it\n' "$p" >&2
		fi
	done < <(find_protected "$d")
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
	host_check "the sandbox's \$HOME marker did not reach the host" test ! -e "$HOME/hlx-selftest-marker"
	if ((host_failed)); then rc=1; fi
	if ((rc == 0)); then echo "SELF-TEST PASSED"; else echo "SELF-TEST FAILED"; fi
fi
exit "$rc"

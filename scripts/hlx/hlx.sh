#!/usr/bin/env bash
# On every edit of this file, run shfmt -d hlx.sh and shellcheck hlx.sh.

set -Eeuo pipefail
shopt -s nullglob

# by now, we want to robustify this with bubblewrap:
# - no network whatsoever
# - read only, only the relevant locations: the location of helix, the location of helix config and language, the conda / mamba folders
# - if no argument provided, the cwd is read write - this is where we work
# - if a list of file is provided, the list of files is read write - this is where we work
# - also have a config array of paths to e.g. lsps, that can be maintained for example by the user, that is read only
# - everything else is off-borders
# - a compromised or malicious helix should not be able to read any sensitive file, even less write them, and should  not be able to exfiltrate anything
# - all lsps used should be local only anyways, so no loss of functionality
#
# design decisions:
# - target: Ubuntu 24.04+, Wayland only
# - AppImage: look for ".extracted" next to the AppImage; if present use it (no FUSE),
#   else prompt y/N to run `--appimage-extract` and rename squashfs-root to .extracted;
#   abort if there is no TTY. Set HELIX_RUNTIME to the extracted runtime dir.
# - Ubuntu 24.04 blocks unprivileged userns via AppArmor: bwrap needs a profile with `userns,`
#   (detect "setting up uid map: Permission denied" and print the fix)
# - clipboard: bind only $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY (not the whole runtime dir) into a
#   tmpfs XDG_RUNTIME_DIR. No network, so no direct exfiltration, but the sandbox can read the
#   clipboard (on GNOME only while focused; with data-control on KDE/wlroots anytime) and can
#   overwrite it (paste-jacking).
#
# further hardening (not implemented yet):
# - --clearenv and pass through only TERM, HOME, PATH, LANG, COLORTERM, conda vars
# - --unshare-all --die-with-parent --new-session (blocks TIOCSTI)
# - tmpfs $HOME, ro-bind only ~/.config/helix; dedicated writable cache dir
# - refuse to run when cwd is $HOME or /
# - bind .git (or .git/hooks and .git/config) read-only; mask .env files with /dev/null
# - seccomp filter blocking ptrace, io_uring, keyctl, etc.
# - clipboard opt-out flag (--no-clipboard) that omits the Wayland socket
# - --dry-run to print the bwrap command; --no-sandbox escape hatch; exec bwrap
# - self-test: curl fails, ~/.ssh unreadable, writes outside the work tree fail
# - optional: run under a dedicated cgroup / systemd-run --user for resource limits

# NOTE that dedicated ubuntu apparmor profile for bwrap is necessary! it may or may not be installed by default (on 24 it is not, should be on 26)
# sudo apt install apparmor-profiles apparmor-utils
# sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
# sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
# bwrap --ro-bind / / --unshare-all --die-with-parent true && echo OK


# ---------------------------------------------------------------- config
HELIX_APPIMAGE="${HELIX_APPIMAGE:-/home/jeanr/Desktop/Software/HelixEditor/helix-25.07.1-x86_64.AppImage}"
HELIX_CONFIG_DIR="${HELIX_CONFIG_DIR:-$HOME/.config/helix}"
SANDBOX_CACHE_DIR="${SANDBOX_CACHE_DIR:-$HOME/.cache/hlx-sandbox}" # only writable place besides the work files

# read-only: conda / mamba installs
CONDA_DIRS=("$HOME/conda" "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/mambaforge" "$HOME/.local/share/mamba")
# read-only: extra paths, e.g. locally installed lsps (maintain here)
EXTRA_RO=()
# read-write: extra paths, e.g. lsp caches
EXTRA_RW=()

# env toggles: HLX_DRY_RUN=1, HLX_NO_SANDBOX=1, HLX_NO_CLIPBOARD=1, HLX_GIT_RW=1

# ---------------------------------------------------------------- helpers
die() { printf 'hlx: %s\n' "$*" >&2; exit 1; }

# extracted AppImage (avoids FUSE, which bwrap cannot use)
EXTRACT_DIR="$(dirname "$HELIX_APPIMAGE")/.extracted"
if [[ ! -x "$EXTRACT_DIR/AppRun" ]]; then
  [[ -f "$HELIX_APPIMAGE" ]] || die "AppImage not found: $HELIX_APPIMAGE"
  [[ -t 0 ]] || die "$EXTRACT_DIR missing and no TTY to ask; extract manually"
  read -rp "hlx: $EXTRACT_DIR not found. Extract the AppImage there? [y/N] " ans
  [[ "$ans" == [yY] ]] || die "aborted"
  tmp="$(mktemp -d "$(dirname "$HELIX_APPIMAGE")/.extract.XXXXXX")"
  (cd "$tmp" && "$HELIX_APPIMAGE" --appimage-extract >/dev/null) || { rm -rf "$tmp"; die "extraction failed"; }
  mv "$tmp/squashfs-root" "$EXTRACT_DIR" && rmdir "$tmp"
fi

if [[ "${HLX_NO_SANDBOX:-0}" == 1 ]]; then
  exec "$EXTRACT_DIR/AppRun" "$@"
fi

command -v bwrap >/dev/null || die "bwrap not installed (sudo apt install bubblewrap)"

# ---------------------------------------------------------------- work paths
# Flags are passed through untouched. Every other argument is treated as a path
# (so values of flags like -c/--config are treated as paths too).
# Existing file: bound rw as a single file (helix writes in place).
# New file: its parent dir is bound rw. Directory: bound rw.
rw_paths=()
hx_args=()
workdir=""

if [[ $# -gt 0 ]]; then
  end_of_flags=0
  for a in "$@"; do
    if [[ $end_of_flags == 0 && "$a" == -- ]]; then end_of_flags=1; hx_args+=("$a"); continue; fi
    if [[ $end_of_flags == 0 && ( "$a" == -* || "$a" == +* ) ]]; then hx_args+=("$a"); continue; fi

    path="$a" suffix=""
    if [[ ! -e "$path" ]]; then
      # file:line:col first, then file:line
      if [[ "$a" =~ ^(.+)(:[0-9]+:[0-9]+)$ || "$a" =~ ^(.+)(:[0-9]+)$ ]]; then
        path="${BASH_REMATCH[1]}" suffix="${BASH_REMATCH[2]}"
      fi
    fi
    abs="$(realpath -m "$path")"
    if [[ -d "$abs" ]]; then
      bind="$abs"
    elif [[ -e "$abs" ]]; then
      bind="$abs"
    else
      bind="$(dirname "$abs")"
      [[ -d "$bind" ]] || die "parent directory does not exist: $bind"
    fi
    [[ "$bind" != "/" && "$bind" != "$(realpath "$HOME")" ]] || die "refusing to bind $bind read-write"
    rw_paths+=("$bind")
    [[ -n "$workdir" ]] || { [[ -d "$abs" ]] && workdir="$abs" || workdir="$(dirname "$abs")"; }
    hx_args+=("$abs$suffix")
  done
fi

# no path arguments (none, or only flags): the cwd is the work dir
if [[ ${#rw_paths[@]} -eq 0 ]]; then
  workdir="$(realpath "$PWD")"
  [[ "$workdir" != "/" && "$workdir" != "$(realpath "$HOME")" ]] \
    || die "refusing to use $workdir as read-write work dir; pass files or cd elsewhere"
  rw_paths+=("$workdir")
fi

# ---------------------------------------------------------------- bwrap
mkdir -p "$SANDBOX_CACHE_DIR"

bw=(bwrap --unshare-all --die-with-parent --new-session --clearenv)

for d in /bin /sbin /lib /lib32 /lib64 /libx32; do
  if [[ -L "$d" ]]; then bw+=(--symlink "$(readlink "$d")" "$d"); fi
done
bw+=(--ro-bind /usr /usr --proc /proc --dev /dev --tmpfs /tmp)
for f in ld.so.cache ld.so.conf ld.so.conf.d passwd group nsswitch.conf localtime locale.alias terminfo alternatives; do
  bw+=(--ro-bind-try "/etc/$f" "/etc/$f")
done

# tmpfs $HOME must precede every bind located under it
bw+=(--tmpfs "$HOME")

# work paths (rw); protected read-only paths are mounted afterwards so that a
# rw parent directory can never override them
for p in "${rw_paths[@]}" "${EXTRA_RW[@]}"; do bw+=(--bind-try "$p" "$p"); done

# AppImage contents, helix config (languages.toml can run commands), conda, lsps
bw+=(--ro-bind "$EXTRACT_DIR" "$EXTRACT_DIR")
bw+=(--ro-bind-try "$HELIX_CONFIG_DIR" "$HELIX_CONFIG_DIR")
for p in "${CONDA_DIRS[@]}" "${EXTRA_RO[@]}"; do bw+=(--ro-bind-try "$p" "$p"); done
bw+=(--bind "$SANDBOX_CACHE_DIR" "$HOME/.cache/helix")

# protect .git metadata unless HLX_GIT_RW=1
if [[ "${HLX_GIT_RW:-0}" != 1 ]]; then
  for p in "${rw_paths[@]}"; do
    if [[ -d "$p/.git" ]]; then bw+=(--ro-bind "$p/.git" "$p/.git"); fi
  done
fi

# environment
bw+=(--setenv HOME "$HOME" --setenv PATH "$PATH" --setenv TERM "${TERM:-xterm-256color}")
for v in LANG LC_ALL COLORTERM; do
  if [[ -n "${!v:-}" ]]; then bw+=(--setenv "$v" "${!v}"); fi
done

# wayland clipboard: only the socket, inside a private runtime dir
if [[ "${HLX_NO_CLIPBOARD:-0}" != 1 && -n "${WAYLAND_DISPLAY:-}" && -n "${XDG_RUNTIME_DIR:-}" \
      && -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
  bw+=(--perms 0700 --tmpfs "$XDG_RUNTIME_DIR")
  bw+=(--bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY")
  bw+=(--setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY")
fi

bw+=(--chdir "$workdir" -- "$EXTRACT_DIR/AppRun" "${hx_args[@]}")

if [[ "${HLX_DRY_RUN:-0}" == 1 ]]; then
  printf '%q ' "${bw[@]}"; echo
  exit 0
fi

# fail early with a useful hint if namespaces are blocked (Ubuntu AppArmor)
bwrap --ro-bind / / --unshare-all --die-with-parent true 2>/dev/null \
  || die "bwrap cannot create namespaces (Ubuntu AppArmor userns restriction?); see notes in this script"

exec "${bw[@]}"


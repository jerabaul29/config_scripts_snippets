#!/usr/bin/env bash
# Run the verified latest Joplin AppImage in a Bubblewrap sandbox.
# Sandbox policy: read-only system runtime and AppImage; ephemeral writable home
# and /tmp; persistent read/write access only to Joplin's data directory; access
# to one Wayland socket (no X11); host timezone, locale, and GTK theme values; shared host
# networking, not restricted to Joplin Cloud.

set -Eeuo pipefail
shopt -s nullglob
IFS=$'\n\t'
umask 077

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}
trap 'die "command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

[[ -n "${HOME:-}" && -d "${HOME}" ]] || die "HOME is not set or not a directory"

readonly JOPLIN_DIR="${HOME}/Desktop/Software/Joplin"
readonly JOPLIN_DATA_DIR="${HOME}/.config/joplin-desktop"
readonly SHARE_DIR="/tmp/joplin_sharedrop"
readonly RELEASES_URL="https://github.com/laurent22/joplin/releases/latest"
readonly TAG_REGEX='https://github\.com/laurent22/joplin/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)'
readonly FILE_REGEX='^Joplin-([0-9]+\.[0-9]+\.[0-9]+)\.AppImage$'
readonly PROCESS_REGEX='Joplin-[0-9]+\.[0-9]+\.[0-9]+\.AppImage|/opt/Joplin\.AppImage|/\.mount_[Jj]oplin'

for cmd in wget sha512sum sort tail basename pgrep setsid id mkdir chmod sleep readlink stat head bwrap; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done
[[ -d "$JOPLIN_DIR" ]] || die "directory not found: $JOPLIN_DIR"

# Target: Ubuntu 24.04+ (merged /usr, so /bin, /lib and /lib64 are symlinks into /usr).
[[ -r /etc/os-release ]] || die "/etc/os-release is not readable"
os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
[[ "$os_id" == ubuntu ]] || die "this script targets Ubuntu (found: ${os_id:-unknown})"
[[ "$os_version" =~ ^[0-9]+\.[0-9]+$ ]] || die "unexpected Ubuntu VERSION_ID: $os_version"
[[ "$(printf '%s\n24.04\n' "$os_version" | sort -V | head -n 1)" == 24.04 ]] \
    || die "Ubuntu 24.04 or newer is required (found: $os_version)"
for link in /bin /lib /lib64; do
    [[ -L "$link" ]] || die "merged-/usr layout expected, but $link is not a symlink"
done
[[ -d /usr && -d /etc ]] || die "required system runtime directories are missing"

# 1. Latest local AppImage, by version in file name.
declare -a versions=()
for f in "$JOPLIN_DIR"/Joplin-*.AppImage; do
    name="$(basename "$f")"
    if [[ "$name" =~ $FILE_REGEX ]]; then
        versions+=("${BASH_REMATCH[1]}")
    fi
done
((${#versions[@]} > 0)) || die "no Joplin-X.Y.Z.AppImage found in $JOPLIN_DIR"

local_version="$(printf '%s\n' "${versions[@]}" | sort -V | tail -n 1)"
[[ -n "$local_version" ]] || die "could not determine latest local version"
appimage="${JOPLIN_DIR}/Joplin-${local_version}.AppImage"
sha_file="${appimage}.sha512"

[[ -f "$appimage" && -x "$appimage" ]] || die "AppImage missing or not executable: $appimage"
# Refuse files that others could have tampered with.
for f in "$appimage" "$sha_file"; do
    [[ -f "$f" && ! -L "$f" && -O "$f" ]] || die "must be a regular file owned by the current user (no symlink): $f"
    mode="$(stat -c '%a' -- "$f")" || die "could not stat $f"
    (((8#$mode & 8#022) == 0)) || die "file must not be group/world writable ($mode): $f"
done
printf 'Latest local AppImage: %s (version %s)\n' "$appimage" "$local_version"

# 2. Verify the matching checksum file has exactly one entry for this AppImage.
[[ -f "$sha_file" ]] || die "checksum file not found: $sha_file"
checksum_line="$(<"$sha_file")"
[[ "$checksum_line" != *$'\n'* ]] || die "checksum file must contain exactly one entry: $sha_file"
[[ "$checksum_line" =~ ^([[:xdigit:]]{128})[[:space:]]+\*?(.+)$ ]] \
    || die "checksum file has an invalid SHA-512 entry: $sha_file"
[[ "${BASH_REMATCH[2]}" == "$(basename "$appimage")" ]] \
    || die "checksum file does not name $(basename "$appimage"): $sha_file"
if ! sha_out="$(cd "$JOPLIN_DIR" && sha512sum -c -- "$(basename "$sha_file")" 2>&1)"; then
    die "sha512 verification FAILED for $appimage: $sha_out"
fi
printf 'sha512 check OK: %s\n' "$sha_out"

# 3. Fetch the latest GitHub release.
page="$(wget -qO- --https-only --max-redirect=5 --timeout=30 --tries=2 "$RELEASES_URL")" || die "wget failed for $RELEASES_URL"
[[ -n "$page" ]] || die "empty response from $RELEASES_URL"
[[ "$page" =~ $TAG_REGEX ]] || die "no release tag URL found in response from $RELEASES_URL"
latest_version="${BASH_REMATCH[1]}"
printf 'Latest GitHub release: %s\n' "$latest_version"

# 4. Require an up-to-date local AppImage.
[[ "$local_version" == "$latest_version" ]] \
    || die "local version ($local_version) differs from latest release ($latest_version); please update"
printf 'Confirmed: local AppImage is up to date (%s)\n' "$latest_version"

# 5. Make sure Joplin is not already running.
rc=0
running="$(pgrep -u "$(id -u)" -af "$PROCESS_REGEX" 2>&1)" || rc=$?
if ((rc == 0)); then
    die "Joplin appears to be already running:
${running}"
elif ((rc != 1)); then
    die "pgrep failed (exit code $rc): $running"
fi
printf 'Confirmed: Joplin is not already running\n'

# 6. Assemble a minimal runtime and prepare the persistent data directory.
mkdir -p -- "$JOPLIN_DATA_DIR"
[[ -r "$JOPLIN_DATA_DIR" && -w "$JOPLIN_DATA_DIR" ]] \
    || die "Joplin data directory must be readable and writable: $JOPLIN_DATA_DIR"

if [[ -L "$SHARE_DIR" ]]; then
    die "sharedrop path must not be a symbolic link: $SHARE_DIR"
elif [[ ! -e "$SHARE_DIR" ]]; then
    mkdir -m 700 -- "$SHARE_DIR" || die "could not create sharedrop directory: $SHARE_DIR"
fi
[[ -d "$SHARE_DIR" && -O "$SHARE_DIR" && ! -L "$SHARE_DIR" ]] \
    || die "sharedrop path must be a real directory owned by the current user: $SHARE_DIR"
chmod 700 -- "$SHARE_DIR" || die "could not restrict sharedrop directory permissions: $SHARE_DIR"
[[ -r "$SHARE_DIR" && -w "$SHARE_DIR" && -x "$SHARE_DIR" ]] \
    || die "sharedrop directory must be readable and writable by the current user: $SHARE_DIR"
printf 'Sharedrop: host files in %s are shared read/write with Joplin\n' "$SHARE_DIR"

resolv_conf="$(readlink -f /etc/resolv.conf)" || die "could not resolve /etc/resolv.conf"
[[ -r "$resolv_conf" ]] || die "DNS resolver configuration is not readable: $resolv_conf"
for system_file in /etc/hosts /etc/nsswitch.conf /etc/passwd /etc/group /etc/localtime /etc/timezone; do
    [[ -r "$system_file" ]] || die "required system file is not readable: $system_file"
done
[[ -d /etc/ssl/certs && -d /etc/fonts ]] || die "required TLS or font configuration is missing"

declare -a locale_env=()
if [[ -n "${LANGUAGE:-}" ]]; then
    locale_env+=(--setenv LANGUAGE "$LANGUAGE")
fi
for variable in "${!LC_@}"; do
    [[ "$variable" =~ ^LC_[A-Z_]+$ ]] || continue
    locale_env+=(--setenv "$variable" "${!variable}")
done

gtk_theme="${GTK_THEME:-}"
if command -v gsettings >/dev/null 2>&1; then
    if theme_value="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)" \
        && color_value="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"; then
        theme_regex="^'([[:alnum:]_. -]+)'$"
        if [[ "$theme_value" =~ $theme_regex ]]; then
            gtk_theme="${BASH_REMATCH[1]}"
            case "$color_value" in
                "'prefer-dark'")
                    [[ "$gtk_theme" == *:dark ]] || gtk_theme="${gtk_theme}:dark"
                    ;;
                "'prefer-light'")
                    gtk_theme="${gtk_theme%-dark}"
                    ;;
                "'default'") ;;
                *) die "unexpected desktop color-scheme setting: $color_value" ;;
            esac
        else
            die "unexpected desktop GTK theme setting: $theme_value"
        fi
    fi
fi

readonly SANDBOX_HOME="/home/joplin"
readonly SANDBOX_CONFIG="${SANDBOX_HOME}/.config"
readonly SANDBOX_DATA="${SANDBOX_CONFIG}/joplin-desktop"
readonly SANDBOX_SHARE="${SANDBOX_HOME}/Sharedrop"
readonly SANDBOX_RUNTIME="/run/joplin"
declare -a sandbox_env=(
    --clearenv
    --setenv HOME "$SANDBOX_HOME"
    --setenv PATH /usr/bin:/bin
    --setenv LANG "${LANG:-C.UTF-8}"
    --setenv XDG_CONFIG_HOME "$SANDBOX_CONFIG"
    --setenv XDG_CACHE_HOME "${SANDBOX_HOME}/.cache"
    --setenv XDG_STATE_HOME "${SANDBOX_HOME}/.local/state"
    --setenv TMPDIR /tmp
    --setenv APPIMAGE_EXTRACT_AND_RUN 1
)
if [[ -n "$gtk_theme" ]]; then
    sandbox_env+=(--setenv GTK_THEME "$gtk_theme")
    printf 'GTK theme: %s\n' "$gtk_theme"
fi
sandbox_env+=("${locale_env[@]}")
printf 'Locale: host LANG, LC_* and LANGUAGE values\n'
declare -a sandbox_args=(
    --unshare-pid
    --unshare-ipc
    --unshare-uts
    --unshare-cgroup-try
    --new-session
    --cap-drop ALL
    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --dir /usr
    --ro-bind /usr /usr
    --symlink usr/bin /bin
    --symlink usr/lib /lib
    --symlink usr/lib64 /lib64
    --dir /etc
    --dir /etc/ssl
    --dir /etc/fonts
    --ro-bind /etc/hosts /etc/hosts
    --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf
    --ro-bind /etc/passwd /etc/passwd
    --ro-bind /etc/group /etc/group
    --ro-bind /etc/localtime /etc/localtime
    --ro-bind /etc/timezone /etc/timezone
    --ro-bind /etc/ssl/certs /etc/ssl/certs
    --ro-bind /etc/fonts /etc/fonts
    --ro-bind "$resolv_conf" /etc/resolv.conf
    --dir /opt
    --ro-bind "$appimage" /opt/Joplin.AppImage
    --dir /home
    --tmpfs "$SANDBOX_HOME"
    --dir "$SANDBOX_SHARE"
    --bind "$SHARE_DIR" "$SANDBOX_SHARE"
    --dir "$SANDBOX_CONFIG"
    --bind "$JOPLIN_DATA_DIR" "$SANDBOX_DATA"
    --dir /run
    --dir "$SANDBOX_RUNTIME"
)

# Wayland only: expose exactly one Wayland socket; X11 is never exposed.
[[ -n "${WAYLAND_DISPLAY:-}" ]] || die "WAYLAND_DISPLAY is not set; a Wayland session is required"
if [[ "$WAYLAND_DISPLAY" == /* ]]; then
    wayland_socket="$WAYLAND_DISPLAY"
else
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] || die "XDG_RUNTIME_DIR is required for a relative WAYLAND_DISPLAY"
    [[ "$WAYLAND_DISPLAY" != */* ]] || die "WAYLAND_DISPLAY must be a socket name or absolute path"
    wayland_socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
fi
[[ -S "$wayland_socket" ]] || die "Wayland socket not found: $wayland_socket"
sandbox_args+=(--bind "$wayland_socket" "${SANDBOX_RUNTIME}/wayland-0")
declare -a gui_env=(
    --setenv WAYLAND_DISPLAY wayland-0
    --setenv XDG_RUNTIME_DIR "$SANDBOX_RUNTIME"
    --setenv GDK_BACKEND wayland
)
declare -a gui_args=(--ozone-platform=wayland)
printf 'GUI access: Wayland (%s)\n' "$wayland_socket"

# The host-side log is not exposed inside the sandbox.
state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
[[ "$state_home" == /* ]] || die "XDG_STATE_HOME must be an absolute path: $state_home"
readonly LOG_FILE="${state_home}/joplin_run.log"
mkdir -p -- "$state_home"
[[ -d "$state_home" && -w "$state_home" ]] || die "log directory is not writable: $state_home"

# Exercise the exact mounts and namespace setup before launching the AppImage.
[[ -x /usr/bin/true ]] || die "required sandbox preflight executable is missing: /usr/bin/true"
if ! preflight_out="$(bwrap "${sandbox_args[@]}" "${sandbox_env[@]}" "${gui_env[@]}" -- /usr/bin/true 2>&1)"; then
    die "Bubblewrap preflight failed; check user-namespace support and mounts: $preflight_out"
fi

# 7. Launch detached. Extract-and-run avoids requiring FUSE inside the sandbox.
# The shared network namespace permits general network access, not only Joplin Cloud.
readonly RUN_UID="$(id -u)"
printf 'Starting %s in Bubblewrap (detached, output in %s)\n' "$appimage" "$LOG_FILE"
setsid -f bwrap \
    "${sandbox_args[@]}" \
    "${sandbox_env[@]}" \
    "${gui_env[@]}" \
    -- /opt/Joplin.AppImage "${gui_args[@]}" \
    </dev/null >>"$LOG_FILE" 2>&1 || die "failed to start Bubblewrap for $appimage"

sleep 2
rc=0
running="$(pgrep -u "$RUN_UID" -af "$PROCESS_REGEX" 2>&1)" || rc=$?
if ((rc == 1)); then
    die "Joplin exited right after start; see $LOG_FILE"
elif ((rc != 0)); then
    die "pgrep failed after start (exit code $rc): $running"
fi
printf 'Joplin started in Bubblewrap\n'

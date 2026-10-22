#!/usr/bin/env bash
# Run the verified, up-to-date Joplin AppImage in a Bubblewrap sandbox.
# Target: Ubuntu 24.04+ with a Wayland session. See AGENTS.md (kept in sync).
# Sandbox policy: read-only /usr and a private copy of the AppImage; synthetic
# minimal /etc identity files; ephemeral size-capped home and /tmp; persistent
# read/write access only to Joplin's data directory and the Sharedrop folder;
# one Wayland socket (no X11, GPU, audio, D-Bus); memory-capped systemd scope;
# shared host networking, not restricted to Joplin Cloud.

set -Eeuo pipefail
shopt -s nullglob
IFS=$'\n\t'
umask 077
PATH=/usr/bin:/bin
export PATH
unset BASH_ENV ENV LD_PRELOAD LD_LIBRARY_PATH

die() {
    # Strip control characters (e.g. terminal escapes) from anything we print.
    local LC_ALL=C msg="$*"
    msg="${msg//[^[:print:][:space:]]/?}"
    printf 'ERROR: %s\n' "$msg" >&2
    exit 1
}
trap 'die "command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

work_dir=""
cleanup() {
    if [[ -n "$work_dir" ]]; then
        rm -rf -- "$work_dir" || true
    fi
}
trap cleanup EXIT

((EUID != 0)) || die "refusing to run as root"
[[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || die "HOME is not set to an existing absolute directory"

readonly JOPLIN_DIR="${HOME}/Desktop/Software/Joplin"
readonly JOPLIN_DATA_DIR="${HOME}/.config/joplin-desktop"
readonly SHARE_DIR="/tmp/joplin_sharedrop"
readonly RELEASES_URL="https://github.com/laurent22/joplin/releases/latest"
readonly DOWNLOAD_URL="https://github.com/laurent22/joplin/releases/download"
readonly TAG_REGEX='https://github\.com/laurent22/joplin/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)'
readonly FILE_REGEX='^Joplin-([0-9]+\.[0-9]+\.[0-9]+)\.AppImage$'
readonly PROCESS_REGEX='Joplin-[0-9]+\.[0-9]+\.[0-9]+\.AppImage|/opt/Joplin\.AppImage|/\.mount_[Jj]oplin'
readonly SAFE_ENV_REGEX='^[A-Za-z0-9_.@-]+$'
readonly TMP_SIZE=$((2 * 1024 * 1024 * 1024))
readonly HOME_SIZE=$((512 * 1024 * 1024))
readonly MEMORY_MAX="4G"
readonly LOG_MAX_BYTES=$((1024 * 1024))

for cmd in wget sha512sum sort tail head basename pgrep setsid id mkdir mktemp cp chmod stat rm sleep \
    flock readlink timeout gsettings systemd-run bwrap; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done
[[ -d "$JOPLIN_DIR" ]] || die "directory not found: $JOPLIN_DIR"

# Target: Ubuntu 24.04+ (merged /usr: /bin, /lib and /lib64 are symlinks into /usr).
[[ -r /etc/os-release ]] || die "/etc/os-release is not readable"
os_id=""
os_version=""
while IFS='=' read -r key value; do
    value="${value//\"/}"
    case "$key" in
        ID) os_id="$value" ;;
        VERSION_ID) os_version="$value" ;;
    esac
done </etc/os-release
[[ "$os_id" == ubuntu ]] || die "this script targets Ubuntu (found: ${os_id:-unknown})"
[[ "$os_version" =~ ^[0-9]+\.[0-9]+$ ]] || die "unexpected Ubuntu VERSION_ID: $os_version"
((10#${os_version%%.*} >= 24)) || die "Ubuntu 24.04 or newer is required (found: $os_version)"
for link in /bin /lib /lib64; do
    [[ -L "$link" ]] || die "merged-/usr layout expected, but $link is not a symlink"
done
[[ -d /usr && -d /etc/ssl/certs && -d /etc/fonts && -r /etc/localtime ]] \
    || die "required system files are missing: /usr, /etc/ssl/certs, /etc/fonts or /etc/localtime"
# systemd-resolved stub resolver (Ubuntu default); the sandbox gets a synthetic resolv.conf for it.
[[ "$(readlink -f /etc/resolv.conf)" == /run/systemd/resolve/stub-resolv.conf ]] \
    || die "/etc/resolv.conf must point to the systemd-resolved stub (Ubuntu default)"

# A Wayland session and a private runtime directory are required.
[[ -n "${XDG_RUNTIME_DIR:-}" && "$XDG_RUNTIME_DIR" == /* && -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]] \
    || die "XDG_RUNTIME_DIR must be an absolute directory owned by the current user"
[[ -n "${WAYLAND_DISPLAY:-}" ]] || die "WAYLAND_DISPLAY is not set; a Wayland session is required"
if [[ "$WAYLAND_DISPLAY" == /* ]]; then
    wayland_socket="$WAYLAND_DISPLAY"
else
    [[ "$WAYLAND_DISPLAY" != */* ]] || die "WAYLAND_DISPLAY must be a socket name or absolute path"
    wayland_socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
fi
[[ -S "$wayland_socket" && -O "$wayland_socket" ]] \
    || die "Wayland socket not found or not owned by the current user: $wayland_socket"

# Only one instance of this script at a time; the lock is not inherited by Joplin.
exec {lock_fd}>"${XDG_RUNTIME_DIR}/joplin_run.lock"
flock -n "$lock_fd" || die "another joplin_run.sh instance is already running"

wget_opts=(--no-config --https-only --max-redirect=5 --timeout=30 --tries=2 -qO-)

# 1. Latest local AppImage, by version in file name.
declare -a versions=()
for f in "$JOPLIN_DIR"/Joplin-*.AppImage; do
    name="$(basename "$f")"
    if [[ "$name" =~ $FILE_REGEX ]]; then
        versions+=("${BASH_REMATCH[1]}")
    fi
done
((${#versions[@]} > 0)) || die "no Joplin-X.Y.Z.AppImage found in $JOPLIN_DIR"

local_version="$(printf '%s\n' "${versions[@]}" | LC_ALL=C sort -V | tail -n 1)"
[[ -n "$local_version" ]] || die "could not determine latest local version"
appimage="${JOPLIN_DIR}/Joplin-${local_version}.AppImage"
sha_file="${appimage}.sha512"

# Refuse files that others could have tampered with.
for f in "$appimage" "$sha_file"; do
    [[ -f "$f" && ! -L "$f" && -O "$f" ]] \
        || die "must exist as a regular file owned by the current user (no symlink): $f"
    mode="$(stat -c '%a' -- "$f")" || die "could not stat $f"
    (((8#$mode & 8#022) == 0)) || die "file must not be group/world writable ($mode): $f"
done
[[ -x "$appimage" ]] || die "AppImage is not executable: $appimage"
printf 'Latest local AppImage: %s (version %s)\n' "$appimage" "$local_version"

# 2. Verify the local checksum file: exactly one entry, naming this AppImage.
checksum_line="$(<"$sha_file")"
[[ "$checksum_line" != *$'\n'* ]] || die "checksum file must contain exactly one entry: $sha_file"
[[ "$checksum_line" =~ ^([[:xdigit:]]{128})[[:space:]]+\*?(.+)$ ]] \
    || die "checksum file has an invalid SHA-512 entry: $sha_file"
expected_hash="${BASH_REMATCH[1],,}"
[[ "${BASH_REMATCH[2]}" == "$(basename "$appimage")" ]] \
    || die "checksum file does not name $(basename "$appimage"): $sha_file"
if ! sha_out="$(cd "$JOPLIN_DIR" && sha512sum --strict -c -- "$(basename "$sha_file")" 2>&1)"; then
    die "sha512 verification FAILED for $appimage: $sha_out"
fi
printf 'sha512 check OK: %s\n' "$sha_out"

# 3. Fetch the latest GitHub release version.
page="$(wget "${wget_opts[@]}" "$RELEASES_URL")" || die "wget failed for $RELEASES_URL"
[[ -n "$page" ]] || die "empty response from $RELEASES_URL"
[[ "$page" =~ $TAG_REGEX ]] || die "no release tag URL found in response from $RELEASES_URL"
latest_version="${BASH_REMATCH[1]}"
printf 'Latest GitHub release: %s\n' "$latest_version"

# 4. Require an up-to-date local AppImage.
[[ "$local_version" == "$latest_version" ]] \
    || die "local version ($local_version) differs from latest release ($latest_version); please update"
printf 'Confirmed: local AppImage is up to date (%s)\n' "$latest_version"

# 4b. Authenticity: the checksum published in the GitHub release must match the local one.
# This also confirms the release tag really exists.
remote_sha="$(wget "${wget_opts[@]}" "${DOWNLOAD_URL}/v${latest_version}/Joplin-${latest_version}.AppImage.sha512")" \
    || die "could not download the release checksum for v${latest_version}"
[[ "$remote_sha" =~ ^[[:space:]]*([[:xdigit:]]{128})([[:space:]].*)?$ ]] \
    || die "release checksum has an unexpected format"
[[ "${BASH_REMATCH[1],,}" == "$expected_hash" ]] \
    || die "local checksum does not match the checksum published in the GitHub release"
printf 'Confirmed: checksum matches the GitHub release\n'

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

# 6. Prepare private working files, data directories and the log.
work_dir="$(mktemp -d -- "${XDG_RUNTIME_DIR}/joplin_run.XXXXXX")"
[[ -d "$work_dir" && -O "$work_dir" ]] || die "could not create private work directory"

# Run a private copy so the verified bytes cannot change between check and launch.
appimage_copy="${work_dir}/Joplin.AppImage"
cp --no-preserve=all -- "$appimage" "$appimage_copy" || die "could not copy the AppImage to $work_dir"
chmod 500 -- "$appimage_copy"
copy_hash="$(sha512sum -- "$appimage_copy")" || die "could not hash the AppImage copy"
[[ "${copy_hash%% *}" == "$expected_hash" ]] || die "AppImage copy does not match the verified checksum"

mkdir -p -- "$JOPLIN_DATA_DIR"
[[ -d "$JOPLIN_DATA_DIR" && -O "$JOPLIN_DATA_DIR" && ! -L "$JOPLIN_DATA_DIR" \
    && -r "$JOPLIN_DATA_DIR" && -w "$JOPLIN_DATA_DIR" ]] \
    || die "Joplin data directory must be a real, readable, writable directory owned by you: $JOPLIN_DATA_DIR"

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
printf 'Sharedrop: %s is shared read/write with Joplin\n' "$SHARE_DIR"

# The host-side log is not exposed inside the sandbox; rotate it when it grows.
state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
[[ "$state_home" == /* ]] || die "XDG_STATE_HOME must be an absolute path: $state_home"
readonly LOG_FILE="${state_home}/joplin_run.log"
mkdir -p -- "$state_home"
[[ -d "$state_home" && -w "$state_home" ]] || die "log directory is not writable: $state_home"
if [[ -e "$LOG_FILE" || -L "$LOG_FILE" ]]; then
    [[ -f "$LOG_FILE" && ! -L "$LOG_FILE" && -O "$LOG_FILE" ]] \
        || die "log file must be a regular file owned by the current user (no symlink): $LOG_FILE"
    log_size="$(stat -c '%s' -- "$LOG_FILE")"
    if ((log_size > LOG_MAX_BYTES)); then
        mv -f -- "$LOG_FILE" "${LOG_FILE}.1"
    fi
fi

# Synthetic identity and name-service files: the sandbox never sees the host
# user name, host name, domain search list or nsswitch modules.
run_uid="$(id -u)"
run_gid="$(id -g)"
readonly SANDBOX_HOME="/home/joplin"
printf 'joplin:x:%s:%s:joplin:%s:/usr/sbin/nologin\n' "$run_uid" "$run_gid" "$SANDBOX_HOME" >"${work_dir}/passwd"
printf 'joplin:x:%s:\n' "$run_gid" >"${work_dir}/group"
printf '127.0.0.1 localhost\n::1 localhost\n' >"${work_dir}/hosts"
printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\n' >"${work_dir}/nsswitch.conf"
printf 'nameserver 127.0.0.53\noptions edns0 trust-ad\n' >"${work_dir}/resolv.conf"

declare -a locale_env=()
if [[ -n "${LANGUAGE:-}" ]]; then
    [[ "$LANGUAGE" =~ ^[A-Za-z0-9_.@:-]+$ ]] || die "unexpected LANGUAGE value"
    locale_env+=(--setenv LANGUAGE "$LANGUAGE")
fi
for variable in "${!LC_@}"; do
    [[ "$variable" =~ ^LC_[A-Z_]+$ ]] || continue
    [[ "${!variable}" =~ $SAFE_ENV_REGEX ]] || die "unexpected value for $variable"
    locale_env+=(--setenv "$variable" "${!variable}")
done
sandbox_lang="${LANG:-C.UTF-8}"
[[ "$sandbox_lang" =~ $SAFE_ENV_REGEX ]] || die "unexpected LANG value"

# GTK theme and light/dark preference from GNOME settings (read on the host only).
theme_value="$(timeout 5 gsettings get org.gnome.desktop.interface gtk-theme)" \
    || die "could not read the GNOME GTK theme setting"
color_value="$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme)" \
    || die "could not read the GNOME color-scheme setting"
theme_regex="^'([[:alnum:]_. -]+)'$"
[[ "$theme_value" =~ $theme_regex ]] || die "unexpected desktop GTK theme setting: $theme_value"
gtk_base="${BASH_REMATCH[1]%-dark}"
case "$color_value" in
    "'prefer-dark'") gtk_theme="${gtk_base}:dark" ;;
    "'prefer-light'") gtk_theme="$gtk_base" ;;
    "'default'") gtk_theme="${BASH_REMATCH[1]}" ;;
    *) die "unexpected desktop color-scheme setting: $color_value" ;;
esac
printf 'GTK theme: %s\n' "$gtk_theme"
printf 'Locale: host LANG, LC_* and LANGUAGE values\n'

readonly SANDBOX_CONFIG="${SANDBOX_HOME}/.config"
readonly SANDBOX_DATA="${SANDBOX_CONFIG}/joplin-desktop"
readonly SANDBOX_SHARE="${SANDBOX_HOME}/Sharedrop"
readonly SANDBOX_RUNTIME="/run/joplin"
declare -a sandbox_env=(
    --clearenv
    --setenv HOME "$SANDBOX_HOME"
    --setenv PATH /usr/bin:/bin
    --setenv LANG "$sandbox_lang"
    --setenv XDG_CONFIG_HOME "$SANDBOX_CONFIG"
    --setenv XDG_CACHE_HOME "${SANDBOX_HOME}/.cache"
    --setenv XDG_STATE_HOME "${SANDBOX_HOME}/.local/state"
    --setenv XDG_RUNTIME_DIR "$SANDBOX_RUNTIME"
    --setenv WAYLAND_DISPLAY wayland-0
    --setenv GDK_BACKEND wayland
    --setenv GTK_THEME "$gtk_theme"
    --setenv TMPDIR /tmp
    --setenv APPIMAGE_EXTRACT_AND_RUN 1
)
sandbox_env+=("${locale_env[@]}")

declare -a sandbox_args=(
    --unshare-user
    --unshare-pid
    --unshare-ipc
    --unshare-uts
    --unshare-cgroup-try
    --hostname joplin
    --new-session
    --cap-drop ALL
    --proc /proc
    --dev /dev
    --size "$TMP_SIZE" --tmpfs /tmp
    --ro-bind /usr /usr
    --symlink usr/bin /bin
    --symlink usr/lib /lib
    --symlink usr/lib64 /lib64
    --dir /etc
    --dir /etc/ssl
    --ro-bind /etc/ssl/certs /etc/ssl/certs
    --ro-bind /etc/fonts /etc/fonts
    --ro-bind /etc/localtime /etc/localtime
    --ro-bind "${work_dir}/passwd" /etc/passwd
    --ro-bind "${work_dir}/group" /etc/group
    --ro-bind "${work_dir}/hosts" /etc/hosts
    --ro-bind "${work_dir}/nsswitch.conf" /etc/nsswitch.conf
    --ro-bind "${work_dir}/resolv.conf" /etc/resolv.conf
    --dir /opt
    --ro-bind "$appimage_copy" /opt/Joplin.AppImage
    --dir /home
    --size "$HOME_SIZE" --perms 0700 --tmpfs "$SANDBOX_HOME"
    --dir "$SANDBOX_SHARE"
    --bind "$SHARE_DIR" "$SANDBOX_SHARE"
    --dir "$SANDBOX_CONFIG"
    --bind "$JOPLIN_DATA_DIR" "$SANDBOX_DATA"
    --dir /run
    --perms 0700 --dir "$SANDBOX_RUNTIME"
    --bind "$wayland_socket" "${SANDBOX_RUNTIME}/wayland-0"
)
# GPU is not exposed, so disable it rather than letting Chromium probe for one.
declare -a app_args=(--ozone-platform=wayland --disable-gpu)
declare -a scope_cmd=(systemd-run --user --scope --quiet -p "MemoryMax=${MEMORY_MAX}" -p MemorySwapMax=0 --)
printf 'GUI access: Wayland (%s)\n' "$wayland_socket"

# Exercise the exact mounts, namespaces and memory scope before launching the AppImage.
if ! preflight_out="$("${scope_cmd[@]}" /usr/bin/true 2>&1)"; then
    die "systemd user scope with a memory limit is not available: $preflight_out"
fi
# shellcheck disable=SC2016 # $1..$4 expand inside the sandbox shell
if ! preflight_out="$(bwrap "${sandbox_args[@]}" "${sandbox_env[@]}" -- /usr/bin/sh -c \
    'test -w "$1" && test -w "$2" && test -w "$3" && test -w /tmp && test -S "$4"' \
    sh "$SANDBOX_DATA" "$SANDBOX_SHARE" "$SANDBOX_HOME" "${SANDBOX_RUNTIME}/wayland-0" 2>&1)"; then
    die "Bubblewrap preflight failed; check user-namespace support (Ubuntu AppArmor) and mounts: $preflight_out"
fi

# 7. Launch detached. Extract-and-run avoids requiring FUSE inside the sandbox.
# The shared network namespace permits general network access, not only Joplin Cloud.
status_file="${work_dir}/status.json"
printf 'Starting %s in Bubblewrap (detached, output in %s)\n' "$appimage" "$LOG_FILE"
setsid -f "${scope_cmd[@]}" bwrap \
    "${sandbox_args[@]}" \
    --json-status-fd 3 \
    "${sandbox_env[@]}" \
    -- /opt/Joplin.AppImage "${app_args[@]}" \
    3>"$status_file" {lock_fd}>&- </dev/null >>"$LOG_FILE" 2>&1 \
    || die "failed to start Bubblewrap for $appimage"

# Bubblewrap reports the sandbox child PID, and its exit code if it ends.
status=""
for _ in 1 2 3 4 5 6; do
    sleep 0.5
    status="$(<"$status_file")"
    [[ "$status" != *'"exit-code"'* ]] || die "Joplin exited right after start; see $LOG_FILE"
done
pid_regex='"child-pid":[[:space:]]*([0-9]+)'
[[ "$status" =~ $pid_regex ]] || die "Bubblewrap did not report a child PID; see $LOG_FILE"
child_pid="${BASH_REMATCH[1]}"
kill -0 "$child_pid" 2>/dev/null || die "Joplin is not running after start; see $LOG_FILE"
printf 'Joplin started in Bubblewrap (sandbox PID %s)\n' "$child_pid"

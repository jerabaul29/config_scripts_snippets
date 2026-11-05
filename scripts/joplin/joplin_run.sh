#!/usr/bin/env bash
# Run the verified, up-to-date Joplin AppImage in a Bubblewrap sandbox.
# Target: Ubuntu 24.04+ with a Wayland session. See AGENTS.md (kept in sync).
# Sandbox policy: read-only /usr and a private copy of the AppImage; synthetic
# minimal /etc identity files; ephemeral size-capped home and /tmp; persistent
# read/write access only to Joplin's data directory and the Sharedrop folder;
# one Wayland socket (no X11, GPU, audio, D-Bus); memory-capped systemd scope;
# shared host networking, not restricted to Joplin Cloud.
#
# After any edit, run (all must pass with no output):
#   bash -n joplin_run.sh                    # syntax check
#   lint: run "shellcheck joplin_run.sh"     # apt install shellcheck
#   shfmt -i 4 -ci -bn -d joplin_run.sh      # format check; use -w to rewrite in place

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
    msg="${msg//[^[:print:]$'\n']/?}"
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

readonly JOPLIN_DIR="${HOME:-}/Desktop/Software/Joplin"
readonly JOPLIN_DATA_DIR="${HOME:-}/.config/joplin-desktop"
readonly SHARE_DIR="/tmp/joplin_sharedrop"
readonly RELEASES_URL="https://github.com/laurent22/joplin/releases/latest"
readonly DOWNLOAD_URL="https://github.com/laurent22/joplin/releases/download"
readonly TAG_REGEX='https://github\.com/laurent22/joplin/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)'
readonly FILE_REGEX='^Joplin-([0-9]+\.[0-9]+\.[0-9]+)\.AppImage$'
readonly SHA_REGEX='^([[:xdigit:]]{128})([[:space:]]+\*?(.+))?$'
readonly PROCESS_REGEX='Joplin-[0-9]+\.[0-9]+\.[0-9]+\.AppImage|/opt/Joplin\.AppImage|/\.mount_Joplin'
readonly SAFE_ENV_REGEX='^[A-Za-z0-9_.@-]+$'
readonly TMP_SIZE=$((2 * 1024 * 1024 * 1024))
readonly HOME_SIZE=$((512 * 1024 * 1024))
readonly MEMORY_MAX="4G"
readonly TASKS_MAX=2048
readonly LOG_MAX_BYTES=$((1024 * 1024))
readonly SANDBOX_HOME="/home/joplin"
readonly SANDBOX_CONFIG="${SANDBOX_HOME}/.config"
readonly SANDBOX_DATA="${SANDBOX_CONFIG}/joplin-desktop"
readonly SANDBOX_SHARE="${SANDBOX_HOME}/Sharedrop"
readonly SANDBOX_RUNTIME="/run/joplin"
readonly WGET_OPTS=(--no-config --https-only --max-redirect=5 --timeout=30 --tries=2 -nv -O-)
readonly REQUIRED_COMMANDS=(wget sha512sum sort tail pgrep setsid id mkdir mktemp cp chmod stat rm mv sleep
    flock readlink timeout gsettings systemd-run bwrap systemctl head)

# Set by the steps below.
local_version="" appimage="" sha_file="" expected_hash="" latest_version=""
wayland_socket="" lock_fd="" appimage_copy="" LOG_FILE="" gtk_theme="" sandbox_lang=""
locale_env=() sandbox_env=() sandbox_args=() scope_cmd=()

# --- helpers ---------------------------------------------------------------

require_real_dir() {
    [[ -d "$1" && -O "$1" && ! -L "$1" ]] \
        || die "must be a real directory (no symlink) owned by the current user: $1"
}

require_own_file() {
    [[ -f "$1" && ! -L "$1" && -O "$1" ]] \
        || die "must exist as a regular file owned by the current user (no symlink): $1"
}

require_not_shared_writable() {
    local mode
    mode="$(stat -c '%a' -- "$1")" || die "could not stat $1"
    (((8#$mode & 8#022) == 0)) || die "file must not be group/world writable ($mode): $1"
}

fetch() {
    local err_file out rc=0
    err_file="$(mktemp -- "${XDG_RUNTIME_DIR}/joplin_wget.XXXXXX")"
    out="$(wget "${WGET_OPTS[@]}" "$1" 2>"$err_file")" || rc=$?
    if ((rc != 0)); then
        local err
        err="$(head -c 500 -- "$err_file")"
        rm -f -- "$err_file"
        die "wget failed (exit code $rc) for $1: $err"
    fi
    rm -f -- "$err_file"
    printf '%s' "$out"
}

# Print the single SHA-512 entry of a checksum text as "hash name"; name may be empty.
# $1 = text, $2 = description for errors.
parse_single_checksum() {
    [[ "$1" != *$'\n'* ]] || die "$2 must contain exactly one entry"
    [[ "$1" =~ $SHA_REGEX ]] || die "$2 has an invalid SHA-512 entry"
    printf '%s %s' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[3]:-}"
}

# --- steps -----------------------------------------------------------------

check_platform() {
    ((EUID != 0)) || die "refusing to run as root"
    [[ "${HOME:-}" == /* && -d "$HOME" ]] || die "HOME is not set to an existing absolute directory"

    local cmd
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
    done
    [[ -d "$JOPLIN_DIR" ]] || die "directory not found: $JOPLIN_DIR"

    # Ubuntu 24.04+ with a merged /usr (/bin, /lib and /lib64 are symlinks into /usr).
    [[ -r /etc/os-release ]] || die "/etc/os-release is not readable"
    local key value os_id="" os_version=""
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

    local link
    for link in /bin /lib /lib64; do
        [[ -L "$link" ]] || die "merged-/usr layout expected, but $link is not a symlink"
        [[ "$(readlink -f "$link")" == "/usr${link}" ]] \
            || die "merged-/usr layout expected, but $link does not resolve to /usr${link}"
    done
    [[ -d /etc/ssl/certs && -d /etc/fonts && -r /etc/localtime ]] \
        || die "required system files are missing: /etc/ssl/certs, /etc/fonts or /etc/localtime"
    # systemd-resolved stub resolver (Ubuntu default); the sandbox gets a synthetic resolv.conf for it.
    [[ "$(readlink -f /etc/resolv.conf)" == /run/systemd/resolve/stub-resolv.conf ]] \
        || die "/etc/resolv.conf must point to the systemd-resolved stub (Ubuntu default)"
    systemctl is-active --quiet systemd-resolved || die "systemd-resolved is not active"
}

# A Wayland session and a private runtime directory are required; take the single-instance lock.
check_session() {
    [[ "${XDG_RUNTIME_DIR:-}" == /* && -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]] \
        || die "XDG_RUNTIME_DIR must be an absolute directory owned by the current user"
    [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || die "a Wayland session is required (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset})"
    [[ "${WAYLAND_DISPLAY:-}" =~ ^[A-Za-z0-9_-]+$ ]] \
        || die "WAYLAND_DISPLAY must be a plain socket name like wayland-0 (a Wayland session is required)"
    wayland_socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    [[ -S "$wayland_socket" && -O "$wayland_socket" ]] \
        || die "Wayland socket not found or not owned by the current user: $wayland_socket"

    # The lock is not inherited by Joplin (see launch).
    exec {lock_fd}>"${XDG_RUNTIME_DIR}/joplin_run.lock"
    flock -n "$lock_fd" || die "another joplin_run.sh instance is already running"
}

# 1. Latest local AppImage, by version in the file name (not modification time).
find_latest_local() {
    local f name versions=()
    for f in "$JOPLIN_DIR"/Joplin-*.AppImage; do
        name="${f##*/}"
        if [[ "$name" =~ $FILE_REGEX ]]; then
            versions+=("${BASH_REMATCH[1]}")
        fi
    done
    ((${#versions[@]} > 0)) || die "no Joplin-X.Y.Z.AppImage found in $JOPLIN_DIR"

    local_version="$(printf '%s\n' "${versions[@]}" | LC_ALL=C sort -V | tail -n 1)"
    appimage="${JOPLIN_DIR}/Joplin-${local_version}.AppImage"
    sha_file="${appimage}.sha512"

    # Refuse files that others could have tampered with.
    for f in "$appimage" "$sha_file"; do
        require_own_file "$f"
        require_not_shared_writable "$f"
    done
    printf 'Latest local AppImage: %s (version %s)\n' "$appimage" "$local_version"
}

# 2. Verify the local checksum file: exactly one entry, naming this AppImage.
verify_local_checksum() {
    local entry name sha_out
    entry="$(parse_single_checksum "$(<"$sha_file")" "checksum file $sha_file")" || exit 1
    expected_hash="${entry%% *}"
    name="${entry#* }"
    [[ "$name" == "${appimage##*/}" ]] || die "checksum file does not name ${appimage##*/}: $sha_file"
    if ! sha_out="$(cd "$JOPLIN_DIR" && sha512sum --strict -c -- "${sha_file##*/}" 2>&1)"; then
        die "sha512 verification FAILED for $appimage: $sha_out"
    fi
    printf 'sha512 check OK: %s\n' "$sha_out"
}

# 3-4. Latest GitHub release must equal the local version and publish the same checksum.
check_release() {
    local page remote_sha entry
    page="$(fetch "$RELEASES_URL")" || die "wget failed for $RELEASES_URL"
    [[ "$page" =~ $TAG_REGEX ]] || die "no release tag URL found in response from $RELEASES_URL"
    latest_version="${BASH_REMATCH[1]}"
    printf 'Latest GitHub release: %s\n' "$latest_version"

    [[ "$local_version" == "$latest_version" ]] \
        || die "local version ($local_version) differs from latest release ($latest_version); please update"
    printf 'Confirmed: local AppImage is up to date (%s)\n' "$latest_version"

    # Authenticity: the published checksum must match the local one (this also
    # confirms the release tag exists); the local checksum alone proves only integrity.
    remote_sha="$(fetch "${DOWNLOAD_URL}/v${latest_version}/Joplin-${latest_version}.AppImage.sha512")" \
        || die "could not download the release checksum for v${latest_version}"
    entry="$(parse_single_checksum "$remote_sha" "release checksum")" || exit 1
    [[ -z "${entry#* }" || "${entry#* }" == "${appimage##*/}" ]] \
        || die "release checksum names a different file: ${entry#* }"
    [[ "${entry%% *}" == "$expected_hash" ]] \
        || die "local checksum does not match the checksum published in the GitHub release"
    printf 'Confirmed: checksum matches the GitHub release\n'
}

# 5. pgrep exit code 1 means "not running"; any other non-zero code is an error.
check_not_running() {
    local rc=0 running
    running="$(pgrep -u "$(id -u)" -af "$PROCESS_REGEX" 2>&1)" || rc=$?
    if ((rc == 0)); then
        die "Joplin appears to be already running:
${running}"
    elif ((rc != 1)); then
        die "pgrep failed (exit code $rc): $running"
    fi
    printf 'Confirmed: Joplin is not already running\n'
}

# 6a. Private work dir with a re-verified copy of the AppImage, so the verified
# bytes cannot change between check and launch.
prepare_work_dir() {
    local copy_hash
    work_dir="$(mktemp -d -- "${XDG_RUNTIME_DIR}/joplin_run.XXXXXX")"
    require_real_dir "$work_dir"

    appimage_copy="${work_dir}/Joplin.AppImage"
    cp --no-preserve=all -- "$appimage" "$appimage_copy" || die "could not copy the AppImage to $work_dir"
    chmod 500 -- "$appimage_copy"
    copy_hash="$(sha512sum -- "$appimage_copy")" || die "could not hash the AppImage copy"
    [[ "${copy_hash%% *}" == "$expected_hash" ]] || die "AppImage copy does not match the verified checksum"
}

# 6b. Writable host directories: Joplin's data and the Sharedrop exchange folder.
prepare_dirs() {
    mkdir -p -- "$JOPLIN_DATA_DIR"
    require_real_dir "$JOPLIN_DATA_DIR"
    [[ -r "$JOPLIN_DATA_DIR" && -w "$JOPLIN_DATA_DIR" ]] \
        || die "Joplin data directory must be readable and writable: $JOPLIN_DATA_DIR"

    [[ ! -L "$SHARE_DIR" ]] || die "sharedrop path must not be a symbolic link: $SHARE_DIR"
    if [[ ! -e "$SHARE_DIR" ]]; then
        mkdir -m 700 -- "$SHARE_DIR" || die "could not create sharedrop directory: $SHARE_DIR"
    fi
    require_real_dir "$SHARE_DIR"
    chmod 700 -- "$SHARE_DIR" || die "could not restrict sharedrop directory permissions: $SHARE_DIR"
    printf 'Sharedrop: %s is shared read/write with Joplin\n' "$SHARE_DIR"
}

# 6c. The host-side log is not exposed inside the sandbox; rotate it when it grows.
prepare_log() {
    local state_home="${HOME}/.local/state"
    LOG_FILE="${state_home}/joplin_run.log"
    mkdir -p -- "$state_home"
    require_real_dir "$state_home"
    if [[ -e "$LOG_FILE" || -L "$LOG_FILE" ]]; then
        require_own_file "$LOG_FILE"
        if (($(stat -c '%s' -- "$LOG_FILE") > LOG_MAX_BYTES)); then
            mv -f -- "$LOG_FILE" "${LOG_FILE}.1"
        fi
    fi
}

# Synthetic identity and name-service files: the sandbox never sees the host
# user name, host name, domain search list or nsswitch modules.
write_synthetic_etc() {
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    printf 'joplin:x:%s:%s:joplin:%s:/usr/sbin/nologin\n' "$uid" "$gid" "$SANDBOX_HOME" >"${work_dir}/passwd"
    printf 'joplin:x:%s:\n' "$gid" >"${work_dir}/group"
    printf '127.0.0.1 localhost\n::1 localhost\n' >"${work_dir}/hosts"
    printf 'passwd: files\ngroup: files\nhosts: files dns\n' >"${work_dir}/nsswitch.conf"
    printf 'nameserver 127.0.0.53\noptions edns0 trust-ad\n' >"${work_dir}/resolv.conf"
}

# Pass through LANG and LANGUAGE only when they have a safe character set.
collect_locale() {
    if [[ -n "${LANGUAGE:-}" ]]; then
        [[ "$LANGUAGE" =~ ^[A-Za-z0-9_.@:-]+$ ]] || die "unexpected LANGUAGE value"
        locale_env+=(--setenv LANGUAGE "$LANGUAGE")
    fi
    sandbox_lang="${LANG:-C.UTF-8}"
    [[ "$sandbox_lang" =~ $SAFE_ENV_REGEX ]] || die "unexpected LANG value"
}

# GTK theme and light/dark preference from GNOME settings (read on the host only).
collect_gtk_theme() {
    local theme_value color_value theme_regex="^'([[:alnum:]_. -]+)'$" gtk_base
    theme_value="$(timeout 5 gsettings get org.gnome.desktop.interface gtk-theme)" \
        || die "could not read the GNOME GTK theme setting"
    color_value="$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme)" \
        || die "could not read the GNOME color-scheme setting"
    [[ "$theme_value" =~ $theme_regex ]] || die "unexpected desktop GTK theme setting: $theme_value"
    gtk_base="${BASH_REMATCH[1]%-dark}"
    case "$color_value" in
        "'prefer-dark'") gtk_theme="${gtk_base}:dark" ;;
        "'prefer-light'") gtk_theme="$gtk_base" ;;
        "'default'") gtk_theme="${BASH_REMATCH[1]}" ;;
        *) die "unexpected desktop color-scheme setting: $color_value" ;;
    esac
    printf 'GTK theme: %s\n' "$gtk_theme"
}

build_sandbox() {
    write_synthetic_etc
    collect_locale
    collect_gtk_theme
    printf 'Locale: host LANG and LANGUAGE values\n'

    sandbox_env=(
        --clearenv
        --setenv HOME "$SANDBOX_HOME"
        --setenv PATH /usr/bin:/bin
        --setenv LANG "$sandbox_lang"
        --setenv XDG_RUNTIME_DIR "$SANDBOX_RUNTIME"
        --setenv WAYLAND_DISPLAY wayland-0
        --setenv GDK_BACKEND wayland
        --setenv GTK_THEME "$gtk_theme"
        --setenv APPIMAGE_EXTRACT_AND_RUN 1
        "${locale_env[@]}"
    )

    sandbox_args=(
        --unshare-user
        --unshare-pid
        --unshare-ipc
        --unshare-uts
        --unshare-cgroup
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
        --ro-bind /etc/ssl/certs /etc/ssl/certs
        --ro-bind /etc/fonts /etc/fonts
        --ro-bind /etc/localtime /etc/localtime
        --ro-bind "${work_dir}/passwd" /etc/passwd
        --ro-bind "${work_dir}/group" /etc/group
        --ro-bind "${work_dir}/hosts" /etc/hosts
        --ro-bind "${work_dir}/nsswitch.conf" /etc/nsswitch.conf
        --ro-bind "${work_dir}/resolv.conf" /etc/resolv.conf
        --ro-bind "$appimage_copy" /opt/Joplin.AppImage
        --size "$HOME_SIZE" --perms 0700 --tmpfs "$SANDBOX_HOME"
        --bind "$SHARE_DIR" "$SANDBOX_SHARE"
        --bind "$JOPLIN_DATA_DIR" "$SANDBOX_DATA"
        --perms 0700 --dir "$SANDBOX_RUNTIME"
        --bind "$wayland_socket" "${SANDBOX_RUNTIME}/wayland-0"
    )
    scope_cmd=(systemd-run --user --scope --quiet -p "MemoryMax=${MEMORY_MAX}" -p MemorySwapMax=0 -p "TasksMax=${TASKS_MAX}" --)
    printf 'GUI access: Wayland (%s)\n' "$wayland_socket"
}

# Exercise the exact mounts, namespaces and memory scope before launching the AppImage.
preflight() {
    local out
    if ! out="$("${scope_cmd[@]}" /usr/bin/true 2>&1)"; then
        die "systemd user scope with a memory limit is not available: $out"
    fi
    # shellcheck disable=SC2016 # $1..$4 expand inside the sandbox shell
    if ! out="$(bwrap "${sandbox_args[@]}" "${sandbox_env[@]}" -- /usr/bin/sh -c \
        'test -w "$1" && test -w "$2" && test -w "$3" && test -w /tmp && test -S "$4"' \
        sh "$SANDBOX_DATA" "$SANDBOX_SHARE" "$SANDBOX_HOME" "${SANDBOX_RUNTIME}/wayland-0" 2>&1)"; then
        die "Bubblewrap preflight failed; check user-namespace support (Ubuntu AppArmor) and mounts: $out"
    fi
}

# 7. Launch detached. Extract-and-run avoids requiring FUSE inside the sandbox.
# The shared network namespace permits general network access, not only Joplin Cloud.
launch() {
    # GPU is not exposed, so disable it rather than letting Chromium probe for one.
    local app_args=(--ozone-platform=wayland --disable-gpu)
    local status_file="${work_dir}/status.json" status="" child_pid pid_regex='"child-pid":[[:space:]]*([0-9]+)'

    printf 'Starting %s in Bubblewrap (detached, output in %s)\n' "$appimage" "$LOG_FILE"
    setsid -f "${scope_cmd[@]}" bwrap \
        "${sandbox_args[@]}" \
        --json-status-fd 3 \
        "${sandbox_env[@]}" \
        -- /opt/Joplin.AppImage "${app_args[@]}" \
        3>"$status_file" {lock_fd}>&- </dev/null >>"$LOG_FILE" 2>&1 \
        || die "failed to start Bubblewrap for $appimage"

    # Bubblewrap reports the sandbox child PID, and its exit code if it ends.
    local _
    for _ in 1 2 3 4 5 6; do
        sleep 0.5
        status="$(<"$status_file")"
        [[ "$status" != *'"exit-code"'* ]] || die "Joplin exited right after start; see $LOG_FILE"
    done
    [[ "$status" =~ $pid_regex ]] || die "Bubblewrap did not report a child PID; see $LOG_FILE"
    child_pid="${BASH_REMATCH[1]}"
    kill -0 "$child_pid" 2>/dev/null || die "Joplin is not running after start; see $LOG_FILE"
    printf 'Joplin started in Bubblewrap (sandbox PID %s)\n' "$child_pid"
}

main() {
    check_platform
    check_session
    find_latest_local
    verify_local_checksum
    check_release
    check_not_running
    prepare_work_dir
    prepare_dirs
    prepare_log
    build_sandbox
    preflight
    launch
}

main "$@"

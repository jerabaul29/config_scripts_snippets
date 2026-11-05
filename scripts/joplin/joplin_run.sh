#!/usr/bin/env bash
# Run the verified, up-to-date Joplin AppImage in a Bubblewrap sandbox.
# Target: Ubuntu 24.04+ and a Wayland session only. See AGENTS.md (kept in sync).
# Sandbox policy: read-only /usr and a private copy of the AppImage; synthetic
# minimal /etc identity files; ephemeral size-capped home and /tmp; persistent
# read/write access only to Joplin's data directory and the Sharedrop folder;
# one Wayland socket (no X11, GPU, audio, D-Bus); memory-capped systemd scope;
# shared host networking, not restricted to Joplin Cloud.
#
# Assumptions checked in code before launch (abort if any is false):
# - Not root. HOME and the Joplin directory are real, user-owned, not group/world writable.
# - Ubuntu 24.04 or newer only (ID=ubuntu, VERSION_ID >= 24.04). ID_LIKE is not accepted.
# - Wayland only: XDG_SESSION_TYPE=wayland, plain WAYLAND_DISPLAY, owned non-symlink socket.
# - Merged /usr. systemd-resolved is active and its stub nameserver is 127.0.0.53.
# - XDG_RUNTIME_DIR is a real user-owned directory and not group/world accessible.
# - bwrap is not setuid/setgid and supports every flag this script passes.
# - wget supports --https-only/--no-config/--no-proxy/--no-netrc (direct HTTPS; no ~/.wgetrc).
# - sha512sum supports --strict; sort -V is version sort; setsid supports -f; pgrep exits 1
#   when nothing matches.
# - Sandbox uid/gid are pinned to the invoking user (--uid/--gid), never left at bwrap's default.
# - user/pid/ipc/uts/cgroup namespaces are isolated; the network namespace is the host's.
# - Capabilities are dropped; /usr is read-only; no GPU, audio, X11, or D-Bus; synthetic /etc only.
# - --json-status-fd 3 survives setsid and systemd-run and names a live host pid in the sandbox.
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
status_probe_pid=""
cleanup() {
    if [[ -n "${status_probe_pid:-}" ]]; then
        kill -KILL "$status_probe_pid" 2>/dev/null || true
        status_probe_pid=""
    fi
    if [[ -n "${work_dir:-}" ]]; then
        rm -rf -- "$work_dir" || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
# Direct HTTPS only: no wgetrc, no proxy, no .netrc credentials.
readonly WGET_OPTS=(--no-config --https-only --no-proxy --no-netrc --max-redirect=5 --timeout=30 --tries=2 -nv -O-)
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
    # Direct HTTPS: wgetrc is disabled by WGET_OPTS, and proxy variables are removed
    # for this process so they cannot redirect the release check.
    local err_file out rc=0
    err_file="$(mktemp -- "${XDG_RUNTIME_DIR}/joplin_wget.XXXXXX")"
    out="$(/usr/bin/env \
        -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
        -u all_proxy -u ALL_PROXY -u ftp_proxy -u FTP_PROXY \
        -u no_proxy -u NO_PROXY \
        wget "${WGET_OPTS[@]}" "$1" 2>"$err_file")" || rc=$?
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

# Flags and tool behaviour this script relies on. Help text and a few dry runs,
# not "the binary exists".
check_tool_assumptions() {
    local bwrap_path bwrap_mode help flag rc=0

    bwrap_path="$(command -v bwrap)" || die "required command not found: bwrap"
    bwrap_path="$(readlink -f -- "$bwrap_path")" || die "could not resolve bwrap"
    [[ -f "$bwrap_path" && ! -L "$bwrap_path" ]] || die "bwrap is not a regular file: $bwrap_path"
    bwrap_mode="$(stat -c '%a' -- "$bwrap_path")" || die "could not stat $bwrap_path"
    # A setuid bwrap would change the privilege model this script assumes.
    (((8#$bwrap_mode & 8#6000) == 0)) || die "bwrap must not be setuid or setgid (mode $bwrap_mode): $bwrap_path"

    help="$(bwrap --help 2>&1)" || die "bwrap --help failed"
    for flag in --json-status-fd --unshare-user --unshare-pid --unshare-ipc --unshare-uts \
        --unshare-cgroup --cap-drop --uid --gid --size --perms --new-session --hostname; do
        [[ "$help" == *"$flag"* ]] || die "installed bwrap does not support $flag"
    done

    help="$(wget --help 2>&1)" || die "wget --help failed"
    for flag in --https-only --no-config --no-proxy --no-netrc; do
        [[ "$help" == *"$flag"* ]] || die "wget does not support $flag"
    done

    help="$(sha512sum --help 2>&1)" || die "sha512sum --help failed"
    [[ "$help" == *--strict* ]] || die "sha512sum does not support --strict"

    help="$(setsid --help 2>&1)" || die "setsid --help failed"
    [[ "$help" == *"--fork"* ]] || die "setsid does not support -f/--fork (util-linux setsid is required)"

    [[ "$(printf '1.2\n1.10\n' | LC_ALL=C sort -V | tail -n 1)" == "1.10" ]] \
        || die "sort -V is not version sort (1.10 should sort after 1.2)"

    # The bracket expression cannot match pgrep's own command line. Exit 1 means not running.
    pgrep -u "$(id -u)" -f '[j]oplin_run_absent_probe' >/dev/null 2>&1 || rc=$?
    ((rc == 1)) || die "pgrep must exit 1 when no process matches (got $rc)"

    [[ -x /usr/bin/env && -x /usr/bin/sh && -x /usr/bin/true && -x /usr/bin/sleep && -x /usr/bin/stat ]] \
        || die "required runtime binaries missing under /usr/bin (env, sh, true, sleep, stat)"
}

check_platform() {
    # Not root. HOME must be a real directory we own, not a symlink and not group/world writable.
    ((EUID != 0)) || die "refusing to run as root"
    [[ "${HOME:-}" == /* ]] || die "HOME is not set to an absolute directory"
    require_real_dir "$HOME"
    require_not_shared_writable "$HOME"

    local cmd
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
    done
    [[ -d "$JOPLIN_DIR" ]] || die "directory not found: $JOPLIN_DIR"
    require_real_dir "$JOPLIN_DIR"
    require_not_shared_writable "$JOPLIN_DIR"

    # Ubuntu 24.04+ only. A derivative that sets ID_LIKE=ubuntu but not ID=ubuntu is rejected.
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
    local major="${os_version%%.*}" minor="${os_version#*.}"
    ((10#$major > 24 || (10#$major == 24 && 10#$minor >= 4))) \
        || die "Ubuntu 24.04 or newer is required (found: $os_version)"

    local link
    for link in /bin /lib /lib64; do
        [[ -L "$link" ]] || die "merged-/usr layout expected, but $link is not a symlink"
        [[ "$(readlink -f "$link")" == "/usr${link}" ]] \
            || die "merged-/usr layout expected, but $link does not resolve to /usr${link}"
    done
    [[ -d /etc/ssl/certs && -d /etc/fonts && -r /etc/localtime ]] \
        || die "required system files are missing: /etc/ssl/certs, /etc/fonts or /etc/localtime"
    # systemd-resolved stub resolver (Ubuntu default); the sandbox gets a synthetic resolv.conf for it.
    local stub line found=0
    stub="$(readlink -f -- /etc/resolv.conf)" || die "could not resolve /etc/resolv.conf"
    [[ "$stub" == /run/systemd/resolve/stub-resolv.conf ]] \
        || die "/etc/resolv.conf must point to the systemd-resolved stub (Ubuntu default)"
    while IFS= read -r line; do
        [[ "$line" == "nameserver 127.0.0.53" ]] && found=1
    done <"$stub"
    ((found == 1)) || die "systemd-resolved stub does not list nameserver 127.0.0.53"
    systemctl is-active --quiet systemd-resolved || die "systemd-resolved is not active"

    check_tool_assumptions
}

# A Wayland session and a private runtime directory are required; take the single-instance lock.
# X11 is not supported: any other session type, an absolute WAYLAND_DISPLAY, or a
# missing, unowned, or symlinked socket aborts. DISPLAY is cleared before launch.
check_session() {
    [[ "${XDG_RUNTIME_DIR:-}" == /* ]] || die "XDG_RUNTIME_DIR must be an absolute path"
    require_real_dir "$XDG_RUNTIME_DIR"
    local runtime_mode
    runtime_mode="$(stat -c '%a' -- "$XDG_RUNTIME_DIR")" || die "could not stat $XDG_RUNTIME_DIR"
    (((8#$runtime_mode & 8#077) == 0)) \
        || die "XDG_RUNTIME_DIR must not be group/world accessible ($runtime_mode): $XDG_RUNTIME_DIR"
    [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || die "a Wayland session is required (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset})"
    [[ "${WAYLAND_DISPLAY:-}" =~ ^[A-Za-z0-9_-]+$ ]] \
        || die "WAYLAND_DISPLAY must be a plain socket name like wayland-0 (a Wayland session is required; X11 is not supported)"
    wayland_socket="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    [[ ! -L "$wayland_socket" && -S "$wayland_socket" && -O "$wayland_socket" ]] \
        || die "Wayland socket not found, not owned by the current user, or is a symlink: $wayland_socket"

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
        # Do not trust bwrap's default uid map. Pin both ids so they match the
        # synthetic passwd; a uid of 0 would make Electron treat itself as root.
        --uid "$(id -u)"
        --gid "$(id -g)"
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
        # No --unshare-net: the network namespace stays shared. --share-net is not
        # passed; this bwrap accepts it only together with --unshare-all. The
        # preflight aborts if the network namespace is not the host's.
    )
    scope_cmd=(systemd-run --user --scope --quiet -p "MemoryMax=${MEMORY_MAX}" -p MemorySwapMax=0 -p "TasksMax=${TASKS_MAX}" --)
    printf 'GUI access: Wayland (%s)\n' "$wayland_socket"
}

# Probe run inside the configured sandbox. /bin/sh is dash; keep this POSIX.
write_sandbox_probe() {
    cat >"${work_dir}/probe.sh" <<'EOF'
set -eu
fail() {
    printf 'sandbox check failed: %s\n' "$1" >&2
    exit 1
}
[ "$#" -eq 13 ] || fail "internal error: expected 13 arguments, got $#"

uid=$(id -u)
gid=$(id -g)
[ "$uid" = "$1" ] || fail "uid is ${uid}, expected ${1}"
[ "$gid" = "$2" ] || fail "gid is ${gid}, expected ${2}"
[ "$uid" != 0 ] || fail "uid is 0; refusing to run as root inside the sandbox"

host_name=""
read -r host_name </proc/sys/kernel/hostname || fail "could not read sandbox hostname"
[ "$host_name" = joplin ] || fail "hostname is ${host_name}, expected joplin"

cap=""
while read -r key val _; do
    if [ "$key" = "CapEff:" ]; then
        cap=$val
    fi
done </proc/self/status
[ -n "$cap" ] || fail "CapEff is missing"
case "$cap" in
    *[!0]*) fail "capabilities are not dropped (CapEff=${cap})" ;;
esac

[ "$(readlink /proc/self/ns/net)" = "$3" ] || fail "network namespace is not shared with the host"
[ "$(readlink /proc/self/ns/pid)" != "$4" ] || fail "pid namespace is not isolated"
[ "$(readlink /proc/self/ns/ipc)" != "$5" ] || fail "ipc namespace is not isolated"
[ "$(readlink /proc/self/ns/uts)" != "$6" ] || fail "uts namespace is not isolated"
[ "$(readlink /proc/self/ns/user)" != "$7" ] || fail "user namespace is not isolated"
[ "$(readlink /proc/self/ns/cgroup)" != "$8" ] || fail "cgroup namespace is not isolated"

passwd_line=""
read -r passwd_line </etc/passwd || fail "could not read /etc/passwd"
[ "$passwd_line" = "joplin:x:${uid}:${gid}:joplin:/home/joplin:/usr/sbin/nologin" ] \
    || fail "unexpected /etc/passwd: ${passwd_line}"
group_line=""
read -r group_line </etc/group || fail "could not read /etc/group"
[ "$group_line" = "joplin:x:${gid}:" ] || fail "unexpected /etc/group: ${group_line}"

line_no=0
while IFS= read -r line; do
    line_no=$((line_no + 1))
    case "$line_no" in
        1) [ "$line" = "127.0.0.1 localhost" ] || fail "unexpected /etc/hosts line 1: ${line}" ;;
        2) [ "$line" = "::1 localhost" ] || fail "unexpected /etc/hosts line 2: ${line}" ;;
        *) fail "unexpected extra /etc/hosts line: ${line}" ;;
    esac
done </etc/hosts
[ "$line_no" -eq 2 ] || fail "/etc/hosts has ${line_no} lines, expected 2"

line_no=0
while IFS= read -r line; do
    line_no=$((line_no + 1))
    case "$line_no" in
        1) [ "$line" = "nameserver 127.0.0.53" ] || fail "unexpected resolv.conf line 1: ${line}" ;;
        2) [ "$line" = "options edns0 trust-ad" ] || fail "unexpected resolv.conf line 2: ${line}" ;;
        *) fail "unexpected extra resolv.conf line: ${line}" ;;
    esac
done </etc/resolv.conf
[ "$line_no" -eq 2 ] || fail "resolv.conf has ${line_no} lines, expected 2"

line_no=0
while IFS= read -r line; do
    line_no=$((line_no + 1))
    case "$line_no" in
        1) [ "$line" = "passwd: files" ] || fail "unexpected nsswitch line 1: ${line}" ;;
        2) [ "$line" = "group: files" ] || fail "unexpected nsswitch line 2: ${line}" ;;
        3) [ "$line" = "hosts: files dns" ] || fail "unexpected nsswitch line 3: ${line}" ;;
        *) fail "unexpected extra nsswitch line: ${line}" ;;
    esac
done </etc/nsswitch.conf
[ "$line_no" -eq 3 ] || fail "nsswitch.conf has ${line_no} lines, expected 3"

[ ! -e "$9" ] || fail "host path is visible inside the sandbox: $9"
[ ! -e /dev/dri ] || fail "GPU device /dev/dri is exposed"
[ ! -e /dev/nvidiactl ] || fail "GPU device /dev/nvidiactl is exposed"
[ ! -e /dev/snd ] || fail "audio device /dev/snd is exposed"
[ ! -d /tmp/.X11-unix ] || fail "X11 socket directory is exposed"
[ ! -e /run/dbus ] || fail "D-Bus system socket directory is exposed"
[ ! -S /run/joplin/bus ] || fail "session D-Bus socket is exposed"
[ -w "${10}" ] || fail "data directory is not writable"
[ -w "${11}" ] || fail "Sharedrop is not writable"
[ -w "${12}" ] || fail "sandbox home is not writable"
[ -w /tmp ] || fail "/tmp is not writable"
[ -S "${13}" ] || fail "Wayland socket is missing in the sandbox"
[ -L /bin ] && [ "$(readlink /bin)" = usr/bin ] || fail "/bin is not a symlink to usr/bin"
[ -L /lib ] && [ "$(readlink /lib)" = usr/lib ] || fail "/lib is not a symlink to usr/lib"
[ -L /lib64 ] && [ "$(readlink /lib64)" = usr/lib64 ] || fail "/lib64 is not a symlink to usr/lib64"

usr_opts=""
while read -r _src dest _fstype opts _rest; do
    if [ "$dest" = "/usr" ]; then
        usr_opts=$opts
    fi
done </proc/mounts
[ -n "$usr_opts" ] || fail "/usr is not mounted"
case ",${usr_opts}," in
    *,ro,*) ;;
    *) fail "/usr is not read-only (${usr_opts})" ;;
esac

mode=$(stat -c %a /run/joplin) || fail "could not stat /run/joplin"
case "$mode" in
    700 | 0700) ;;
    *) fail "/run/joplin mode is ${mode}, expected 700" ;;
esac
EOF
}

run_sandbox_probe() {
    local host_net host_pid host_ipc host_uts host_user host_cgroup out
    host_net="$(readlink /proc/self/ns/net)" || die "could not read host network namespace"
    host_pid="$(readlink /proc/self/ns/pid)" || die "could not read host pid namespace"
    host_ipc="$(readlink /proc/self/ns/ipc)" || die "could not read host ipc namespace"
    host_uts="$(readlink /proc/self/ns/uts)" || die "could not read host uts namespace"
    host_user="$(readlink /proc/self/ns/user)" || die "could not read host user namespace"
    host_cgroup="$(readlink /proc/self/ns/cgroup)" || die "could not read host cgroup namespace"

    if ! out="$(bwrap "${sandbox_args[@]}" \
        --ro-bind "${work_dir}/probe.sh" /opt/probe.sh \
        "${sandbox_env[@]}" \
        -- /usr/bin/sh /opt/probe.sh \
        "$(id -u)" "$(id -g)" \
        "$host_net" "$host_pid" "$host_ipc" "$host_uts" "$host_user" "$host_cgroup" \
        "$JOPLIN_DIR" \
        "$SANDBOX_DATA" "$SANDBOX_SHARE" "$SANDBOX_HOME" \
        "${SANDBOX_RUNTIME}/wayland-0" \
        2>&1)"; then
        die "sandbox assumption checks failed; check user-namespace support (Ubuntu AppArmor): ${out:-bwrap exited non-zero}"
    fi
}

# Same supervisor chain as launch: setsid -f, systemd-run --scope, bwrap fd 3.
# Confirms the reported child PID is a live host PID inside the sandbox, then stops it.
check_status_channel() {
    local status_file="${work_dir}/preflight-status.json"
    local err_file="${work_dir}/preflight-status.err"
    : >"$status_file" || die "could not create status-fd preflight file"
    : >"$err_file" || die "could not create status-fd preflight log"

    setsid -f "${scope_cmd[@]}" bwrap \
        "${sandbox_args[@]}" \
        --json-status-fd 3 \
        "${sandbox_env[@]}" \
        -- /usr/bin/sleep 20 \
        3>"$status_file" {lock_fd}>&- </dev/null >/dev/null 2>"$err_file" \
        || die "could not start status-fd preflight"

    local status="" child_pid="" cmdline="" child_ns="" host_ns="" _
    local pid_regex='"child-pid":[[:space:]]*([0-9]+)'
    for _ in 1 2 3 4 5 6 7 8; do
        sleep 0.5
        status="$(<"$status_file")"
        if [[ "$status" =~ $pid_regex ]]; then
            child_pid="${BASH_REMATCH[1]}"
            break
        fi
    done
    if [[ -z "$child_pid" ]]; then
        local err
        err="$(head -c 500 -- "$err_file")"
        die "bwrap did not report a host child PID through systemd-run fd 3: ${err:-${status:-empty}}"
    fi
    [[ "$child_pid" != "$$" && "$child_pid" != 1 ]] \
        || die "status fd reported an unexpected pid: $child_pid"
    kill -0 "$child_pid" 2>/dev/null \
        || die "status fd child PID $child_pid is not alive in the host pid namespace"
    # argv[0] is bwrap for the sandbox supervisor. Do not signal anything else.
    # cmdline is NUL-separated; read only argv[0].
    IFS= read -r -d '' cmdline <"/proc/${child_pid}/cmdline" || die "could not read status-fd child cmdline"
    [[ "$cmdline" == *bwrap* ]] || die "refusing to signal pid $child_pid (not bubblewrap)"
    child_ns="$(readlink "/proc/${child_pid}/ns/pid")" || die "could not read status-fd child pid namespace"
    host_ns="$(readlink /proc/self/ns/pid)" || die "could not read host pid namespace"
    [[ "$child_ns" != "$host_ns" ]] || die "status fd PID $child_pid is not in an isolated pid namespace"

    status_probe_pid="$child_pid"
    # The pid is init of the sandbox pid namespace: it ignores SIGTERM from outside, so use SIGKILL.
    kill -KILL "$child_pid" 2>/dev/null || die "could not stop status-fd preflight (pid $child_pid)"
    for _ in 1 2 3 4 5 6 7 8; do
        kill -0 "$child_pid" 2>/dev/null || break
        sleep 0.25
    done
    if kill -0 "$child_pid" 2>/dev/null; then
        die "status-fd preflight pid $child_pid did not exit"
    fi
    status_probe_pid=""
}

# Exercise the exact mounts, namespaces, uid map and status fd before launching Joplin.
preflight() {
    local out
    if ! out="$("${scope_cmd[@]}" /usr/bin/true 2>&1)"; then
        die "systemd user scope with a memory limit is not available: $out"
    fi
    write_sandbox_probe
    run_sandbox_probe
    check_status_channel
    printf 'Confirmed: sandbox assumptions hold\n'
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

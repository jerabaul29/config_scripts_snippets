#!/usr/bin/env bash
# Safely run the latest local Joplin AppImage after verifying checksum and release version.

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
readonly RELEASES_URL="https://github.com/laurent22/joplin/releases/latest"
readonly TAG_REGEX='https://github\.com/laurent22/joplin/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)'
readonly FILE_REGEX='^Joplin-([0-9]+\.[0-9]+\.[0-9]+)\.AppImage$'

for cmd in wget sha512sum sort tail basename; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done
[[ -d "$JOPLIN_DIR" ]] || die "directory not found: $JOPLIN_DIR"

# 1. Latest local AppImage, by version in file name
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
printf 'Latest local AppImage: %s (version %s)\n' "$appimage" "$local_version"

# 2. Checksum verification
[[ -f "$sha_file" ]] || die "checksum file not found: $sha_file"
if ! sha_out="$(cd "$JOPLIN_DIR" && sha512sum -c -- "$(basename "$sha_file")" 2>&1)"; then
    die "sha512 verification FAILED for $appimage: $sha_out"
fi
grep -q 'OK' <<<"$sha_out" || die "sha512 verification gave unexpected output: $sha_out"
printf 'sha512 check OK: %s\n' "$sha_out"

# 3. Latest GitHub release
page="$(wget -qO- --timeout=30 --tries=2 "$RELEASES_URL")" || die "wget failed for $RELEASES_URL"
[[ -n "$page" ]] || die "empty response from $RELEASES_URL"

[[ "$page" =~ $TAG_REGEX ]] || die "no release tag URL found in response from $RELEASES_URL"
latest_version="${BASH_REMATCH[1]}"
printf 'Latest GitHub release: %s\n' "$latest_version"

# 4. Compare
[[ "$local_version" == "$latest_version" ]] \
    || die "local version ($local_version) differs from latest release ($latest_version); please update"
printf 'Confirmed: local AppImage is up to date (%s)\n' "$latest_version"

# 5. Start (bubblewrap to be added later)
printf 'Starting %s\n' "$appimage"
trap - ERR
exec "$appimage"

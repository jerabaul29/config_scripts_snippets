# Script for good practice run of Joplin AppImage

This should describe how to design a small bash script compatible with modern Ubuntu distros. The script should be in this folder, self contained, and named: `joplin_run.sh` .

The goal of the script is to make it easier to use Joplin in a safe way: making sure it is updated, and running well isolated with minimum sets of rights with bubblewrap.

Make sure the .sh script and this .md file are kept in sync and reflecting each other.

Assumptions about the system setup:
- There is one or more Joplin AppImage and associated sha512 files under `$HOME/Desktop/Software/Joplin` ; only the latest and most up to date should be run.
- The appimage can be run and the necessary packages are on the system so it runs without error - this is the user's responsibility.
- The bubblewrap (`bwrap`) program is installed - this is the user's responsibility.

Rules for the bash script:
- Use a preamble that makes bash as safe as possible.
- Make sure the script is always safe to run.
- Code defensively: make sure that any failed assumption or failed command makes the script abort and print an error message + return an error code.
- Check all assumptions actively.

Tasks that the bash script should implement and run in sequence (any failure should abort with error message and error code):
- Find the latest local version of the appimage in `$HOME/Desktop/Software/Joplin` and print it for the user.
  - File naming format: `Joplin-3.7.21.AppImage` with associated `Joplin-3.7.21.AppImage.sha512` (3.7.21 is only an example; the actual version may differ and be more recent).
  - "Latest" is determined from the version in the file name (version sort, e.g. `sort -V`), not from file modification time.
- Check that the sha512 for the latest local version (.sha512 corresponding file) is correct according to `sha512sum -c` and print it for the user.
- Get the latest version available by `wget https://github.com/laurent22/joplin/releases/latest` : use wget to fetch the page (e.g. `wget -qO-` to stdout), then match the version in its output (next step).
- Use a regexp with field capture to find the latest version released: it should be the first match for a string in the wget output looking like https://github.com/laurent22/joplin/releases/tag/v3.7.21 (note version is v. some number . some number . some number), and print the corresponding version for the user.
- Check that the appimage version is equal to the latest github release version, and print confirmation to the user.
- Check that Joplin is not already running (abort with an error if it is): use `pgrep` for the current user's processes matching the AppImage file name (`Joplin-X.Y.Z.AppImage`) or its `/tmp/.mount_Joplin*` mount; `pgrep` exit code 1 means not running, any other non-zero code is an error. Print confirmation to the user.
- Start the AppImage with bubblewrap (see the bubblewrap rules under), detached with `setsid -f` (own session, stdin from `/dev/null`, stdout/stderr appended to `${XDG_STATE_HOME:-$HOME/.local/state}/joplin_run.log`) so Joplin keeps running if the terminal is closed or killed. Use `APPIMAGE_EXTRACT_AND_RUN=1` so the verified AppImage does not need FUSE inside the sandbox. After a short wait, check it is still running and abort with an error if it exited immediately.

Bubblewrap rules (keep these rules in sync with `joplin_run.sh`):
- By default, everything not needed is locked away.
- Expose `/usr`, `/bin`, `/lib` (and `/lib64` when present) read-only for the application runtime. Expose only the needed host configuration read-only: hosts, name-service configuration, passwd/group, local time (and `/etc/timezone` when present), TLS certificates, fonts, and the resolved DNS configuration. Pass through `LANG`, `LANGUAGE`, and host `LC_*` values without exposing more locale configuration.
- Provide isolated writable `/tmp` and home/cache/state paths. These are temporary and are not host directories.
- Allow persistent read/write access only to `$HOME/.config/joplin-desktop`.
- Allow the active GUI connection only: one Wayland socket (preferred when available) or one local X11 display socket and its optional read-only Xauthority file. Do not expose the rest of the user's home or session runtime sockets.
- Pass the GNOME GTK theme and color-scheme selection as the `GTK_THEME` environment variable when `gsettings` is available, rather than exposing the user's desktop settings database or D-Bus.
- Isolate the PID, IPC, and UTS namespaces. Leave the network namespace shared with the host so Joplin Cloud can connect.
- Bubblewrap cannot limit shared networking to Joplin Cloud. This configuration permits Joplin general network access; restricting it to Cloud requires a separate host firewall or proxy.
- GPU devices, audio, D-Bus/portals, keyring, notifications, and arbitrary host files are not exposed. Grant them separately only if a needed feature requires them. File import/export outside Joplin's data folder is intentionally unavailable by default.
- Before launch, the script runs a no-op inside the configured sandbox to verify Bubblewrap mounts and namespace support. The host must permit the namespaces Bubblewrap needs; an installed `bwrap` alone is not sufficient.

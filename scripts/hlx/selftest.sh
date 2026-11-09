#!/usr/bin/env bash
# Runs INSIDE the hlx sandbox (started by `hlx --self-test`, which also checks the host side
# afterwards). Every line of output is one test: "ok" when the sandbox behaves as intended.
#
# Two helpers keep the tests easy to read:
#   allowed "what should work"  COMMAND...   passes when COMMAND succeeds
#   blocked "what must fail"    COMMAND...   passes when COMMAND fails
#
# The paths below are set up by hlx.sh in a throwaway git repository under /tmp:
#   HLX_ST_REPO     the repository (opened folder is its sub/ directory -> repo is read-only)
#   HLX_ST_SUB      the opened folder, the only writable place
#   HLX_ST_OUTSIDE  a host directory next to the repo that is NOT shared with the sandbox
#   HLX_ST_DENIED   a file inside the opened folder that is listed in DENY_PATHS
#   HLX_ST_SECRET   an environment variable that must NOT reach the sandbox

SECCOMP_PY=/opt/hlx/seccomp.py
passed=0
failed=0

report() { # report STATUS DESCRIPTION
	if [[ $1 == ok ]]; then
		passed=$((passed + 1))
		printf '  ok    %s\n' "$2"
	else
		failed=$((failed + 1))
		printf '  FAIL  %s\n' "$2"
	fi
}

allowed() {
	local description=$1
	shift
	if "$@" >/dev/null 2>&1; then report ok "$description"; else report FAIL "$description"; fi
}

blocked() {
	local description=$1
	shift
	if "$@" >/dev/null 2>&1; then report FAIL "$description"; else report ok "$description"; fi
}

# a syscall probe must come back with exactly this errno (see seccomp.py --probe)
probe_returns() { # probe_returns ERRNO SYSCALL [ARG...]
	local expected=$1
	shift
	[[ "$(python3 "$SECCOMP_PY" --probe "$@" 2>&1)" == "$expected" ]]
}

status_field() { grep -E "^$1:[[:space:]]" /proc/self/status; }

echo "[isolation]"
blocked "no network: TCP connection to 1.1.1.1:53 fails" timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/53'
blocked "host ~/.ssh is not visible" test -e "$HOME/.ssh"
blocked "host ~/.bashrc is not visible" test -e "$HOME/.bashrc"
blocked "host files outside the opened folder are not visible" test -e "$HLX_ST_OUTSIDE/canary"
blocked "the host environment is not inherited (HLX_ST_SECRET)" test -n "${HLX_ST_SECRET:-}"
blocked "no docker socket" test -e /var/run/docker.sock
if [[ "$(dirname "$HOME")" != / ]]; then
	allowed "other users' home directories are not visible" \
		test "$(ls -A "$(dirname "$HOME")")" == "$(basename "$HOME")"
fi
allowed "own PID namespace (host processes are not visible)" test "$$" -lt 50

echo "[privileges]"
allowed "all capabilities are dropped (CapEff is zero)" bash -c "$(declare -f status_field); status_field CapEff | grep -Eq '[[:space:]]0+\$'"
allowed "no_new_privs is set (setuid binaries gain nothing)" bash -c "$(declare -f status_field); status_field NoNewPrivs | grep -q '1\$'"
allowed "a seccomp filter is active" bash -c "$(declare -f status_field); status_field Seccomp | grep -q '2\$'"
blocked "creating a nested user namespace fails" unshare --user --map-root-user true
blocked "mounting a filesystem fails" mount -t tmpfs none /mnt

echo "[seccomp: denied syscalls fail with EPERM, their normal result is a different error]"
allowed "an ordinary syscall still works (getpid)" probe_returns OK getpid
allowed "io_uring_setup is denied" probe_returns EPERM io_uring_setup 0 0
allowed "perf_event_open is denied" probe_returns EPERM perf_event_open 0 0 0 0 0
allowed "add_key (kernel keyring) is denied" probe_returns EPERM add_key
allowed "process_vm_readv (read other processes' memory) is denied" probe_returns EPERM process_vm_readv 0 0 0 0 0 0
allowed "ioctl TIOCSTI (keystroke injection) is denied" bash -c "exec 3</dev/null; python3 $SECCOMP_PY --probe ioctl 3 0x5412 0 | grep -qx EPERM"
allowed "other ioctls still work (TCGETS on /dev/null gives ENOTTY, not EPERM)" bash -c "exec 3</dev/null; python3 $SECCOMP_PY --probe ioctl 3 0x5401 0 | grep -qx ENOTTY"

echo "[filesystem: the repo is read-only, only the opened folder is writable]"
allowed "write inside the opened folder" touch "$HLX_ST_SUB/ok"
blocked "write elsewhere in the repo" touch "$HLX_ST_REPO/escape"
blocked "modify a tracked file of the repo" bash -c "echo x >> '$HLX_ST_REPO/tracked.txt'"
blocked "write into the repo's .git" touch "$HLX_ST_REPO/.git/escape"
blocked "create a .git inside the opened folder (it could carry hooks)" touch "$HLX_ST_SUB/.git/pre-commit"
blocked "create a .helix inside the opened folder (it can run commands)" touch "$HLX_ST_SUB/.helix/languages.toml"
blocked "write to a host directory next to the repo" touch "$HLX_ST_OUTSIDE/escape"
blocked "read a DENY_PATHS file (it is masked)" test -s "$HLX_ST_DENIED"
blocked "write a DENY_PATHS file" bash -c "echo x > '$HLX_ST_DENIED'"
blocked "write the helix config" touch "$HOME/.config/helix/escape"
allowed "the persistent cache dir is writable" bash -c "touch '$HOME/.cache/helix/.selftest' && rm '$HOME/.cache/helix/.selftest'"
allowed "\$HOME is a throwaway tmpfs (writes succeed but never reach the host)" touch "$HOME/hlx-selftest-marker"

echo "[git: reading works, changing history does not]"
allowed "git log works" git -C "$HLX_ST_REPO" log --oneline
allowed "git diff works (shows the uncommitted change)" bash -c "git -C '$HLX_ST_REPO' diff | grep -q '^+two'"
blocked "git commit fails (the .git directory is read-only)" \
	git -C "$HLX_ST_REPO" -c user.name=hlx -c user.email=hlx@localhost commit --allow-empty -q -m x

printf '\n%d passed, %d failed (inside the sandbox)\n' "$passed" "$failed"
((failed == 0))

#!/usr/bin/env python3
"""Seccomp filter for the hlx sandbox, built with libseccomp (libseccomp.so.2, preinstalled
on Ubuntu because systemd needs it; used through ctypes, so no Python package is needed).

    seccomp.py --out FILE [--allow NAME[,NAME...]]
        compile the filter to FILE (bwrap --seccomp FD reads it). hlx.sh does this
        automatically whenever FILE is missing or older than this script or libseccomp.
    seccomp.py --probe NAME [ARG...]
        call syscall NAME with integer arguments and print "OK" or the errno name
        (used by `hlx --self-test`; harmless arguments only)
    seccomp.py --check
        list DENY entries that libseccomp cannot resolve (typos would otherwise be skipped
        silently); exit status 1 unless all of them are known-optional on this architecture

Policy: allow everything except DENY, which fails with EPERM. It is a deny-list on top of the
namespaces and the dropped capabilities: defence in depth, not the primary barrier. libseccomp
resolves names per architecture, and names unknown to the running kernel headers are skipped.

memfd_create is deliberately not denied: runtimes (JITs, wasm, some language servers) use it and
anonymous files cannot escape the sandbox anyway.

TODO: go through DENY again from time to time and deny more. New syscalls appear every kernel
release (the mount API and io_uring came after most deny-lists were written). Candidates:
socket families (AF_NETLINK, AF_PACKET), seccomp, prctl options, pkey_*, and eventually an
allow-list built from the real syscall set of helix + language servers.
"""

import ctypes
import errno
import os
import sys

DENY = """
kexec_load kexec_file_load init_module finit_module delete_module create_module get_kernel_syms
query_module nfsservctl reboot swapon swapoff acct quotactl quotactl_fd syslog uselib modify_ldt
iopl ioperm pivot_root chroot mount umount umount2 move_mount open_tree fsopen fsconfig fsmount
fspick mount_setattr unshare setns ptrace process_vm_readv process_vm_writev pidfd_getfd kcmp
perf_event_open bpf userfaultfd io_uring_setup io_uring_enter io_uring_register add_key keyctl
request_key open_by_handle_at name_to_handle_at lookup_dcookie fanotify_init settimeofday
clock_settime clock_settime64 clock_adjtime adjtimex sethostname setdomainname mbind get_mempolicy
set_mempolicy migrate_pages move_pages set_mempolicy_home_node vhangup _sysctl sysfs
landlock_create_ruleset landlock_add_rule landlock_restrict_self memfd_secret
""".split()
# Names that legitimately do not exist on every architecture / libseccomp version (removed
# legacy calls, x86-only calls, 32-bit-only calls, very new calls); --check tolerates these.
OPTIONAL = set("""
create_module get_kernel_syms query_module nfsservctl uselib _sysctl lookup_dcookie modify_ldt
iopl ioperm umount clock_settime64 quotactl_fd set_mempolicy_home_node
""".split())

# Argument-dependent rules.
# clone(2) flags that create namespaces (NEWTIME NEWNS NEWCGROUP NEWUTS NEWIPC NEWUSER NEWPID NEWNET)
CLONE_NEW_FLAGS = [0x80, 0x20000, 0x2000000, 0x4000000, 0x8000000, 0x10000000, 0x20000000, 0x40000000]
# ioctls that inject keystrokes / redirect the console
BAD_IOCTLS = {"TIOCSTI": 0x5412, "TIOCCONS": 0x541D, "TIOCLINUX": 0x541C}
# personality(2) flags that weaken exploit mitigations: MMAP_PAGE_ZERO, ADDR_COMPAT_LAYOUT,
# READ_IMPLIES_EXEC
# (libseccomp allows one comparison per argument per rule, so the 0xffffffff "query" call, which
# has these bits set, is denied too; nothing in a normal editor session uses it)
PERSONALITY_BAD_FLAGS = [0x0100000, 0x0200000, 0x0400000]

SCMP_ACT_ALLOW = 0x7FFF0000
SCMP_ACT_ERRNO = lambda e: 0x00050000 | e  # noqa: E731
SCMP_CMP_MASKED_EQ = 7


class ArgCmp(ctypes.Structure):  # struct scmp_arg_cmp
    _fields_ = [("arg", ctypes.c_uint), ("op", ctypes.c_int),
                ("datum_a", ctypes.c_uint64), ("datum_b", ctypes.c_uint64)]


def load_libseccomp():
    try:
        lib = ctypes.CDLL("libseccomp.so.2", use_errno=True)
    except OSError:
        raise SystemExit("seccomp.py: libseccomp.so.2 not found (sudo apt install libseccomp2), "
                         "or set HLX_SECCOMP=off")
    lib.seccomp_init.restype = ctypes.c_void_p
    lib.seccomp_init.argtypes = [ctypes.c_uint32]
    lib.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    lib.seccomp_rule_add_array.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int,
                                           ctypes.c_uint, ctypes.POINTER(ArgCmp)]
    lib.seccomp_export_bpf.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.seccomp_release.argtypes = [ctypes.c_void_p]
    return lib


def build(lib, out_path, allow):
    ctx = lib.seccomp_init(SCMP_ACT_ALLOW)
    if not ctx:
        raise SystemExit("seccomp.py: seccomp_init failed")

    def add(action, name, *cmps):
        nr = lib.seccomp_syscall_resolve_name(name.encode())
        if nr < 0:  # unknown on this architecture/kernel headers
            return
        arr = (ArgCmp * max(len(cmps), 1))(*[ArgCmp(*c) for c in cmps])
        rc = lib.seccomp_rule_add_array(ctx, action, nr, len(cmps), arr)
        if rc != 0:
            raise SystemExit(f"seccomp.py: rule for {name} failed: {os.strerror(-rc)}")

    eperm = SCMP_ACT_ERRNO(errno.EPERM)
    for name in DENY:
        if name not in allow:
            add(eperm, name)
    for flag in CLONE_NEW_FLAGS:
        add(eperm, "clone", (0, SCMP_CMP_MASKED_EQ, flag, flag))
    # clone3 passes its flags in a user struct that seccomp cannot inspect; ENOSYS makes glibc
    # fall back to clone(2), which is filtered above
    add(SCMP_ACT_ERRNO(errno.ENOSYS), "clone3")
    for request in BAD_IOCTLS.values():
        add(eperm, "ioctl", (1, SCMP_CMP_MASKED_EQ, 0xFFFFFFFF, request))
    if "personality" not in allow:
        for flag in PERSONALITY_BAD_FLAGS:
            add(eperm, "personality", (0, SCMP_CMP_MASKED_EQ, flag, flag))

    tmp = f"{out_path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        rc = lib.seccomp_export_bpf(ctx, fd)
    finally:
        os.close(fd)
        lib.seccomp_release(ctx)
    if rc != 0:
        os.unlink(tmp)
        raise SystemExit(f"seccomp.py: export failed: {os.strerror(-rc)}")
    os.replace(tmp, out_path)  # atomic: concurrent hlx sessions never see a half-written file


def probe(lib, name, args):
    nr = lib.seccomp_syscall_resolve_name(name.encode())
    if nr < 0:
        raise SystemExit(f"seccomp.py: unknown syscall {name!r}")
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    ret = libc.syscall(ctypes.c_long(nr), *[ctypes.c_long(int(a, 0)) for a in args])
    err = ctypes.get_errno()
    print("OK" if ret >= 0 else errno.errorcode.get(err, str(err)))


def check(lib):
    unresolved = [n for n in DENY if lib.seccomp_syscall_resolve_name(n.encode()) < 0]
    for name in unresolved:
        print(name + (" (optional)" if name in OPTIONAL else ""))
    sys.exit(1 if any(n not in OPTIONAL for n in unresolved) else 0)


def main(argv):
    lib = load_libseccomp()
    if argv[:1] == ["--probe"] and len(argv) >= 2:
        probe(lib, argv[1], argv[2:])
    elif argv == ["--check"]:
        check(lib)
    elif argv[:1] == ["--out"] and (len(argv) == 2 or (len(argv) == 4 and argv[2] == "--allow")):
        allow = set()
        if len(argv) == 4:
            allow = {n for n in argv[3].split(",") if n}
            unknown = allow - set(DENY) - {"personality"}
            if unknown:
                raise SystemExit(f"seccomp.py: not in the deny list: {', '.join(sorted(unknown))}")
        build(lib, argv[1], allow)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])

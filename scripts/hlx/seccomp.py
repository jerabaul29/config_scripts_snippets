#!/usr/bin/env python3
"""Seccomp filter for the hlx sandbox, built with libseccomp (libseccomp.so.2, preinstalled
on Ubuntu because systemd needs it; used through ctypes, so no Python package is needed).

    seccomp.py --out FILE [--allow NAME[,NAME...]]
        compile the filter to FILE (bwrap --seccomp FD reads it). hlx.sh does this
        automatically whenever FILE is missing or older than this script or libseccomp.
    seccomp.py --probe NAME [ARG...]
        call a self-test syscall NAME with integer arguments and print "OK" or the errno
        name (used by `hlx --self-test`). Names outside that set are refused: this is not
        a general syscall invoker, including on the host where no filter is installed.
    seccomp.py --check
        list DENY entries that libseccomp cannot resolve (typos would otherwise be skipped
        silently); exit status 1 unless all of them are known-optional on this architecture

Policy: allow everything except DENY, which fails with EPERM. It is a deny-list on top of the
namespaces and the dropped capabilities: defence in depth, not the primary barrier. libseccomp
resolves names per architecture, and names unknown to the running kernel headers are skipped.

memfd_create is deliberately not denied: runtimes (JITs, wasm, some language servers) use it and
anonymous files cannot escape the sandbox anyway.

link and linkat are denied as defence in depth: hard links would alias read-only inodes
(.git hooks, the helix config, AppRun) into a writable directory. The kernel already refuses
links across the sandbox's separate mounts (EXDEV); the filter keeps that from depending on
the mount layout. symlink is not denied; a symlink cannot name a file this mount namespace
did not mount. See LINKS in hlx.sh. If a real tool breaks, prefer Landlock REFER over
SECCOMP_ALLOW=link,linkat.

Also denied: socket()/socketpair() for kernel-attack-surface families (netlink, packet, vsock,
bluetooth, alg, ...; EAFNOSUPPORT, so programs fall back cleanly). AF_UNIX, AF_INET and AF_INET6
stay: Helix talks to its language servers over pipes, but some servers listen on loopback.
SECCOMP_ALLOW=(socket) lifts the family filter (some tools list interfaces through AF_NETLINK).
seccomp(2) and prctl(PR_SET_SECCOMP) are denied (nothing in an editor session installs filters,
and SECCOMP_RET_USER_NOTIF is a way to stall the process); SECCOMP_ALLOW=(seccomp) lifts both.
vmsplice is denied (page-cache write primitive in several kernel exploits).
splice stays: pipes between git and helpers use it.

TODO: go through DENY again from time to time and deny more. New syscalls appear every kernel
release (the mount API and io_uring came after most deny-lists were written). Candidates:
other prctl options, pkey_*, and eventually an allow-list built from the real syscall set of
helix + language servers.
"""

import ctypes
import errno
import os
import platform
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
link linkat seccomp vmsplice
""".split()  # noqa: SIM905
# not syscall names of their own: SECCOMP_ALLOW=socket lifts the socket-family rules
PSEUDO_ALLOW = {"personality", "socket"}
# Names that legitimately do not exist on every architecture / libseccomp version (removed
# legacy calls, x86-only calls, 32-bit-only calls, very new calls); --check tolerates these.
OPTIONAL = set("""
create_module get_kernel_syms query_module nfsservctl uselib _sysctl lookup_dcookie modify_ldt
iopl ioperm umount clock_settime64 quotactl_fd set_mempolicy_home_node link sysfs
""".split())  # noqa: SIM905

# Argument-dependent rules.
# clone(2) flags that create namespaces (NEWTIME NEWNS NEWCGROUP NEWUTS NEWIPC NEWUSER NEWPID NEWNET)
# On s390x (and cris) clone's flags are the second argument, not the first.
CLONE_FLAGS_ARG = 1 if platform.machine() == "s390x" else 0
CLONE_NEW_FLAGS = [0x80, 0x20000, 0x2000000, 0x4000000, 0x8000000, 0x10000000, 0x20000000, 0x40000000]
# ioctls that inject keystrokes / redirect the console
BAD_IOCTLS = {"TIOCSTI": 0x5412, "TIOCCONS": 0x541D, "TIOCLINUX": 0x541C}
# personality(2) flags that weaken exploit mitigations: ADDR_NO_RANDOMIZE (turns ASLR off),
# MMAP_PAGE_ZERO, ADDR_COMPAT_LAYOUT, READ_IMPLIES_EXEC
# (libseccomp allows one comparison per argument per rule, so the 0xffffffff "query" call, which
# has these bits set, is denied too; nothing in a normal editor session uses it)
PERSONALITY_BAD_FLAGS = [0x0040000, 0x0100000, 0x0200000, 0x0400000]
# socket families other than AF_UNIX(1), AF_INET(2), AF_INET6(10): AX25 IPX APPLETALK NETROM BRIDGE
# AAL5 X25 ROSE DECnet NETBEUI SECURITY KEY NETLINK PACKET ASH ECONET ATMSVC RDS IRDA PPPOX WANPIPE
# LLC IB MPLS CAN TIPC BLUETOOTH IUCV RXRPC ISDN PHONET IEEE802154 CAIF ALG NFC VSOCK KCM QIPCRTR
# SMC XDP MCTP, plus headroom for families added later (AF_MAX is 46 in current kernels). An explicit list (not "everything but ...") because libseccomp takes one
# comparison per argument per rule, and unknown new families are rare enough to review here.
BAD_SOCKET_FAMILIES = list(range(3, 10)) + list(range(11, 64))
PR_SET_SECCOMP = 22

# --probe is a test hook, not a way to invoke reboot/delete_module/etc. on the host.
PROBE_ALLOW = set("""
getpid ioctl clone personality
io_uring_setup perf_event_open add_key process_vm_readv
landlock_create_ruleset link linkat socket seccomp vmsplice mount unshare
""".split())  # noqa: SIM905

SCMP_ACT_ALLOW = 0x7FFF0000


def SCMP_ACT_ERRNO(e):
    return 0x00050000 | e

SCMP_CMP_EQ = 4
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
        add(eperm, "clone", (CLONE_FLAGS_ARG, SCMP_CMP_MASKED_EQ, flag, flag))
    # clone3 passes its flags in a user struct that seccomp cannot inspect; ENOSYS makes glibc
    # fall back to clone(2), which is filtered above
    add(SCMP_ACT_ERRNO(errno.ENOSYS), "clone3")
    for request in BAD_IOCTLS.values():
        add(eperm, "ioctl", (1, SCMP_CMP_MASKED_EQ, 0xFFFFFFFF, request))
    if "personality" not in allow:
        for flag in PERSONALITY_BAD_FLAGS:
            add(eperm, "personality", (0, SCMP_CMP_MASKED_EQ, flag, flag))

    if "socket" not in allow:
        for family in BAD_SOCKET_FAMILIES:
            for name in ("socket", "socketpair"):
                add(SCMP_ACT_ERRNO(errno.EAFNOSUPPORT), name, (0, SCMP_CMP_EQ, family))
    if "seccomp" not in allow:
        add(eperm, "prctl", (0, SCMP_CMP_EQ, PR_SET_SECCOMP))

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
    if name not in PROBE_ALLOW:
        raise SystemExit(f"seccomp.py: --probe refuses {name!r} (not a self-test syscall)")
    nr = lib.seccomp_syscall_resolve_name(name.encode())
    if nr < 0:
        if name in OPTIONAL:  # e.g. link on aarch64: nothing to deny
            print("ABSENT")
            return
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
            unknown = allow - set(DENY) - PSEUDO_ALLOW
            if unknown:
                raise SystemExit(f"seccomp.py: not in the deny list: {', '.join(sorted(unknown))}")
        build(lib, argv[1], allow)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])

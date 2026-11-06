#!/usr/bin/env python3
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
"""Read/write PS4 HDMI bridge (MN86471A / MN864729) registers from userspace.

Uses the PS4 kernel's ICC character device (major 73, ioctl ICC_IOCTL_CMD) and
the same I2C command-queue format as drivers/gpu/drm/amd/amdgpu/ps4_bridge.c
(ICC major 0x10). Run as root on the PS4.

  ps4-bridge.py read ADDR [COUNT]        e.g. read 0x60f8 2
  ps4-bridge.py write ADDR VALUE
  ps4-bridge.py mask ADDR VALUE MASK
  ps4-bridge.py dump ADDR COUNT          hex dump, one read per 16 bytes
"""
import ctypes
import fcntl
import os
import stat
import struct
import sys

DEV = "/dev/icc"
ICC_MAJOR_NR = 73

# Bridge command codes (major, minor) from ps4_bridge.c
CMD_READ = (1, 1)
CMD_WRITE = (2, 2)
CMD_MASK = (2, 3)


class IccCmd(ctypes.Structure):
    _fields_ = [
        ("major", ctypes.c_uint8),
        ("minor", ctypes.c_uint16),
        ("data", ctypes.c_void_p),
        ("length", ctypes.c_uint16),
        ("reply", ctypes.c_void_p),
        ("reply_length", ctypes.c_uint16),
    ]


ICC_IOCTL_CMD = (3 << 30) | (ctypes.sizeof(IccCmd) << 16) | (ord("I") << 8) | 1


def open_icc():
    if not os.path.exists(DEV):
        os.mknod(DEV, 0o600 | stat.S_IFCHR, os.makedev(ICC_MAJOR_NR, 0))
    return os.open(DEV, os.O_RDWR)


def icc(fd, major, minor, payload, reply_len=0x7F0):
    data = ctypes.create_string_buffer(bytes(payload), len(payload))
    reply = ctypes.create_string_buffer(reply_len)
    cmd = IccCmd(major, minor, ctypes.cast(data, ctypes.c_void_p), len(payload),
                 ctypes.cast(reply, ctypes.c_void_p), reply_len)
    n = fcntl.ioctl(fd, ICC_IOCTL_CMD, cmd)
    return n, reply.raw


def queue(fd, ops, code=4):
    """ops: list of ((major, minor), payload). Same-type neighbours are grouped
    under one header, as cq_cmd() does."""
    body = b""
    groups = 0
    i = 0
    while i < len(ops):
        kind = ops[i][0]
        chunk = b""
        count = 0
        while i < len(ops) and ops[i][0] == kind:
            chunk += ops[i][1]
            count += 1
            i += 1
        hdr = struct.pack("<BBBB", kind[0], 4 + len(chunk), kind[1], count)
        body += hdr + chunk
        groups += 1
    req = struct.pack("<BHB", code, 4 + len(body), groups) + body
    n, rep = icc(fd, 0x10, 0, req)
    if n < 5 or rep[0] != 0 or rep[1] != 0:
        raise RuntimeError(f"bridge command failed: len={n} res={rep[0]},{rep[1]}")
    return n, rep


def read(fd, addr, count=1):
    n, rep = queue(fd, [(CMD_READ, bytes([count]) + struct.pack(">H", addr) + b"\x00")],
                   code=1)
    if n < 8 + count:
        raise RuntimeError(f"short read reply ({n} bytes)")
    return rep[8:8 + count]


def write(fd, addr, value):
    queue(fd, [(CMD_WRITE, b"\x01" + struct.pack(">H", addr) + bytes([value]))])


def mask(fd, addr, value, m):
    queue(fd, [(CMD_MASK, b"\x01" + struct.pack(">H", addr) + bytes([value, m]))])


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    fd = open_icc()
    op, args = argv[1], [int(a, 0) for a in argv[2:]]
    if op == "read":
        data = read(fd, args[0], args[1] if len(args) > 1 else 1)
        print(" ".join(f"{args[0] + i:#06x}={b:#04x}" for i, b in enumerate(data)))
    elif op == "write":
        write(fd, args[0], args[1])
        print(f"wrote {args[1]:#04x} to {args[0]:#06x}")
    elif op == "mask":
        mask(fd, args[0], args[1], args[2])
        print(f"masked {args[0]:#06x} value {args[1]:#04x} mask {args[2]:#04x}")
    elif op == "dump":
        base, count = args
        for off in range(0, count, 16):
            n = min(16, count - off)
            data = read(fd, base + off, n)
            print(f"{base + off:#06x}: " + " ".join(f"{b:02x}" for b in data))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

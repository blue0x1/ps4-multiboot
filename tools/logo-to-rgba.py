#!/usr/bin/env python3
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
"""Convert a distro logo (PNG or SVG rendered to PNG) into the installer's format.

  tools/logo-to-rgba.py LOGO.png assets/logos/<name>.rgba

The logo is scaled to fit 480x270 (the size the install screens use; the menu
scales it down again). Output: u32 width, u32 height (little endian), RGBA.
"""
import struct
import sys

from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
bbox = img.getchannel("A").getbbox()  # drop empty borders
if bbox:
    img = img.crop(bbox)
img.thumbnail((480, 270), Image.LANCZOS)
with open(dst, "wb") as f:
    f.write(struct.pack("<II", *img.size))
    f.write(img.tobytes())
print(f"{dst}: {img.size[0]}x{img.size[1]}")

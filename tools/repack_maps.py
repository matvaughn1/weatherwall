#!/usr/bin/env python3
"""Repack old 4-channel maps into RGB-only images.

Qt premultiplies image alpha on load, which wipes the colour channels wherever
alpha is 0, so data must not live in the alpha channel. New layout:

  maps.png   R = distance  G = sky     B = ground
  maps2.png  R = faces up  G = lights  B = mirror line
  maps3.png  R = water     G = plants  B = unused
  decor.png  R = bulb      G = palette B = glow     (twinkle phase now from position)

usage: repack_maps.py PHOTO_DIR [...]   (safe to re-run: skips repacked folders)
"""
import os
import sys

from PIL import Image

for d in sys.argv[1:]:
    p1, p2, p3 = (os.path.join(d, n) for n in ("maps.png", "maps2.png", "maps3.png"))
    if not os.path.exists(p1) or os.path.exists(p3):
        continue
    m1 = Image.open(p1)
    m2 = Image.open(p2)
    if m1.mode != "RGBA":
        continue
    r1, g1, b1, a1 = m1.split()
    r2, g2, b2, a2 = m2.split()
    Image.merge("RGB", (a1, a2, Image.new("L", m1.size, 0))).save(p3, optimize=True)
    Image.merge("RGB", (r1, g1, b1)).save(p1, optimize=True)
    Image.merge("RGB", (r2, g2, b2)).save(p2, optimize=True)
    pd = os.path.join(d, "decor.png")
    if os.path.exists(pd):
        dc = Image.open(pd)
        if dc.mode == "RGBA":
            dc.convert("RGBA").split()
            r, g, b, _ = dc.split()
            Image.merge("RGB", (r, g, b)).save(pd, optimize=True)
    print("repacked", os.path.basename(d.rstrip("/")))

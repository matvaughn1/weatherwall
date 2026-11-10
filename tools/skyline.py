#!/usr/bin/env python3
"""Per-photo extras that only need the existing maps (no ML models):

  Skyline.qml  where the open sky ends in each of 64 columns (photo y, 0 = top),
               so fireworks burst in open sky and launch from behind the skyline
  maps2.png B  mirror line covering water as well as ground, so lakes and
               rivers reflect the sky (and the fireworks)
  sky.png      the sky mask at up to 1920 px wide, edge-fitted to the photo with a
               guided filter, so the live sky meets treetops and roofs without halos
  (run tools/repack_maps.py first on folders made before maps3.png existed)

usage: skyline.py PHOTO_DIR [PHOTO_DIR ...]   (folders holding maps.png)
"""
import os
import sys

import numpy as np
from PIL import Image

COLS = 64


def mirror_line(mask):
    """For each masked pixel, the top row (0..1) of its vertical run."""
    h = mask.shape[0]
    rows = np.arange(h)[:, None].repeat(mask.shape[1], 1)
    start = mask.copy()
    start[1:] &= ~mask[:-1]
    top = np.maximum.accumulate(np.where(start, rows, -1), axis=0)
    return np.where(mask, top / h, 0.0)


def box(a, r):
    """Mean over a (2r+1)^2 window, via integral images."""
    k = 2 * r + 1
    p = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    return (p[k:, k:] - p[:-k, k:] - p[k:, :-k] + p[:-k, :-k])[:a.shape[0], :a.shape[1]] / (k * k)


def guided(guide, src, r, eps):
    """He et al. guided filter: src smoothed but following guide's edges."""
    mi, mp = box(guide, r), box(src, r)
    cov = box(guide * src, r) - mi * mp
    var = box(guide * guide, r) - mi * mi
    a = cov / (var + eps)
    b = mp - a * mi
    return box(a, r) * guide + box(b, r)


def fine_sky(folder, sky):
    photo = Image.open(os.path.join(folder, "photo.jpg")).convert("RGB")
    w = min(1920, photo.width)
    h = round(photo.height * w / photo.width)
    rgb = np.asarray(photo.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255
    # sky is bright and blue-ish: use a guide that separates it from foliage well
    guide = 0.5 * rgb[..., 2] + 0.3 * rgb.mean(2) + 0.2 * (rgb[..., 2] - rgb[..., 0])
    coarse = np.asarray(Image.fromarray((sky * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR),
                        dtype=np.float32) / 255
    # The segmenter is cautious at the edges: gaps in treetops and slivers by
    # walls often read as "not sky". Near the sky, anything that matches the
    # sky's colour on that row is sky too.
    conf = coarse > 0.9
    ref = np.zeros((h, 3), np.float32)
    have = np.zeros(h, bool)
    for y in range(h):
        row = rgb[y][conf[y]]
        if len(row) > 8:
            ref[y] = np.median(row, 0)
            have[y] = True
    if have.any():
        idx = np.nonzero(have)[0]
        nearest = idx[np.clip(np.searchsorted(idx, np.arange(h)), 0, len(idx) - 1)]
        ref = ref[nearest]
        lowest = idx.max()
        near_sky = box(conf.astype(np.float32), 30) > 0.02
        diff = np.abs(rgb - ref[:, None, :]).max(2)
        lum, rlum = rgb.mean(2), ref.mean(1)[:, None]
        match = (diff < 0.07) & (lum > rlum - 0.06) & near_sky & ~conf
        match[lowest + 1:] = False                      # not lakes or anything below the sky
        coarse = np.maximum(coarse, match * np.clip(1 - diff / 0.07, 0, 1) * 1.5).clip(0, 1)
    out = coarse
    for r, eps in ((10, 4e-4), (3, 1e-4)):
        out = np.clip(guided(guide, out, r, eps), 0, 1)
    # sharpen the soft edge a little, keep it anti-aliased
    out = np.clip((out - 0.38) * 3.0 + 0.5, 0, 1)        # lean toward sky: covers bright fringes
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(folder, "sky.png"), optimize=True)
    return out


def fix_edge_depth(folder, fine):
    """Thin things against the sky (treetops, wires, roof edges) come out of the
    depth model blended with the sky, i.e. far away. Give pixels near the sky
    the depth of the nearest solid thing around them instead."""
    from PIL import ImageFilter
    p = os.path.join(folder, "maps.png")
    m = np.asarray(Image.open(p).convert("RGB")).copy()
    h, w = m.shape[:2]
    sky = np.asarray(Image.fromarray((fine * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) > 127
    d = m[..., 0].copy()
    d[sky] = 255                                         # sky never wins a minimum
    low = np.asarray(Image.fromarray(d).filter(ImageFilter.MinFilter(15)))
    near = box(sky.astype(np.float32), 10) > 0.01
    fix = near & ~sky
    m[..., 0] = np.where(fix, np.minimum(m[..., 0], low), m[..., 0])
    m[..., 0] = np.where(sky, 255, m[..., 0])
    Image.fromarray(m, "RGB").save(p, optimize=True)


def skyline(sky):
    h, w = sky.shape
    out = []
    for i in range(COLS):
        col = sky[:, int(i * w / COLS):int((i + 1) * w / COLS)].mean(1)
        # walk down from the top while it's mostly sky
        run = np.convolve(col, np.ones(9) / 9, mode="same")
        below = np.nonzero(run < 0.5)[0]
        out.append(round(float(below[0] / h) if len(below) else 1.0, 3))
    return out


def process(folder):
    m = np.asarray(Image.open(os.path.join(folder, "maps.png")).convert("RGB"), dtype=np.float32) / 255
    sky, ground = m[..., 1], m[..., 2]
    water = np.asarray(Image.open(os.path.join(folder, "maps3.png")).convert("RGB"), dtype=np.float32)[..., 0] / 255
    line = skyline(sky)
    fix_edge_depth(folder, fine_sky(folder, sky))
    with open(os.path.join(folder, "Skyline.qml"), "w") as f:
        f.write("// generated by tools/skyline.py: open sky ends at these photo heights, left to right\n")
        f.write("import QtQml\nQtObject { readonly property var y: %s }\n" % line)
    p2 = os.path.join(folder, "maps2.png")
    m2 = np.asarray(Image.open(p2).convert("RGB")).copy()
    mirror = mirror_line((ground > 0.5) | (water > 0.5))
    m2[..., 2] = (np.clip(mirror, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(m2, "RGB").save(p2, optimize=True)
    return line


def write_fireworks_views(root):
    """FireworksViews.qml in a photo library: town and yard views with plenty of
    open sky, used on fireworks nights (daytime ones get relit as night)."""
    import re
    good = []
    for d in sorted(os.listdir(root)):
        parts = d.split("__")
        f = os.path.join(root, d, "Skyline.qml")
        if len(parts) < 3 or parts[1] == "wild" or not os.path.exists(f):
            continue
        ys = sorted(eval(re.search(r"y: (\[.*\])", open(f).read()).group(1)))
        if ys[len(ys) // 2] >= 0.3:
            good.append(d)
    with open(os.path.join(root, "FireworksViews.qml"), "w") as f:
        f.write("// generated by tools/skyline.py: town/yard views with open sky for fireworks\n")
        f.write("import QtQml\nQtObject { readonly property var names: %s }\n" % repr(good).replace("'", '"'))
    return good


if __name__ == "__main__":
    roots = set()
    for d in sys.argv[1:]:
        if os.path.exists(os.path.join(d, "maps.png")):
            line = process(d)
            roots.add(os.path.dirname(os.path.abspath(d.rstrip("/"))))
            print(os.path.basename(d.rstrip("/")), "sky to", min(line), "-", max(line))
    for r in roots:
        print("fireworks views:", write_fireworks_views(r))

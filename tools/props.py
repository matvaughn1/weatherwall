#!/usr/bin/env python3
"""Holiday props placed into a photo, the way people really decorate:

  halloween     pumpkins and carved jack-o'-lanterns on the ground and steps,
                sheet ghosts hanging in nearby trees
  thanksgiving  pumpkins, hay bales and corn-stalk bundles
  christmas     little lit trees in yards, wreaths on walls
  july4         flags on poles, red-white-blue bunting along rooflines
  oktoberfest   blue-and-white pennant bunting, barrels by the walls
  valentine     red/pink heart bunting
  stpatrick     green/white/orange pennant bunting, shamrock bunting
  easter        big painted eggs scattered on the grass

For each photo folder and holiday this writes
  props_<holiday>.png   RGBA: the props (and their soft contact shadows), at up
                        to 1920 px wide, aligned with photo.jpg
  glow_<holiday>.png    RGB: light the props give off at night (lit faces, bulbs)

Props are sized by distance, sit on real ground / walls / rooflines from the
photo's maps, and are hidden wherever something nearer is in front of them.
The wallpaper shader lights them like the rest of the photo (night, rain, fog).

usage: props.py PHOTO_DIR [...]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

W_MAX = 1920
HOLIDAYS = ["halloween", "thanksgiving", "christmas", "july4", "oktoberfest", "valentine", "stpatrick", "easter"]
SS = 3                                    # supersampling for clean edges
LIGHT = np.array([-0.45, -0.65, 0.62])    # from the upper left, toward the viewer
LIGHT /= np.linalg.norm(LIGHT)


# ── small helpers ────────────────────────────────────────────────────────────
def grid(w, h):
    y, x = np.mgrid[0:h * SS, 0:w * SS].astype(np.float32)
    return (x + 0.5) / SS, (y + 0.5) / SS


def down(a):
    """Average SSxSS blocks (anti-aliasing)."""
    h, w = a.shape[0] // SS, a.shape[1] // SS
    return a[:h * SS, :w * SS].reshape(h, SS, w, SS, *a.shape[2:]).mean((1, 3))


def shade(n, base, amb=0.38, spec=0.0, shin=24):
    lam = np.clip((n * LIGHT).sum(-1), 0, 1)
    col = base * (amb + (1 - amb) * lam)[..., None]
    if spec:
        h = LIGHT + np.array([0, 0, 1.0]); h /= np.linalg.norm(h)
        col += spec * np.clip((n * h).sum(-1), 0, 1)[..., None] ** shin
    return col


def sphere_normal(u, v):
    z = np.sqrt(np.clip(1 - u * u - v * v, 0, 1))
    return np.dstack([u, v, z])


class Sprite:
    """rgba (straight alpha) + glow, both float, plus the anchor (bottom centre)."""
    def __init__(self, rgb, a, glow=None):
        self.rgb, self.a = rgb, a
        self.glow = glow if glow is not None else np.zeros_like(rgb)


# ── the props ────────────────────────────────────────────────────────────────
def pumpkin(h, rng, carved=False):
    w = int(h * (1.25 + rng.uniform(-0.1, 0.15)))
    X, Y = grid(w, h)
    bodyH = h * 0.86
    cx, cy = w / 2, h - bodyH / 2
    u = (X - cx) / (w / 2)
    v = (Y - cy) / (bodyH / 2)
    # ribbed outline: a bit wider at each rib
    ribs = 7 + rng.integers(0, 3)
    r = 1 - 0.035 * np.abs(np.cos(u * np.pi * ribs / 2.3))
    inside = (u * u + v * v) < r * r
    n = sphere_normal(np.clip(u, -1, 1) * 0.98, np.clip(v, -1, 1) * 0.98)
    # rib grooves bend the normal sideways
    groove = np.sin(u * np.pi * ribs / 2.0 + rng.uniform(0, 1))
    n[..., 0] += groove * 0.35 * (1 - np.abs(u))
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    hue = rng.uniform(-0.06, 0.06)
    base = np.array([0.86 + hue, 0.40 + hue * 1.5, 0.05]) * rng.uniform(0.8, 1.05)
    rgb = shade(n, base[None, None, :], amb=0.32, spec=0.18, shin=18)
    rgb *= (0.82 + 0.18 * (np.abs(groove) ** 0.5))[..., None]        # darker in the grooves
    a = inside.astype(np.float32)
    # stem
    sx = cx + rng.uniform(-0.06, 0.06) * w
    stem = (np.abs(X - sx - (Y - (h - bodyH)) * 0.25) < h * 0.055) & (Y > h - bodyH - h * 0.12) & (Y < h - bodyH + h * 0.12)
    rgb[stem] = np.array([0.30, 0.25, 0.10]) * (0.7 + 0.3 * ((X[stem] - sx) < 0))[:, None]
    a[stem] = 1
    glow = np.zeros_like(rgb)
    if carved:
        # two triangle eyes, a nose and a jagged grin; the candle inside lights them
        fu, fv = u, v
        eye = lambda ex: (fv > -0.42) & (fv < -0.08) & (np.abs(fu - ex) < (fv + 0.42) * 0.55)
        nose = (fv > -0.05) & (fv < 0.12) & (np.abs(fu) < (fv + 0.05) * 0.6)
        mouth = (fv > 0.2) & (fv < 0.5 + 0.08 * np.sign(np.sin(fu * 18))) & (np.abs(fu) < 0.55 - (fv - 0.2) * 0.5)
        mouth &= ~((fv < 0.32) & (np.abs(np.sin(fu * 9)) < 0.3))      # teeth
        face = (eye(-0.33) | eye(0.33) | nose | mouth) & inside
        rgb[face] = np.array([0.95, 0.62, 0.18]) * 0.9
        glow[face] = np.array([1.0, 0.55, 0.12]) * 1.6
    return Sprite(down(rgb), down(a), down(glow))


def egg(h, rng):
    w = int(h * 0.74)
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2)
    v = (Y - h / 2) / (h / 2)
    # egg: narrower toward the top
    k = 1 + 0.18 * v
    uu = u / k
    inside = uu * uu + v * v < 1
    n = sphere_normal(np.clip(uu, -1, 1), np.clip(v, -1, 1))
    pastel = [(0.95, 0.55, 0.70), (0.55, 0.75, 0.98), (0.98, 0.90, 0.45), (0.60, 0.90, 0.60),
              (0.80, 0.62, 0.95), (1.0, 0.70, 0.45)]
    c1, c2 = (np.array(pastel[i]) for i in rng.choice(len(pastel), 2, replace=False))
    style = rng.integers(0, 3)
    if style == 0:          # bands
        pat = (np.sin(v * np.pi * 3.5) > 0.55)
    elif style == 1:        # zigzag
        pat = np.abs(v - 0.12 * np.sign(np.sin(u * 10))) < 0.14
    else:                   # dots
        pat = (np.sin(u * 9) * np.sin(v * 9)) > 0.6
    base = np.where(pat[..., None], c2, c1)
    rgb = shade(n, base, amb=0.42, spec=0.35, shin=30)
    return Sprite(down(rgb), down(inside.astype(np.float32)))


def flag(h, rng):
    """A small US flag on a pole, waving."""
    w = int(h * 0.75)
    X, Y = grid(w, h)
    rgb = np.zeros(X.shape + (3,), np.float32)
    a = np.zeros(X.shape, np.float32)
    pole = np.abs(X - w * 0.08) < max(0.6, h * 0.012)
    rgb[pole] = (0.75, 0.72, 0.65); a[pole] = 1
    fx0, fy0, fw, fh = w * 0.09, h * 0.04, w * 0.88, h * 0.42
    s = (X - fx0) / fw
    wave = np.sin(s * 7 + rng.uniform(0, 6)) * 0.04 * s
    t = (Y - fy0) / fh - wave
    on = (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1)
    stripe = (np.floor(t * 13) % 2 == 0)
    col = np.where(stripe[..., None], np.array([0.70, 0.08, 0.12]), np.array([0.93, 0.93, 0.90]))
    canton = (s < 0.4) & (t < 7 / 13)
    col = np.where(canton[..., None], np.array([0.10, 0.14, 0.40]), col)
    stars = canton & ((np.sin(s * 70) * np.sin(t * 60)) > 0.75)
    col = np.where(stars[..., None], np.array([0.95, 0.95, 0.95]), col)
    light = 0.78 + 0.22 * np.cos(s * 7 + 1.0)                          # folds catch light
    rgb[on] = (col * light[..., None])[on]
    a[on] = 1
    return Sprite(down(rgb), down(a))


def hay_bale(h, rng):
    w = int(h * 1.6)
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2); v = (Y - h / 2) / (h / 2)
    inside = (np.abs(u) < 1) & (np.abs(v) < 1)
    n = np.dstack([np.zeros_like(u), np.where(v < -0.6, -1.0, 0.0), np.where(v < -0.6, 0.3, 1.0)])
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    straw = 0.75 + 0.25 * np.sin(Y * 3.1 + np.sin(X * 0.7) * 3) * np.sin(X * 1.7)
    base = np.array([0.78, 0.65, 0.35])[None, None, :] * straw[..., None]
    rgb = shade(n, base, amb=0.45)
    twine = (np.abs(u - 0.45) < 0.03) | (np.abs(u + 0.45) < 0.03)
    rgb[twine & inside] *= 0.55
    return Sprite(down(rgb), down(inside.astype(np.float32)))


def corn_stalks(h, rng):
    w = int(h * 0.55)
    X, Y = grid(w, h)
    a = np.zeros(X.shape, np.float32)
    rgb = np.zeros(X.shape + (3,), np.float32)
    for i in range(14):
        x0 = w / 2 + rng.uniform(-0.12, 0.12) * w
        lean = rng.uniform(-0.25, 0.25)
        top = rng.uniform(0.0, 0.15) * h
        line = (np.abs(X - x0 - (h - Y) * lean) < max(0.7, h * 0.012)) & (Y > top)
        c = np.array([0.72, 0.60, 0.36]) * rng.uniform(0.75, 1.1)
        rgb[line] = c; a[line] = 1
        for _ in range(3):                                            # dry leaves
            ly = rng.uniform(0.15, 0.7) * h
            d = rng.choice([-1, 1])
            leaf = (np.abs((Y - ly) - (X - x0 - (h - ly) * lean) * 0.5 * d) < h * 0.012) & \
                   ((X - x0 - (h - ly) * lean) * d > 0) & ((X - x0 - (h - ly) * lean) * d < h * 0.18)
            rgb[leaf] = c * 0.9; a[leaf] = 1
    band = (np.abs(Y - h * 0.55) < h * 0.02) & (a > 0)
    rgb[band] = (0.55, 0.42, 0.22)
    return Sprite(down(rgb), down(a))


def xmas_tree(h, rng, pal):
    w = int(h * 0.62)
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2); t = Y / h
    rgb = np.zeros(X.shape + (3,), np.float32)
    a = np.zeros(X.shape, np.float32)
    glow = np.zeros_like(rgb)
    # tiers of branches
    tiers = 4
    inside = np.zeros(X.shape, bool)
    for k in range(tiers):
        t0 = 0.05 + k * 0.2
        t1 = t0 + 0.32
        tt = (t - t0) / (t1 - t0)
        inside |= (tt > 0) & (tt < 1) & (np.abs(u) < tt * (0.45 + 0.55 * (k + 1) / tiers))
    inside &= t < 0.9
    needles = 0.7 + 0.3 * np.sin(X * 2.3 + Y * 1.7) * np.sin(X * 1.1 - Y * 2.9)
    base = np.array([0.08, 0.26, 0.12])[None, None, :] * needles[..., None]
    rgb = base * (0.55 + 0.45 * (1 - u))[..., None]
    a = inside.astype(np.float32)
    trunk = (np.abs(u) < 0.08) & (t >= 0.88)
    rgb[trunk] = (0.25, 0.16, 0.08); a[trunk] = 1
    # bulbs
    ys, xs = np.nonzero(inside)
    if len(xs):
        for i in rng.choice(len(xs), size=min(len(xs), int(16 + h * 0.6)), replace=False):
            c = np.array(pal[rng.integers(0, len(pal))])
            r = max(1.0, h * 0.018)
            d = (X - X[ys[i], xs[i]]) ** 2 + (Y - Y[ys[i], xs[i]]) ** 2
            m = d < r * r
            rgb[m] = c * 0.8 + 0.2; glow[m] = c * 2.0
    return Sprite(down(rgb), down(a), down(glow))


def wreath(h, rng):
    w = h
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2); v = (Y - h / 2) / (h / 2)
    r = np.sqrt(u * u + v * v)
    ring = (r > 0.45) & (r < 0.95)
    tex = 0.6 + 0.4 * np.sin(np.arctan2(v, u) * 40 + r * 30)
    rgb = np.array([0.08, 0.28, 0.12])[None, None, :] * tex[..., None] * (0.7 + 0.3 * (-v + 1) / 2)[..., None]
    a = ring.astype(np.float32)
    bow = (np.abs(v - 0.72) < 0.16) & (np.abs(u) < 0.42) | ((v > 0.72) & (v < 1.0) & (np.abs(u) - (v - 0.72) * 0.6 < 0.12) & (np.abs(u) > 0.05))
    rgb[bow] = (0.75, 0.06, 0.08); a[bow] = 1
    return Sprite(down(rgb), down(a))


def ghost(h, rng):
    w = int(h * 0.62)
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2); t = Y / h
    width = np.where(t < 0.3, np.sqrt(np.clip(1 - ((0.3 - t) / 0.3) ** 2, 0, 1)) * 0.55, 0.55 + (t - 0.3) * 0.7)
    hem = 0.92 + 0.05 * np.sin(u * 14)
    inside = (np.abs(u) < width) & (t < hem)
    rgb = np.ones(X.shape + (3,), np.float32) * 0.92
    rgb *= (0.75 + 0.25 * np.cos(u * 3.0 + np.sin(t * 9) * 0.5))[..., None]   # cloth folds
    eyes = ((u + 0.2) ** 2 + ((t - 0.22) * 1.6) ** 2 < 0.012) | ((u - 0.2) ** 2 + ((t - 0.22) * 1.6) ** 2 < 0.012)
    rgb[eyes] = 0.05
    a = inside.astype(np.float32) * 0.92
    string = (np.abs(u) < 0.02) & (t < 0.03)
    a[string] = 1; rgb[string] = 0.3
    return Sprite(down(rgb), down(a))


def barrel(h, rng):
    w = int(h * 0.72)
    X, Y = grid(w, h)
    u = (X - w / 2) / (w / 2); v = (Y - h / 2) / (h / 2)
    bulge = 1 - 0.12 * v * v
    inside = (np.abs(u) < bulge) & (np.abs(v) < 1)
    n = np.dstack([u / bulge, np.zeros_like(u), np.sqrt(np.clip(1 - (u / bulge) ** 2, 0, 1))])
    staves = 0.85 + 0.15 * np.cos(u * 22)
    base = np.array([0.42, 0.25, 0.12])[None, None, :] * staves[..., None]
    rgb = shade(n, base, amb=0.35, spec=0.1)
    hoops = (np.abs(np.abs(v) - 0.7) < 0.05)
    rgb[hoops] = shade(n, np.array([0.25, 0.25, 0.27])[None, None, :], amb=0.35, spec=0.4)[hoops]
    return Sprite(down(rgb), down(inside.astype(np.float32)))


# ── bunting: drawn straight onto the layer between two roofline points ───────
def draw_bunting(layer, alpha, p0, p1, colours, size, rng, kind="pennant"):
    (x0, y0), (x1, y1) = p0, p1
    L = np.hypot(x1 - x0, y1 - y0)
    sag = L * rng.uniform(0.08, 0.14)
    n = max(3, int(L / (size * 1.25)))
    H, Wd = alpha.shape
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + 4 * sag * t * (1 - t)))
    # the cord
    for i in range(len(pts) - 1):
        for s in np.linspace(0, 1, 12):
            x = int(pts[i][0] + (pts[i + 1][0] - pts[i][0]) * s)
            y = int(pts[i][1] + (pts[i + 1][1] - pts[i][1]) * s)
            if 0 <= x < Wd and 0 <= y < H:
                layer[y, x] = (0.25, 0.24, 0.22); alpha[y, x] = 1
    yy, xx = np.mgrid[0:H, 0:Wd]
    for i in range(len(pts) - 1):
        cx = (pts[i][0] + pts[i + 1][0]) / 2
        cy = (pts[i][1] + pts[i + 1][1]) / 2
        half = size * 0.45
        x_lo, x_hi = int(cx - half - 2), int(cx + half + 2)
        y_lo, y_hi = int(cy - 2), int(cy + size * 1.1 + 2)
        if x_hi < 0 or x_lo >= Wd or y_hi < 0 or y_lo >= H:
            continue
        sl = (slice(max(0, y_lo), min(H, y_hi)), slice(max(0, x_lo), min(Wd, x_hi)))
        u = (xx[sl] - cx) / half
        v = (yy[sl] - cy) / size
        if kind == "heart":
            hx, hy = u * 1.2, -(v * 2.2 - 1.0)
            m = (hx * hx + hy * hy - 1) ** 3 - hx * hx * hy ** 3 < 0
        elif kind == "shamrock":
            m = np.zeros(u.shape, bool)
            for ang in (np.pi / 2, np.pi / 2 + 2.1, np.pi / 2 - 2.1):
                ox, oy = np.cos(ang) * 0.38, 0.45 - np.sin(ang) * 0.3
                m |= (u - ox) ** 2 + ((v - oy) * 1.8) ** 2 < 0.16
        else:
            m = (v > 0) & (v < 1) & (np.abs(u) < 1 - v)
        c = np.array(colours[i % len(colours)]) * (0.8 + 0.2 * np.cos(u * 2.0))[..., None]
        sub = layer[sl]; suba = alpha[sl]
        sub[m] = c[m]; suba[m] = 1


# ── placement ────────────────────────────────────────────────────────────────
def load_maps(folder, W, H):
    def L(name, ch):
        im = Image.open(os.path.join(folder, name)).convert("RGB").split()[ch]
        return np.asarray(im.resize((W, H), Image.BILINEAR), dtype=np.float32) / 255
    sky = np.asarray(Image.open(os.path.join(folder, "sky.png")).convert("L").resize((W, H), Image.BILINEAR), dtype=np.float32) / 255
    return dict(dist=L("maps.png", 0), ground=L("maps.png", 2), up=L("maps2.png", 0),
                water=L("maps3.png", 0), plants=L("maps3.png", 1), sky=sky)


def size_at(dist, H, scale):
    """Prop height in pixels for something standing at relative distance dist."""
    return H * scale * (1 - dist) ** 1.7


def spots(mask, dist, rng, n, spacing, H, scale, min_px=7, sky=None):
    ys, xs = np.nonzero(mask)
    out = []
    if not len(xs):
        return out
    for i in rng.permutation(len(xs))[:n * 60]:
        x, y = int(xs[i]), int(ys[i])
        h = size_at(dist[y, x], H, scale)
        if h < min_px:
            continue
        # not on roof peaks or ledges: something solid should be behind/above a prop
        if sky is not None and sky[max(0, int(y - h * 1.5)):y, max(0, x - 2):x + 3].max() > 0.5:
            continue
        if any((x - ox) ** 2 + (y - oy) ** 2 < (spacing * max(h, oh)) ** 2 for ox, oy, oh in out):
            continue
        out.append((x, y, h))
        if len(out) >= n:
            break
    return out


def stamp(layer, alpha, glow, sp, x, y, d, maps, shadow=True):
    """Paste a sprite with its bottom centre at (x, y), standing at distance d.
    Hidden wherever the photo has something nearer in front."""
    H, W = alpha.shape
    h, w = sp.a.shape
    x0, y0 = int(x - w / 2), int(y - h)
    xs, ys = slice(max(0, x0), min(W, x0 + w)), slice(max(0, y0), min(H, y0 + h))
    if xs.start >= xs.stop or ys.start >= ys.stop:
        return
    sx = slice(xs.start - x0, xs.stop - x0); sy = slice(ys.start - y0, ys.stop - y0)
    a = sp.a[sy, sx].copy()
    front = maps["dist"][ys, xs] < d - 0.06                      # something nearer
    a[front & (maps["sky"][ys, xs] < 0.5)] = 0
    if shadow:                                                    # soft contact shadow
        sw, sh = int(w * 1.2), max(2, int(h * 0.18))
        yy, xx = np.mgrid[0:sh, 0:sw]
        e = np.clip(1 - (((xx - sw / 2) / (sw / 2)) ** 2 + ((yy - sh / 2) / (sh / 2)) ** 2), 0, 1) * 0.45
        X0, Y0 = int(x - sw / 2 + w * 0.08), int(y - sh / 2)
        for j in range(sh):
            for i in range(0, sw):
                X, Y = X0 + i, Y0 + j
                if 0 <= X < W and 0 <= Y < H and alpha[Y, X] < e[j, i]:
                    layer[Y, X] = 0; alpha[Y, X] = e[j, i]
    m = a[..., None]
    layer[ys, xs] = layer[ys, xs] * (1 - m) + sp.rgb[sy, sx] * m
    alpha[ys, xs] = alpha[ys, xs] * (1 - a) + a
    glow[ys, xs] = np.maximum(glow[ys, xs], sp.glow[sy, sx] * m)


def rooflines(folder, W, H):
    """Roofline points from the holiday-lights layer (bulbs along rooflines)."""
    p = os.path.join(folder, "decor.png")
    if not os.path.exists(p):
        return []
    r = np.asarray(Image.open(p).convert("RGB").split()[0].resize((W, H), Image.BILINEAR)) > 128
    ys, xs = np.nonzero(r)
    return list(zip(xs, ys))


def make(folder, holiday, scene, seed):
    photo = Image.open(os.path.join(folder, "photo.jpg"))
    W = min(W_MAX, photo.width)
    H = round(photo.height * W / photo.width)
    maps = load_maps(folder, W, H)
    rng = np.random.default_rng(seed)
    layer = np.zeros((H, W, 3), np.float32)
    alpha = np.zeros((H, W), np.float32)
    glow = np.zeros((H, W, 3), np.float32)
    built = scene != "wild"
    dist = maps["dist"]
    solid = (maps["sky"] < 0.3) & (maps["water"] < 0.3)
    ground = (maps["ground"] > 0.6) & solid & (dist < 0.8) & (maps["up"] > 0.3)
    wall = solid & (maps["ground"] < 0.2) & (maps["up"] < 0.15) & (maps["plants"] < 0.2) & (dist < 0.6)
    trees = solid & (maps["plants"] > 0.6) & (dist < 0.5)
    n_scale = 1.0 if built else 0.35

    def ground_props(fn, n, scale, spacing=1.2, **kw):
        for x, y, h in spots(ground, dist, rng, max(1, int(n * n_scale)), spacing, H, scale, sky=maps["sky"]):
            stamp(layer, alpha, glow, fn(int(h), rng, **kw) if kw else fn(int(h), rng), x, y, dist[y, x], maps)

    if holiday == "halloween":
        ground_props(pumpkin, 10, 0.10, carved=False)
        ground_props(pumpkin, 8, 0.10, carved=True)
        if built:
            branches = trees & (dist > 0.2) & (np.arange(H)[:, None] < H * 0.75)
            for x, y, h in spots(branches, dist, rng, 4, 3.0, H, 0.11):
                stamp(layer, alpha, glow, ghost(int(h), rng), x, y + int(h * 0.9), dist[y, x], maps, shadow=False)
    elif holiday == "thanksgiving":
        ground_props(pumpkin, 9, 0.09)
        ground_props(hay_bale, 3, 0.12, spacing=2.0)
        if built:
            ground_props(corn_stalks, 3, 0.26, spacing=2.0)
    elif holiday == "christmas":
        pal = [(1.0, 0.15, 0.1), (1.0, 0.75, 0.25), (0.2, 0.9, 0.3), (0.35, 0.5, 1.0)]
        ground_props(lambda h, r: xmas_tree(h, r, pal), 3 if built else 1, 0.30, spacing=2.5)
        if built:
            for x, y, h in spots(wall, dist, rng, 4, 4.0, H, 0.07):
                stamp(layer, alpha, glow, wreath(int(h), rng), x, y, dist[y, x], maps, shadow=False)
    elif holiday == "july4":
        ground_props(flag, 5, 0.22, spacing=2.0)
    elif holiday == "oktoberfest":
        if built:
            ground_props(barrel, 3, 0.12, spacing=2.0)
    elif holiday == "easter":
        ground_props(egg, 26, 0.07, spacing=1.0)

    bunting = {"july4": ([(0.72, 0.08, 0.12), (0.93, 0.93, 0.9), (0.12, 0.18, 0.5)], "pennant"),
               "oktoberfest": ([(0.15, 0.40, 0.80), (0.93, 0.93, 0.92)], "pennant"),
               "valentine": ([(0.80, 0.08, 0.18), (0.98, 0.55, 0.70), (0.95, 0.90, 0.92)], "heart"),
               "stpatrick": ([(0.10, 0.55, 0.20), (0.93, 0.93, 0.9), (0.95, 0.55, 0.12)], "shamrock")}
    if built and holiday in bunting:
        pts = rooflines(folder, W, H)
        if len(pts) > 10:
            idx = rng.permutation(len(pts))
            made = 0
            for i in idx[:400]:
                x0, y0 = pts[i]
                d0 = dist[min(H - 1, y0 + 3), x0]
                span = size_at(d0, H, 1.0) * rng.uniform(0.6, 1.2)
                cands = [(x, y) for x, y in pts[::7] if span * 0.5 < abs(x - x0) < span and abs(y - y0) < span * 0.25]
                if not cands:
                    continue
                x1, y1 = cands[rng.integers(0, len(cands))]
                cols, kind = bunting[holiday]
                draw_bunting(layer, alpha, (x0, y0 + 2), (x1, y1 + 2), cols, max(5, span * 0.07), rng, kind)
                made += 1
                if made >= 3:
                    break

    out_a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    out_rgb = (np.clip(layer, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(np.dstack([out_rgb, out_a]), "RGBA").save(os.path.join(folder, f"props_{holiday}.png"), optimize=True)
    g = Image.fromarray((np.clip(glow / 2, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    g = g.resize((W // 2, H // 2), Image.BILINEAR)
    halo = g.filter(ImageFilter.GaussianBlur(6))
    g = Image.fromarray(np.maximum(np.asarray(g), (np.asarray(halo) * 1.6).clip(0, 255).astype(np.uint8)))
    g.save(os.path.join(folder, f"glow_{holiday}.png"), optimize=True)
    return int((alpha > 0.5).sum())


if __name__ == "__main__":
    args = sys.argv[1:]
    only = None
    if args and args[0].startswith("--only="):
        only = args[0].split("=", 1)[1].split(",")
        args = args[1:]
    for d in args:
        d = d.rstrip("/")
        parts = os.path.basename(d).split("__")
        if len(parts) < 2 or not os.path.exists(os.path.join(d, "sky.png")):
            continue
        scene = parts[1] if len(parts) >= 3 else "wild"
        seed = sum(map(ord, os.path.basename(d)))
        done = {hol: make(d, hol, scene, seed + i) for i, hol in enumerate(HOLIDAYS) if not only or hol in only}
        print(os.path.basename(d), done, flush=True)

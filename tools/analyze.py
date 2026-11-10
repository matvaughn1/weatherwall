#!/usr/bin/env python3
"""Prepare a photo for the Live Weather wallpaper.

Runs a depth model (Depth Anything V2) and a scene-segmentation model
(SegFormer, ADE20K classes) on the photo once, and writes:

  photo.jpg   the photo, at most 3840 px wide
  maps.png    R = distance (0 near .. 1 far, sky = 1)
              G = sky
              B = ground (road, path, grass, floor, field, ...) - gets wet / puddles
  maps2.png   R = faces up (roofs, branches, ground) - where snow settles
              G = light sources (windows, lamps, bright warm spots) - glow at night
              B = mirror line for reflections: screen y of the top of the ground
                  or water region in this column, so puddles and lakes reflect
  maps3.png   R = water (lakes, rivers) - already reflective, no snow
              G = plants (trees, grass, bushes)
  No alpha channels: Qt premultiplies alpha on load, which would wipe the data.

usage: analyze.py SRC_IMAGE OUT_DIR
"""
import os
import sys

import numpy as np
from PIL import Image

MAP_W = 1280          # maps are smooth; this is plenty

_models = {}


def models():
    if not _models:
        import torch
        from transformers import (AutoImageProcessor, AutoModelForDepthEstimation,
                                  SegformerForSemanticSegmentation)
        torch.set_num_threads(max(1, os.cpu_count() - 2))
        _models["dproc"] = AutoImageProcessor.from_pretrained("depth-anything/Depth-Anything-V2-Small-hf")
        _models["depth"] = AutoModelForDepthEstimation.from_pretrained("depth-anything/Depth-Anything-V2-Small-hf").eval()
        _models["sproc"] = AutoImageProcessor.from_pretrained("nvidia/segformer-b4-finetuned-ade-512-512")
        _models["seg"] = SegformerForSemanticSegmentation.from_pretrained("nvidia/segformer-b4-finetuned-ade-512-512").eval()
    return _models


def class_ids(model, names):
    lut = {v.lower(): int(k) for k, v in model.config.id2label.items()}
    ids = []
    for n in names:
        for label, i in lut.items():
            if n in [s.strip() for s in label.split(";")] or label == n:
                ids.append(i)
    return ids


def run_models(img):
    import torch
    m = models()
    w, h = img.size
    with torch.no_grad():
        d_in = m["dproc"](images=img, return_tensors="pt")
        depth = m["depth"](**d_in).predicted_depth            # relative inverse depth: big = near
        depth = torch.nn.functional.interpolate(depth[:, None], size=(h, w), mode="bicubic")[0, 0].numpy()

        s_in = m["sproc"](images=img, return_tensors="pt")
        logits = m["seg"](**s_in).logits
        logits = torch.nn.functional.interpolate(logits, size=(h, w), mode="bilinear")
        labels = logits.argmax(1)[0].numpy()
    return depth, labels


def blur(a, r=3, passes=3):
    """Approximate gaussian blur: repeated separable box blur."""
    k = 2 * r + 1
    for _ in range(passes):
        a = np.pad(a, ((r, r), (0, 0)), mode="edge")
        c = np.cumsum(a, axis=0); c = np.vstack([np.zeros((1, a.shape[1]), a.dtype), c])
        a = (c[k:] - c[:-k]) / k
        a = np.pad(a, ((0, 0), (r, r)), mode="edge")
        c = np.cumsum(a, axis=1); c = np.hstack([np.zeros((a.shape[0], 1), a.dtype), c])
        a = (c[:, k:] - c[:, :-k]) / k
    return a


def norm(a):
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)


def scene_type(labels, seg):
    """wild, town or yard, from how much of the frame is buildings / fences / garden."""
    def frac(names):
        return float(np.isin(labels, class_ids(seg, names)).mean())
    built = frac(["building", "edifice", "house", "skyscraper", "tower", "awning", "shop", "store",
                  "streetlight", "street lamp", "car", "auto", "automobile", "bus", "signboard", "sign"])
    yard = frac(["fence", "fencing", "railing", "rail", "bannister", "balustrade", "porch", "chair",
                 "bench", "pot", "flowerpot", "swimming pool", "table", "deck chair", "lawn"])
    road = frac(["road", "route", "sidewalk", "pavement"])
    if built > 0.10 or (built > 0.04 and road > 0.08):
        return "town"
    if yard > 0.03 or built > 0.03:
        return "yard"
    return "wild"


def make_decor(photo_size, labels, seg, dist, plants, out, scene):
    """Holiday lights for a photo: bulbs along building rooflines and eaves,
    plus some scattered through nearby trees. Written at full photo size:
      decor.png  R = bulb, G = which of the 3 palette colours, B = glow
    """
    from PIL import ImageDraw, ImageFilter
    W, H = photo_size
    h, w = labels.shape
    sx, sy = W / w, H / h
    rng = np.random.default_rng(1234)
    built = np.isin(labels, class_ids(seg, ["building", "edifice", "house", "skyscraper", "tower", "awning"]))

    bulbs = []                                         # (x, y, size) in full-res pixels
    if scene != "wild":
        # top edges of buildings: building here, not building a couple of pixels above
        edge = np.zeros_like(built)
        edge[3:] = built[3:] & ~built[:-3]
        # keep edges with something farther (sky / background) above them, i.e. real rooflines
        farther = np.zeros_like(dist, dtype=bool)
        farther[4:] = dist[:-4] > dist[4:] + 0.02
        edge &= farther
        ys, xs = np.nonzero(edge)
        # walk across the image: one bulb every `step` map pixels per roofline
        step = 7
        taken = set()
        for x, y in sorted(zip(xs, ys)):
            key = (x // step, y // 6)
            if key in taken:
                continue
            taken.add(key)
            near = 1.0 - dist[y, x]                    # nearer houses get bigger bulbs
            bulbs.append((x * sx, (y + 1.5) * sy, 2.2 + 4.5 * near))
        # lights wound through trees close to the houses
        trees = plants.astype(bool) & (dist < 0.55)
        ty, tx = np.nonzero(trees)
        if len(tx):
            n = min(len(tx) // 150, 220)
            for k in rng.choice(len(tx), size=n, replace=False):
                near = 1.0 - dist[ty[k], tx[k]]
                bulbs.append((tx[k] * sx, ty[k] * sy, 1.8 + 3.5 * near))

    bulb = Image.new("L", (W, H), 0)
    pal = Image.new("L", (W, H), 0)
    phase = Image.new("L", (W, H), 0)
    db, dp, dph = ImageDraw.Draw(bulb), ImageDraw.Draw(pal), ImageDraw.Draw(phase)
    for i, (x, y, r) in enumerate(bulbs):
        box = [x - r, y - r, x + r, y + r]
        db.ellipse(box, fill=255)
        dp.ellipse([x - r * 2, y - r * 2, x + r * 2, y + r * 2], fill=(i % 3) * 127)
        dph.ellipse([x - r * 2, y - r * 2, x + r * 2, y + r * 2], fill=int(rng.integers(0, 255)))
    glow = bulb.filter(ImageFilter.GaussianBlur(14))
    glow = Image.eval(glow, lambda v: min(255, v * 4))
    bulb = bulb.filter(ImageFilter.GaussianBlur(1.2))
    Image.merge("RGB", (bulb, pal, glow)).save(os.path.join(out, "decor.png"), optimize=True)
    return len(bulbs)


def decor_only(folder, scene):
    """Add decor.png to a photo folder analysed before decorations existed."""
    img = Image.open(os.path.join(folder, "photo.jpg")).convert("RGB")
    small = img.resize((MAP_W, round(img.height * MAP_W / img.width)), Image.LANCZOS)
    depth, labels = run_models(small)
    dist = 1.0 - norm(depth)
    seg = models()["seg"]
    plants = np.isin(labels, class_ids(seg, ["tree", "plant", "flora", "plant life", "palm", "palm tree"])).astype(np.float32)
    return make_decor(img.size, labels, seg, dist, plants, folder, scene)


def classify_only(src):
    """Just the scene type, for tagging photos analysed before tags existed."""
    img = Image.open(src).convert("RGB")
    small = img.resize((MAP_W, round(img.height * MAP_W / img.width)), Image.LANCZOS)
    _, labels = run_models(small)
    return scene_type(labels, models()["seg"])


def main(src, out):
    os.makedirs(out, exist_ok=True)
    img = Image.open(src).convert("RGB")
    if img.width > 3840:
        img = img.resize((3840, round(img.height * 3840 / img.width)), Image.LANCZOS)
    img.save(os.path.join(out, "photo.jpg"), quality=90, optimize=True)

    small = img.resize((MAP_W, round(img.height * MAP_W / img.width)), Image.LANCZOS)
    depth, labels = run_models(small)
    seg = models()["seg"]

    def mask(names):
        return np.isin(labels, class_ids(seg, names)).astype(np.float32)

    sky = mask(["sky"])
    ground = mask(["road", "route", "sidewalk", "pavement", "floor", "flooring", "grass", "earth", "ground",
                   "field", "path", "sand", "dirt track", "land", "soil", "runway", "stairs", "step",
                   "stairway", "staircase", "rug", "carpet"])
    water = mask(["water", "sea", "river", "lake", "swimming pool", "pool"])
    plants = mask(["tree", "plant", "flora", "plant life", "palm", "palm tree", "grass", "flower"])
    windows = mask(["windowpane", "window", "streetlight", "street lamp", "lamp", "light", "light source",
                    "chandelier", "sconce", "lantern", "candle"])

    # distance: invert relative depth, sky is as far as it gets
    dist = 1.0 - norm(depth)
    dist = np.where(sky > 0.5, 1.0, dist * 0.97)

    # faces up: depth increases going up the screen (ground, roofs, tops of branches)
    dsm = blur(norm(depth).astype(np.float32), 2)
    gy = np.zeros_like(dsm)
    gy[1:-1] = dsm[2:] - dsm[:-2]                         # near (big) below far (small) => positive
    up = np.clip(gy * 60.0, 0, 1)
    up = np.maximum(up, ground * 0.9)
    up = up * (1 - sky) * (1 - water)
    # tops of things: pixels with sky / far background just above them
    above_far = np.zeros_like(dist)
    above_far[3:] = np.clip((dist[:-3] - dist[3:]) * 6.0, 0, 1)
    up = np.clip(np.maximum(up, above_far) * (1 - sky) * (1 - water), 0, 1)

    # the segmenter misses snowy or unusual ground: add up-facing areas low in the frame
    rows = np.linspace(0, 1, ground.shape[0], dtype=np.float32)[:, None]
    ground = np.maximum(ground, (gy * 60 > 0.35) * (rows > 0.5) * (1 - plants) * (1 - water))

    # light sources: window/lamp classes that are bright, plus small bright warm spots
    rgb = np.asarray(small, dtype=np.float32) / 255
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    warm = np.clip((rgb[..., 0] - rgb[..., 2]) * 2.5, 0, 1)
    lights = np.maximum(windows * np.clip(lum * 1.4, 0.15, 1), np.clip((lum - 0.72) * 4, 0, 1) * warm)
    lights *= 1 - sky

    # mirror line: for each ground pixel, the top of its ground run in that column
    h = ground.shape[0]
    mirror = np.zeros_like(ground)
    wet = np.maximum(ground, water)
    for x in range(ground.shape[1]):
        col = wet[:, x] > 0.5
        top = -1
        for y in range(h):
            if col[y]:
                if top < 0:
                    top = y
                mirror[y, x] = top / h
            else:
                top = -1

    def to8(a):
        return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)

    Image.fromarray(np.dstack([to8(dist), to8(sky), to8(ground)]), "RGB") \
        .save(os.path.join(out, "maps.png"), optimize=True)
    Image.fromarray(np.dstack([to8(up), to8(lights), to8(mirror)]), "RGB") \
        .save(os.path.join(out, "maps2.png"), optimize=True)
    Image.fromarray(np.dstack([to8(water), to8(plants), np.zeros_like(to8(water))]), "RGB") \
        .save(os.path.join(out, "maps3.png"), optimize=True)
    scene = scene_type(labels, seg)
    trees = np.isin(labels, class_ids(seg, ["tree", "plant", "flora", "plant life", "palm", "palm tree"])).astype(np.float32)
    make_decor(img.size, labels, seg, dist, trees, out, scene)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import skyline
    import props
    skyline.process(out)
    seed = sum(map(ord, os.path.basename(out.rstrip("/"))))
    for i, hol in enumerate(props.HOLIDAYS):
        props.make(out, hol, scene, seed + i)
    return scene


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

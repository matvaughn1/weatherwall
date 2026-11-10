#!/usr/bin/env python3
"""Prepare your own photo for the Live Weather wallpaper.

usage: add_custom.py /path/to/photo.jpg
Analyses it into ~/.local/share/weatherwall/custom/<custom|custom_night>__<scene>__<name>/
and prints that folder on the last line (the settings page reads it).
"""
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze  # noqa: E402

src = sys.argv[1]
name = re.sub(r"[^a-z0-9]+", "-", os.path.splitext(os.path.basename(src))[0].lower()).strip("-")[:48] or "photo"
root = os.path.expanduser("~/.local/share/weatherwall/custom")
os.makedirs(root, exist_ok=True)

# a dark photo is treated as a night shot (not relit, lights glow)
lum = np.asarray(Image.open(src).convert("L").resize((256, 256)), dtype=np.float32).mean() / 255
bucket = "custom_night" if lum < 0.22 else "custom"

tmp = os.path.join(root, f".tmp-{name}")
scene = analyze.main(src, tmp)
dest = os.path.join(root, f"{bucket}__{scene}__{name}")
if os.path.exists(dest):
    import shutil
    shutil.rmtree(dest)
os.replace(tmp, dest)
print(dest)

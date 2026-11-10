#!/usr/bin/env python3
"""Add the wild/town/yard tag to photo folders named before tags existed:
<bucket>__<name>  ->  <bucket>__<scene>__<name>"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import analyze  # noqa: E402

root = sys.argv[1]
for d in sorted(os.listdir(root)):
    parts = d.split("__")
    if len(parts) != 2 or d.startswith("."):
        continue
    scene = analyze.classify_only(os.path.join(root, d, "photo.jpg"))
    os.rename(os.path.join(root, d), os.path.join(root, f"{parts[0]}__{scene}__{parts[1]}"))
    print(scene, d, flush=True)

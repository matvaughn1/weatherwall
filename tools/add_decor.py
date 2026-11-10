#!/usr/bin/env python3
"""Add holiday decorations (decor.png) to photo folders that don't have one yet."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import analyze  # noqa: E402

root = sys.argv[1]
for d in sorted(os.listdir(root)):
    f = os.path.join(root, d)
    if d.startswith(".") or not os.path.isdir(f) or os.path.exists(os.path.join(f, "decor.png")):
        continue
    parts = d.split("__")
    scene = parts[1] if len(parts) >= 3 else "wild"
    print(scene, d, analyze.decor_only(f, scene), "bulbs", flush=True)

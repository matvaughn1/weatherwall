#!/usr/bin/env python3
"""Download the hand-picked photos at full size, analyse them, and install
them into the wallpaper package as photos/<bucket>__<name>/.

usage: build_library.py CANDIDATES_DIR picks.txt PACKAGE_PHOTOS_DIR

picks.txt lines:  <bucket> <candidate-sheet> <index> [<index> ...]
e.g.              snow_night snow_night 3 7 10
"""
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import analyze                     # noqa: E402
import commons_search as cs        # noqa: E402


def full_url(c):
    """Ask Commons for a 3840 px rendition (or the original if it's smaller)."""
    r = cs.api({"action": "query", "format": "json", "titles": c["title"],
                "prop": "imageinfo", "iiprop": "url", "iiurlwidth": 3840})
    ii = next(iter(r["query"]["pages"].values()))["imageinfo"][0]
    return ii.get("thumburl") or ii["url"]


def slug(title):
    t = re.sub(r"^File:|\(Unsplash[^)]*\)|\.\w+$", "", title)
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")[:48] or "photo"


def main(cands_dir, picks, out_dir):
    credits = []
    os.makedirs(out_dir, exist_ok=True)
    for line in open(picks):
        line = line.split("#")[0].split()
        if len(line) < 3:
            continue
        bucket, sheet, idxs = line[0], line[1], [int(i) for i in line[2:]]
        cands = json.load(open(os.path.join(cands_dir, sheet, "cands.json")))
        for i in idxs:
            c = cands[i]
            name = slug(c["title"])
            done = [d for d in os.listdir(out_dir) if d.startswith(f"{bucket}__") and d.endswith("__" + name)]
            credits.append(f"- {bucket}: [{c['title'][5:]}]({c['page']}) — {c['artist'] or 'unknown'}, {c['license']}")
            if done:
                continue
            raw = os.path.join(cands_dir, sheet, f"{i:02d}.full.jpg")
            if not os.path.exists(raw):
                for attempt in range(5):
                    try:
                        req = urllib.request.Request(full_url(c), headers={"User-Agent": cs.UA})
                        resp = urllib.request.urlopen(req, timeout=120)
                        if not resp.headers.get("Content-Type", "").startswith("image/"):
                            raise ValueError("not an image: " + resp.headers.get("Content-Type", ""))
                        open(raw, "wb").write(resp.read())
                        break
                    except Exception as e:
                        print("  retry", c["title"], e, flush=True)
                        time.sleep(8 * (attempt + 1))
                time.sleep(1)
            print(f"{bucket}: {c['title']}", flush=True)
            try:
                tmp = os.path.join(out_dir, f".tmp-{name}")
                scene = analyze.main(raw, tmp)
                os.replace(tmp, os.path.join(out_dir, f"{bucket}__{scene}__{name}"))
            except Exception as e:
                print("  SKIPPED", c["title"], e, flush=True)
    with open(os.path.join(out_dir, "CREDITS.md"), "w") as f:
        f.write("# Photo credits\n\nAll photos are from Wikimedia Commons (originally Unsplash), "
                "released under CC0 / public domain.\n\n" + "\n".join(credits) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])

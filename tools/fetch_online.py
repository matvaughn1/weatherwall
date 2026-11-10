#!/usr/bin/env python3
"""Fetch fresh photos for the Live Weather wallpaper.

Searches Wikimedia Commons for CC0 (Unsplash) landscape photos for each scene
type, downloads a few new ones, analyses them (tools/analyze.py) and stores
them in ~/.local/share/weatherwall/photos/<bucket>__<name>/. Keeps at most
KEEP photos per type, dropping the oldest. Run daily by a systemd user timer.
"""
import os
import random
import re
import shutil
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze                     # noqa: E402
import commons_search as cs        # noqa: E402

DEST = os.path.expanduser("~/.local/share/weatherwall/photos")
CACHE = os.path.expanduser("~/.cache/weatherwall")
KEEP = 8
NEW_PER_RUN = 2

QUERIES = {
    "clear_day":   ["mountain lake", "lake cabin", "backyard garden", "small town street", "village"],
    "clear_night": ["milky way mountains", "night sky cabin", "town at night", "house at night"],
    "dusk":        ["sunset mountains", "sunset lake", "golden hour valley"],
    "dusk_winter": ["winter sunset", "snowy sunset mountains"],
    "cloudy_day":  ["cloudy mountains", "overcast lake", "moody mountains"],
    "snow_day":    ["snowy forest", "winter cabin snow", "snowy village", "snowy backyard", "snowy street"],
    "snow_night":  ["snowy night", "winter night lights", "snow street night", "snowy house night"],
    "rain_day":    ["rainy forest", "rainy street", "rain garden", "rainy town"],
    "rain_night":  ["rainy night street", "wet street night", "rain night city"],
    "fog":         ["foggy forest", "misty lake", "fog mountains"],
    "storm":       ["storm clouds landscape", "thunderstorm", "stormy sky"],
    "autumn":      ["autumn forest", "fall colors lake", "autumn mountains"],
    "christmas":   ["christmas market night", "christmas lights street", "snowy christmas village"],
    "halloween":   ["jack o lantern night", "pumpkin patch"],
}


def slug(title):
    t = re.sub(r"^File:|\(Unsplash[^)]*\)|\.\w+$", "", title)
    return re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")[:48] or "photo"


def existing(bucket):
    if not os.path.isdir(DEST):
        return []
    return sorted((d for d in os.listdir(DEST) if d.startswith(bucket + "__")),
                  key=lambda d: os.path.getmtime(os.path.join(DEST, d)))


def fetch_bucket(bucket, queries):
    have = {d.split("__")[-1] for d in existing(bucket)}
    # also skip anything already bundled with the wallpaper
    bundled = os.path.join(os.path.dirname(__file__), "..", "package", "contents", "photos")
    if os.path.isdir(bundled):
        have |= {d.split("__")[-1] for d in os.listdir(bundled) if "__" in d}
    q = random.choice(queries)
    try:
        results = cs.search(q + " intitle:Unsplash", 40)
    except Exception as e:
        print(f"{bucket}: search failed: {e}")
        return
    results = [r for r in results if r["license"].upper().startswith(("CC0", "PUBLIC")) and slug(r["title"]) not in have]
    random.shuffle(results)
    added = 0
    for r in results:
        if added >= NEW_PER_RUN:
            break
        name = slug(r["title"])
        os.makedirs(CACHE, exist_ok=True)
        raw = os.path.join(CACHE, name + ".jpg")
        try:
            info = cs.api({"action": "query", "format": "json", "titles": r["title"],
                           "prop": "imageinfo", "iiprop": "url", "iiurlwidth": 3840})
            ii = next(iter(info["query"]["pages"].values()))["imageinfo"][0]
            req = urllib.request.Request(ii.get("thumburl") or ii["url"], headers={"User-Agent": cs.UA})
            resp = urllib.request.urlopen(req, timeout=120)
            if not resp.headers.get("Content-Type", "").startswith("image/"):
                continue
            open(raw, "wb").write(resp.read())
            tmp = os.path.join(DEST, f".tmp-{bucket}__{name}")
            scene = analyze.main(raw, tmp)
            os.replace(tmp, os.path.join(DEST, f"{bucket}__{scene}__{name}"))
            print(f"{bucket}: added {r['title']}")
            added += 1
        except Exception as e:
            print(f"{bucket}: skipped {r['title']}: {e}")
        finally:
            if os.path.exists(raw):
                os.remove(raw)
        time.sleep(2)
    for old in existing(bucket)[:-KEEP] if len(existing(bucket)) > KEEP else []:
        shutil.rmtree(os.path.join(DEST, old), ignore_errors=True)


def main():
    os.makedirs(DEST, exist_ok=True)
    buckets = sys.argv[1:] or list(QUERIES)
    for b in buckets:
        fetch_bucket(b, QUERIES[b])
        time.sleep(3)


if __name__ == "__main__":
    main()

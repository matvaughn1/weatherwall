#!/usr/bin/env python3
"""Gather candidate photos per bucket and build a numbered contact sheet.
usage: gather.py OUTDIR bucket "query1" "query2" ..."""
import json, os, subprocess, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
import commons_search as cs

out, bucket, queries = sys.argv[1], sys.argv[2], sys.argv[3:]
d = os.path.join(out, bucket); os.makedirs(d, exist_ok=True)
seen, cands = set(), []
for q in queries:
    for attempt in range(4):
        try:
            res = cs.search(q + " intitle:Unsplash", 40); break
        except Exception as e:
            time.sleep(6 * (attempt + 1)); res = []
    for r in res:
        if r["title"] not in seen and r["license"].upper().startswith(("CC0", "PUBLIC")):
            seen.add(r["title"]); cands.append(r)
    time.sleep(2)
cands = cands[:24]
for i, c in enumerate(cands):
    p = os.path.join(d, f"{i:02d}.jpg")
    if not os.path.exists(p):
        for attempt in range(4):
            try:
                req = urllib.request.Request(c["thumb"], headers={"User-Agent": cs.UA})
                open(p, "wb").write(urllib.request.urlopen(req, timeout=30).read()); break
            except Exception:
                time.sleep(5 * (attempt + 1))
        time.sleep(0.5)
json.dump(cands, open(os.path.join(d, "cands.json"), "w"), indent=1)
files = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
subprocess.run(["montage", *[os.path.join(d, f) for f in files], "-label", "%t", "-geometry", "300x170+3+3",
                "-tile", "6x", "-pointsize", "18", os.path.join(out, bucket + "_sheet.jpg")], check=False)
subprocess.run(["sh", "-c", f"cd {d} && montage -label '%t' *.jpg -geometry 300x170+3+3 -tile 6x -pointsize 18 ../{bucket}_sheet.jpg"])
print(bucket, len(cands))

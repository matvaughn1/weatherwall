#!/usr/bin/env python3
"""Search Wikimedia Commons for wide, high-res photos.
usage: commons_search.py "query" [limit]  -> JSON lines: title, w, h, thumb, page, license, artist"""
import json, sys, urllib.parse, urllib.request, re

UA = "weatherwall-wallpaper/1.0 (personal KDE wallpaper; contact via github matvaughn1)"

def api(params):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=30))

def search(q, limit=20):
    r = api({"action": "query", "format": "json", "generator": "search",
             "gsrsearch": f"{q} filetype:bitmap filew:>2400", "gsrnamespace": 6, "gsrlimit": 50,
             "prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": 480})
    out = []
    for p in (r.get("query", {}).get("pages", {}) or {}).values():
        ii = p.get("imageinfo", [{}])[0]
        w, h = ii.get("width", 0), ii.get("height", 1)
        if w / h < 1.4 or w < 2400:
            continue
        md = ii.get("extmetadata", {})
        lic = md.get("LicenseShortName", {}).get("value", "")
        artist = re.sub("<[^>]+>", "", md.get("Artist", {}).get("value", "")).strip()
        out.append({"title": p["title"], "w": w, "h": h, "thumb": ii.get("thumburl"),
                    "page": ii.get("descriptionurl"), "license": lic, "artist": artist[:80]})
    return out[:limit]

if __name__ == "__main__":
    for r in search(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 20):
        print(json.dumps(r))

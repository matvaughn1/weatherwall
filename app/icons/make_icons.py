#!/usr/bin/env python3
"""Draws the app icons (sun behind a cloud): app.ico, app.icns, tray.png, tray-mac.png."""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
S = 1024


def cloud(d, ox, oy, k, fill):
    for cx, cy, r in ((0.40, 0.66, 0.16), (0.56, 0.55, 0.21), (0.72, 0.66, 0.15)):
        d.ellipse([(ox + cx * k - r * k), (oy + cy * k - r * k), (ox + cx * k + r * k), (oy + cy * k + r * k)], fill=fill)
    d.rounded_rectangle([ox + 0.24 * k, oy + 0.62 * k, ox + 0.87 * k, oy + 0.81 * k], radius=0.095 * k, fill=fill)


def app_icon():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = Image.new("RGBA", (S, S))
    g = ImageDraw.Draw(bg)
    for y in range(S):                       # dusk sky gradient
        t = y / S
        g.line([(0, y), (S, y)], fill=(int(40 + 200 * t), int(90 + 80 * t), int(190 - 40 * t), 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=200, fill=255)
    im.paste(bg, (0, 0), mask)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([250, 150, 650, 550], fill=(255, 210, 90, 160))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    d = ImageDraw.Draw(im)
    d.ellipse([300, 200, 600, 500], fill=(255, 214, 92, 255))
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cloud(ImageDraw.Draw(sh), 40, 70, S * 0.95, (20, 30, 60, 110))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
    cloud(d, 30, 40, S * 0.95, (250, 251, 255, 255))
    return im


def tray(colour, sun):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if sun:
        d.ellipse([170, 110, 560, 500], fill=sun)
    cloud(d, -40, 60, S * 1.05, colour)
    return im.resize((64, 64), Image.LANCZOS)


icon = app_icon()
icon.save(os.path.join(HERE, "app.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
icon.save(os.path.join(HERE, "app.icns"))
icon.resize((256, 256), Image.LANCZOS).save(os.path.join(HERE, "app.png"))
tray((245, 247, 255, 255), (255, 205, 70, 255)).save(os.path.join(HERE, "tray.png"))
tray((0, 0, 0, 255), None).save(os.path.join(HERE, "tray-mac.png"))
print("icons written")

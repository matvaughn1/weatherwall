# Live Weather

An animated desktop wallpaper that shows the weather where you are, right now.
Real photos (or a drawn village) get the live sky, sun position, clouds, rain on
the glass, snow, rolling fog and thunderstorms from
[Open-Meteo](https://open-meteo.com/), plus holiday decorations, string lights
and fireworks on New Year's Eve and the 4th of July.

Runs on **KDE Plasma 6** (as a wallpaper plugin), **Windows 10/11** and **macOS 12+**.

## Install

Grab the file for your system from the
[latest release](https://github.com/matvaughn1/weatherwall/releases/latest).

### Windows
1. Download `LiveWeather-<version>-Windows-Setup.exe` and run it.
   Windows SmartScreen may warn that the app isn't recognised. Click
   **More info → Run anyway** (the installer isn't code-signed).
2. It starts straight away and appears in the system tray. Click the tray icon
   for settings (set your town first).

Prefer no installer? Unzip `LiveWeather-<version>-Windows-Portable.zip` and run
`Live Weather.exe`.

### macOS
1. Download `LiveWeather-<version>-macOS.dmg`, open it and drag **Live Weather**
   to Applications.
2. The app isn't notarised by Apple, so the first time, **right-click it → Open →
   Open**. If macOS says it's damaged, run this once in Terminal:
   `xattr -cr "/Applications/Live Weather.app"`
3. It lives in the menu bar (sun-and-cloud icon). Click it for settings.

### KDE Plasma 6 (Linux)
Download `LiveWeather-<version>-KDE-Plasma.zip`, then either
- right-click the desktop → **Configure Desktop and Wallpaper → Get New Plugins →
  Install from File** and pick the zip, or
- run `kpackagetool6 -t Plasma/Wallpaper -i LiveWeather-<version>-KDE-Plasma.zip`

Then choose **Live Weather** as the wallpaper type. Each screen has its own settings.

## Settings

Location (search by town), °F/°C, real photos or the drawn village, how often the
view changes, towns / nature / both, string lights (where, on/off/auto, colours,
multicolour or random), holiday decorations, and preview modes for trying any
weather, time of day or holiday.

## Building from source

- **Plasma plugin:** `./build.sh` compiles the shaders (needs Qt 6 `qsb`) and
  installs the package with `kpackagetool6`. Restart plasmashell afterwards.
- **Windows/macOS app:** `app/` is a small Qt 6 C++ program that loads the same
  QML from `package/`. `cmake -S app -B app/build && cmake --build app/build`,
  then `"app/build/Live Weather" --window` to try it in a window.
  Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed.
- **Photo tools** (`tools/`, Linux, optional): Python with `torch`, `transformers`,
  `numpy` and `pillow`. `analyze.py` makes the depth/sky/ground maps for a photo
  (Depth Anything V2 + SegFormer); `fetch_online.py` pulls more public-domain
  photos from Wikimedia Commons; `add_custom.py` prepares your own photo.

## Credits

Photos are public domain (CC0) from Wikimedia Commons, originally Unsplash. See
[package/contents/photos/CREDITS.md](package/contents/photos/CREDITS.md).
Weather data by [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).

Licensed under the GNU GPL v3 or later.
